// analyze-entry — 업로드된 사진을 멀티모달 LLM 으로 분석.
//
// 기획안 §4.2 / §4.3 / §8.2 / §9 / §18.1 #7.
// 트리거: Flutter 클라이언트가 업로드 직후 invoke(). 재시도는 클라이언트 또는
//         cron 이 status='pending' 을 폴링해서 수행.
//
// 순서
//   1) entries row 조회 (service role — RLS 우회)
//   2) food-photos 버킷에서 사진 다운로드 (base64 로 Claude 에 직접 전달)
//   3) 사용자 컨텍스트 조회 (목표 kcal·이 끼니 전 오늘 섭취·목표 모드·GLP-1 여부).
//      실패해도 무시하고 기본 프롬프트로 진행.
//   4) Claude Vision 호출 (structured outputs: json_schema) — _shared/claude.ts
//      응답에 한 끼 피드백(feedback) 포함. 스키마·후처리는 schema.ts.
//   5) entries UPDATE(+feedback) + entry_items 다중 INSERT.
//      피드백이 깨졌거나 저장이 안 돼도 기록은 done 처리 (구버전 앱 호환).
//   6) 신뢰도 낮거나 meal_slot 경계시간이면 coach_messages 로 "확인해줘" 전송
//
// ENV (Supabase Dashboard → Edge Functions → Secrets):
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   ANTHROPIC_API_KEY
//   ANTHROPIC_MODEL        (default 'claude-opus-5-5')

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { claudeJson } from '../_shared/claude.ts';
import {
  buildSystemPrompt,
  buildUserPrompt,
  type Feedback,
  type LlmResult,
  postProcessFeedback,
  RESPONSE_SCHEMA,
} from './schema.ts';
import {
  buildUserContextLine,
  effectiveGoalMode,
  localDayStartUtc,
  type UserContext,
} from './context.ts';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const BUCKET = 'food-photos';

// §9 — meal_slot 경계시간 (로컬 시각 기준). LLM 결정에 더해 시각 prior 로 사용.
function timeBasedMealSlot(isoCapturedAt: string, locale: string) {
  const d = new Date(isoCapturedAt);
  // locale 의 시간대는 추후 profiles.timezone 확장 시 반영. 지금은 Asia/Seoul 가정.
  const tz = locale?.startsWith('ko') ? 'Asia/Seoul' : 'UTC';
  const local = new Date(
    d.toLocaleString('en-US', { timeZone: tz }),
  );
  const h = local.getHours() + local.getMinutes() / 60;
  if (h >= 5 && h < 10.5) return 'breakfast';
  if (h >= 10.5 && h < 14.5) return 'lunch';
  if (h >= 17 && h < 21) return 'dinner';
  if (h >= 21 || h < 5) return 'late_night';
  return null; // 14:30~17:00 는 간식 구간 — LLM 판정에 맡긴다.
}

function timeBoundaryMinutes(isoCapturedAt: string, locale: string) {
  const d = new Date(isoCapturedAt);
  const tz = locale?.startsWith('ko') ? 'Asia/Seoul' : 'UTC';
  const local = new Date(d.toLocaleString('en-US', { timeZone: tz }));
  const h = local.getHours() + local.getMinutes() / 60;
  // 각 경계로부터 ±30분 이내면 경계시간 = 신뢰도 낮춤 → 확인 요청 trigger.
  const boundaries = [5, 10.5, 14.5, 17, 21];
  return boundaries.some((b) => Math.abs(h - b) < 0.5);
}

// Storage 객체 → base64. Claude 가 서명 URL 을 직접 fetch 하게 두지 않고 함수가
// 바로 넘긴다 (외부 fetch 실패 지점 제거). 클라이언트는 1600px q80 JPEG 로 올린다.
function toBase64(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(bin);
}

const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'] as const;
type ImageType = typeof IMAGE_TYPES[number];

function clamp01(x: number) {
  return Number.isFinite(x) ? Math.min(1, Math.max(0, x)) : 0;
}

async function analyze(
  photo: Blob,
  capturedAt: string,
  locale: string,
  contextLine: string | null,
) {
  const priorSlot = timeBasedMealSlot(capturedAt, locale) ?? 'unknown';
  const systemPrompt = buildSystemPrompt(priorSlot);
  const userPrompt = buildUserPrompt(capturedAt, locale, contextLine);

  const mediaType: ImageType = (IMAGE_TYPES as readonly string[]).includes(photo.type)
    ? photo.type as ImageType
    : 'image/jpeg';
  const parsed = await claudeJson<LlmResult>({
    tag: 'analyze-entry',
    system: systemPrompt,
    content: [
      {
        type: 'image',
        source: {
          type: 'base64',
          media_type: mediaType,
          data: toBase64(new Uint8Array(await photo.arrayBuffer())),
        },
      },
      { type: 'text', text: userPrompt },
    ],
    schema: RESPONSE_SCHEMA,
  });
  // structured outputs 는 minimum/maximum 을 강제하지 못하므로 여기서 0..1 로 맞춘다.
  parsed.confidence = clamp01(parsed.confidence);
  for (const it of parsed.items) it.confidence = clamp01(it.confidence);
  return parsed;
}

// ── 사용자 컨텍스트 (피드백 개인화) ──────────────────────────────────
// 각 조회는 독립적으로 실패할 수 있다(예: 0017 미적용이면 goal_mode 컬럼 없음).
// 실패한 항목만 빠지고, 전부 실패하면 null → 기본 프롬프트.
async function safeQuery<T>(
  label: string,
  q: PromiseLike<{ data: T | null; error: unknown }>,
): Promise<T | null> {
  try {
    const { data, error } = await q;
    if (error) {
      console.error(`user context ${label} error`, error);
      return null;
    }
    return data;
  } catch (e) {
    console.error(`user context ${label} threw`, e);
    return null;
  }
}

type ProfileRow = {
  daily_kcal_target: number | null;
  sex: string | null;
  weight_kg: number | null;
  goal_weight_kg: number | null;
};
type TodayRow = {
  id: string;
  kcal_total: number | null;
  shared_with_count: number | null;
  status: string | null;
};

async function loadUserContext(entry: {
  id: string;
  user_id: string;
  captured_at: string;
  locale: string | null;
}): Promise<string | null> {
  try {
    const userId = entry.user_id;
    // 오늘 = 이 사진의 촬영 시각이 속한 로컬 날짜 (갤러리 사진은 과거일 수 있다).
    const tzOffsetMin = (entry.locale ?? 'ko').startsWith('ko') ? 540 : 0;
    const dayStart = localDayStartUtc(entry.captured_at, tzOffsetMin);

    const [profile, modeRow, medRow, rows] = await Promise.all([
      safeQuery<ProfileRow>('profile', admin
        .from('profiles')
        .select('daily_kcal_target, sex, weight_kg, goal_weight_kg')
        .eq('user_id', userId)
        .maybeSingle()),
      safeQuery<{ goal_mode: string | null }>('goal_mode', admin
        .from('profiles')
        .select('goal_mode')
        .eq('user_id', userId)
        .maybeSingle()),
      safeQuery<{ active: boolean | null; coach_context: boolean | null }>(
        'medication',
        admin
          .from('medication_plans')
          .select('active, coach_context')
          .eq('user_id', userId)
          .maybeSingle(),
      ),
      // 이 끼니까지 포함해 가져와 이 사진의 shared_with_count 도 같이 얻는다.
      safeQuery<TodayRow[]>('today', admin
        .from('entries')
        .select('id, kcal_total, shared_with_count, status')
        .eq('user_id', userId)
        .gte('captured_at', dayStart)
        .lte('captured_at', entry.captured_at)),
    ]);

    if (!profile && !modeRow && !medRow && !rows) return null;

    let priorKcalToday: number | null = null;
    let sharedWithCount = 1;
    if (rows) {
      priorKcalToday = 0;
      for (const r of rows) {
        const n = Math.max(1, Number(r.shared_with_count) || 1);
        if (r.id === entry.id) {
          sharedWithCount = n;
          continue;
        }
        if (r.status !== 'done' || typeof r.kcal_total !== 'number') continue;
        priorKcalToday += r.kcal_total / n;
      }
    }

    const num = (x: unknown) => (x == null ? null : Number(x));
    const ctx: UserContext = {
      dailyKcalTarget: num(profile?.daily_kcal_target),
      priorKcalToday,
      mode: effectiveGoalMode(
        modeRow?.goal_mode,
        num(profile?.goal_weight_kg),
        num(profile?.weight_kg),
      ),
      // 'GLP-1 사용 중' 여부만 전달 — 사용자가 coach_context 를 끄면 보내지 않는다.
      // 투약 기록·용량은 LLM 에 보내지 않는다.
      glp1: medRow?.active === true && medRow?.coach_context !== false,
      sex: profile?.sex ?? null,
      sharedWithCount,
    };
    return buildUserContextLine(ctx);
  } catch (e) {
    console.error('user context error', e);
    return null;
  }
}

/// 피드백 후처리가 어떤 이유로 throw 해도 기록 완료를 막지 않는다.
function safeFeedback(raw: unknown): Feedback | null {
  try {
    return postProcessFeedback(raw);
  } catch (e) {
    console.error('feedback postprocess error', e);
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  let entry_id: string | undefined;
  try {
    const body = await req.json();
    entry_id = body?.entry_id;
  } catch {
    return new Response('bad json', { status: 400 });
  }
  if (!entry_id) return new Response('missing entry_id', { status: 400 });

  // 1) entry 조회
  const { data: entry, error: eErr } = await admin
    .from('entries')
    .select('id, user_id, image_path, captured_at, locale, status')
    .eq('id', entry_id)
    .maybeSingle();
  if (eErr) {
    console.error('entries select error', eErr);
    return new Response('db error', { status: 500 });
  }
  if (!entry) return new Response('entry not found', { status: 404 });
  if (entry.status === 'done') {
    return new Response(JSON.stringify({ ok: true, skipped: 'already done' }), {
      headers: { 'content-type': 'application/json' },
    });
  }

  // 2) 사진 다운로드
  const { data: photo, error: dErr } = await admin.storage
    .from(BUCKET)
    .download(entry.image_path);
  if (dErr || !photo) {
    console.error('photo download error', dErr);
    await admin.from('entries').update({ status: 'failed' }).eq('id', entry_id);
    return new Response('photo download failed', { status: 500 });
  }

  // 3) 사용자 컨텍스트 (실패 무시)
  const contextLine = await loadUserContext(entry);

  // 4) LLM 호출
  let result: LlmResult;
  try {
    result = await analyze(
      photo,
      entry.captured_at,
      entry.locale ?? 'ko',
      contextLine,
    );
  } catch (e) {
    console.error('llm error', e);
    await admin.from('entries').update({ status: 'failed' }).eq('id', entry_id);
    return new Response(`llm failed: ${(e as Error).message}`, { status: 502 });
  }

  // 5) entries UPDATE + entry_items INSERT.
  //   title: 상위 2~3 품목 이름으로 요약 (UI 리스트 한 줄 표시용).
  //   너무 긴 이름은 20자 이상이면 "…" 로 자름.
  const topNames = result.items
    .slice()
    .sort((a, b) => b.kcal - a.kcal)
    .slice(0, 3)
    .map((it) => (it.name.length > 20 ? `${it.name.slice(0, 19)}…` : it.name));
  const title = topNames.length === 0
    ? '식사'
    : topNames.length <= 2
      ? topNames.join(' · ')
      : `${topNames.slice(0, 2).join(' · ')} 외 ${result.items.length - 2}`;

  const feedback = safeFeedback(result.feedback);
  const doneRow = {
    status: 'done',
    title,
    meal_slot: result.meal_slot,
    eating_type: result.eating_type,
    kcal_total: result.totals.kcal,
    macros: {
      carb_g: result.totals.carb_g,
      protein_g: result.totals.protein_g,
      fat_g: result.totals.fat_g,
      sodium_mg: result.totals.sodium_mg,
      sugar_g: result.totals.sugar_g,
    },
    confidence: result.confidence,
  };
  let { error: uErr } = await admin
    .from('entries')
    .update(feedback ? { ...doneRow, feedback } : doneRow)
    .eq('id', entry_id);
  if (uErr && feedback) {
    // 피드백 저장 실패(예: feedback 컬럼 미적용)여도 기록은 done 으로 남긴다.
    console.error('entries update with feedback error — retry without', uErr);
    ({ error: uErr } = await admin
      .from('entries')
      .update(doneRow)
      .eq('id', entry_id));
  }
  if (uErr) {
    console.error('entries update error', uErr);
    return new Response('db update failed', { status: 500 });
  }

  if (result.items.length > 0) {
    const { error: iErr } = await admin.from('entry_items').insert(
      result.items.map((it) => ({ entry_id, ...it })),
    );
    if (iErr) console.error('entry_items insert error', iErr);
  }

  // 6) 저신뢰 또는 경계시간 → 확인 요청
  const lowConf = result.confidence < 0.65;
  const boundary = timeBoundaryMinutes(entry.captured_at, entry.locale ?? 'ko');
  if (lowConf || boundary) {
    // coach_messages.scope 는 enum('in_meal','daily','weekly'). 'entry' 넣으면 에러.
    await admin.from('coach_messages').insert({
      user_id: entry.user_id,
      scope: 'in_meal',
      entry_id,
      body_json: {
        kind: 'confirm',
        headline: lowConf
          ? '이거 맞는지 확인해줘 🤔'
          : '끼니 맞는지 봐줄래?',
        why: lowConf
          ? `분석 신뢰도 ${Math.round(result.confidence * 100)}%`
          : '경계시간대라 한 번만 더 체크할게',
        suggested_action: '끼니/품목 수정',
      },
    });
  }

  return new Response(JSON.stringify({ ok: true, entry_id }), {
    headers: { 'content-type': 'application/json' },
  });
});
