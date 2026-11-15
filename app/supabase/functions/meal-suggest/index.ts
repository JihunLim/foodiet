// meal-suggest — "뭐 먹지?" 상황별 추천 + 회식 가이드.
//
// 입력(POST JSON): { situation: 'home'|'convenience'|'delivery'|'eating_out'|'hoesik',
//                    tz_offset_min?: number } + 사용자 JWT (Authorization: Bearer).
// 출력:
//   일반   → { kind:'options', intro, remaining_kcal,
//              options:[{name, kcal, protein_g, carb_g, fat_g, why, tip}] }  (최대 3개,
//              남은 kcal 0 이하면 최대 2개 + 고정 intro)
//   hoesik → { kind:'hoesik', intro, before[], order_tips[], drink_tips[], next_day[] }
//   400 { error:'bad_situation' } / 401 { error:'unauthorized' } /
//   429 { error:'rate_limited' } / 502 { error:'llm_failed' }
//
// 서버가 오늘 섭취(로컬 자정 이후 done entries, 1인분 환산)·목표(하한 적용)·
// 목표 모드·GLP-1 사용 여부(medication_plans.active && coach_context 일 때만, 용량은
// 읽지도 보내지도 않는다)를 조회해 프롬프트에 넣는다.
//
// 레이트리밋: 사용자당 최근 24시간 10회. 서버 전용 llm_calls(kind='meal_suggest')
//   로 집계한다 — 클라이언트가 지울 수 없고, tz_offset_min 조작으로 '오늘' 경계를
//   옮겨도 소용없도록 롤링 창을 쓴다. LLM 호출 전에 1행을 예약하고 실패하면 지운다.
//   집계가 실패하면 비용 보호를 위해 닫힌 쪽(503)으로 실패한다.
//
// ENV: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ANTHROPIC_API_KEY, ANTHROPIC_MODEL

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { claudeJson } from '../_shared/claude.ts';
import {
  buildSystemPrompt,
  buildUserPrompt,
  effectiveMode,
  effectiveTarget,
  HOESIK_SCHEMA,
  type HoesikResponse,
  OPTIONS_SCHEMA,
  type OptionsResponse,
  parseSituation,
  postprocessHoesik,
  postprocessOptions,
  type SuggestContext,
} from './schema.ts';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const DAILY_LIMIT = 10;
const JSON_HEADERS = { 'content-type': 'application/json' };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

// ── 타임존 유틸 (home-coach 와 동일) ──────────────────────────────────
const DEFAULT_TZ_OFFSET_MIN = 540; // Asia/Seoul

function parseTzOffset(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    return DEFAULT_TZ_OFFSET_MIN;
  }
  if (raw < -720 || raw > 840) return DEFAULT_TZ_OFFSET_MIN;
  return Math.round(raw);
}

function nowLocal(tzOffsetMin: number): Date {
  return new Date(Date.now() + tzOffsetMin * 60 * 1000);
}

function startOfTodayUtc(tzOffsetMin: number): string {
  const local = nowLocal(tzOffsetMin);
  const midnightLocalMs = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate(),
  ) - tzOffsetMin * 60 * 1000;
  return new Date(midnightLocalMs).toISOString();
}

async function getUserId(
  req: Request,
): Promise<{ userId: string | null; reason?: string }> {
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth) return { userId: null, reason: 'no_authorization_header' };
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!jwt) return { userId: null, reason: 'malformed_bearer' };
  if (!jwt.includes('.') || jwt.startsWith('sb_')) {
    return { userId: null, reason: 'not_a_jwt' };
  }
  const { data, error } = await admin.auth.getUser(jwt);
  if (error) {
    console.error('getUser error', error);
    return { userId: null, reason: `getUser_error:${error.message}` };
  }
  if (!data?.user) return { userId: null, reason: 'no_user' };
  return { userId: data.user.id };
}

type ProfileRow = {
  daily_kcal_target?: number | null;
  goal_weight_kg?: number | null;
  weight_kg?: number | null;
  sex?: string | null;
  diet_restrictions?: string[] | null;
  goal_mode?: string | null;
};

/// goal_mode 컬럼(0017)이 아직 없는 DB 에서도 죽지 않도록 한 번 폴백.
async function loadProfile(userId: string): Promise<ProfileRow | null> {
  const base = 'daily_kcal_target, goal_weight_kg, weight_kg, sex, diet_restrictions';
  const first = await admin
    .from('profiles')
    .select(`${base}, goal_mode`)
    .eq('user_id', userId)
    .maybeSingle();
  if (!first.error) return (first.data as ProfileRow | null) ?? null;
  console.error('profile select (with goal_mode) failed', first.error);
  const second = await admin
    .from('profiles')
    .select(base)
    .eq('user_id', userId)
    .maybeSingle();
  if (second.error) {
    console.error('profile select failed', second.error);
    return null;
  }
  return (second.data as ProfileRow | null) ?? null;
}

/// GLP-1 사용 여부만. 사용자가 coach_context 를 껐으면 false. 용량·기록은 읽지 않는다.
async function loadGlp1(userId: string): Promise<boolean> {
  const { data, error } = await admin
    .from('medication_plans')
    .select('active, coach_context')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) {
    console.error('medication_plans select failed', error);
    return false;
  }
  return data?.active === true && data?.coach_context === true;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }

  const { userId, reason } = await getUserId(req);
  if (!userId) {
    console.error('unauthorized:', reason);
    return json({ error: 'unauthorized', reason }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = (await req.json()) ?? {};
  } catch {
    // body 없음 → 아래에서 bad_situation.
  }
  const situation = parseSituation(body?.situation);
  if (!situation) return json({ error: 'bad_situation' }, 400);
  const tzOffsetMin = parseTzOffset(body?.tz_offset_min);
  const todayStart = startOfTodayUtc(tzOffsetMin);

  // ── 레이트리밋 (LLM 호출 전) ────────────────────────────────────────
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count: usedToday, error: countErr } = await admin
    .from('llm_calls')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('kind', 'meal_suggest')
    .gte('created_at', since);
  if (countErr) {
    console.error('rate count failed', countErr);
    return json({ error: 'unavailable' }, 503);
  }
  if ((usedToday ?? 0) >= DAILY_LIMIT) {
    return json({ error: 'rate_limited' }, 429);
  }
  // 예약 — 동시 요청이 모두 같은 카운트를 보고 통과하는 걸 줄인다.
  const { data: reserved, error: reserveErr } = await admin
    .from('llm_calls')
    .insert({ user_id: userId, kind: 'meal_suggest' })
    .select('id')
    .single();
  if (reserveErr || !reserved) {
    console.error('rate reserve failed', reserveErr);
    return json({ error: 'unavailable' }, 503);
  }
  const releaseReservation = async () => {
    const { error } = await admin.from('llm_calls').delete().eq(
      'id',
      (reserved as { id: number }).id,
    );
    if (error) console.error('rate release failed', error);
  };

  // ── 컨텍스트 ────────────────────────────────────────────────────────
  const [profile, glp1, entriesRes] = await Promise.all([
    loadProfile(userId),
    loadGlp1(userId),
    admin
      .from('entries')
      .select('title, kcal_total, macros, shared_with_count')
      .eq('user_id', userId)
      .eq('status', 'done')
      .gte('captured_at', todayStart)
      .order('captured_at', { ascending: true }),
  ]);
  if (entriesRes.error) console.error('entries select failed', entriesRes.error);

  let consumed = 0;
  let proteinG = 0;
  const eatenTitles: string[] = [];
  for (const e of entriesRes.data ?? []) {
    const share = Math.max(1, Number(e.shared_with_count) || 1);
    const k = Math.round((Number(e.kcal_total) || 0) / share);
    consumed += k;
    const m = (e.macros as Record<string, unknown> | null) ?? {};
    proteinG += (Number(m.protein_g) || 0) / share;
    eatenTitles.push(`${(e.title as string | null) || '식사'} (${k} kcal)`);
  }

  const target = effectiveTarget(profile?.daily_kcal_target, profile?.sex);
  const remaining = Math.max(0, target - consumed);
  const local = nowLocal(tzOffsetMin);
  const nowLabel = `${String(local.getUTCHours()).padStart(2, '0')}:` +
    `${String(local.getUTCMinutes()).padStart(2, '0')}`;

  const ctx: SuggestContext = {
    situation,
    nowLabel,
    target,
    consumed,
    remaining,
    proteinG,
    eatenTitles,
    mode: effectiveMode(profile),
    glp1,
    dietRestrictions: Array.isArray(profile?.diet_restrictions)
      ? profile!.diet_restrictions!.filter((s) => typeof s === 'string')
      : [],
  };

  // ── LLM ─────────────────────────────────────────────────────────────
  let result: OptionsResponse | HoesikResponse;
  try {
    const raw = await claudeJson<unknown>({
      tag: `meal-suggest:${situation}`,
      system: buildSystemPrompt(ctx),
      content: buildUserPrompt(ctx),
      schema: situation === 'hoesik' ? HOESIK_SCHEMA : OPTIONS_SCHEMA,
    });
    result = situation === 'hoesik'
      ? postprocessHoesik(raw)
      : postprocessOptions(raw, remaining);
  } catch (e) {
    console.error('claude failed', e);
    await releaseReservation();
    return json({ error: 'llm_failed' }, 502);
  }
  if (result.kind === 'options' && result.options.length === 0) {
    // 전부 금지어 등으로 걸러졌다 → 쿼터를 쓰지 않고 실패로.
    console.error('meal-suggest: no options after postprocess');
    await releaseReservation();
    return json({ error: 'llm_failed' }, 502);
  }

  // ── 기록 (분석·디버깅용 로그. 한도는 llm_calls 로 센다) ─────────────
  const { error: insertErr } = await admin.from('coach_messages').insert({
    user_id: userId,
    scope: 'daily',
    body_json: {
      kind: 'meal_suggest',
      persona: 'foodie',
      situation,
      remaining_kcal: remaining,
      result,
    },
  });
  if (insertErr) console.error('coach_messages insert failed', insertErr);

  return json(result);
});
