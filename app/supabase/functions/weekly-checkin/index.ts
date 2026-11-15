// weekly-checkin — 주간 체크인 (spec F4).
//
// 입력 (POST JSON): { tz_offset_min?: number }   — 없거나 비정상이면 KST(+540).
// 출력:
//   * 기록 2일 미만:  { insufficient: true, week_start, days_logged, headline, report: null, ... }
//                     (LLM 호출 없음, 저장 안 함)
//   * 그 외:          { week_start, report: {emoji, headline, wins[1~2], pattern,
//                       experiments[3]{if_then, why}, note, days_logged},
//                       chosen_experiment, completed_at }
//
// week_start = 요청 시각(로컬) 기준 "직전 완료 주"의 월요일. 일요일 17시 이후면
// 이번 주 월요일, 그 외엔 지난 주 월요일. 같은 (user, week_start) 행이 있으면 LLM
// 없이 그대로 돌려준다 (주당 LLM 1회). 실험 선택(chosen_experiment / completed_at)
// 은 클라이언트가 RLS 로 직접 UPDATE 한다.
//
// LLM 에는 기록 집계·체중 변화·지난 실험·모드·GLP-1 사용 여부(coach_context 동의 시)
// 만 보낸다. 투약 기록·용량은 보내지 않는다.
//
// ENV: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ANTHROPIC_API_KEY, ANTHROPIC_MODEL

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { CLAUDE_MODEL, claudeJson } from '../_shared/claude.ts';
import {
  buildUserPrompt,
  type CheckinReport,
  type EntryRow,
  insufficientBody,
  MIN_DAYS,
  postProcessReport,
  RESPONSE_SCHEMA,
  safePrevExperiment,
  summarizeWeek,
  SYSTEM_PROMPT,
  weekRangeUtc,
  weekStartFor,
} from './schema.ts';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const DEFAULT_TZ_OFFSET_MIN = 540; // Asia/Seoul

function parseTzOffset(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    return DEFAULT_TZ_OFFSET_MIN;
  }
  if (raw < -720 || raw > 840) return DEFAULT_TZ_OFFSET_MIN;
  return Math.round(raw);
}

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...extra },
  });
}

/// PostgREST numeric 은 number 로 오지만 드리프트 대비 문자열도 허용.
function toNum(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

async function getUserId(req: Request): Promise<string | null> {
  const auth = req.headers.get('Authorization') ?? '';
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!jwt || !jwt.includes('.') || jwt.startsWith('sb_')) return null;
  const { data, error } = await admin.auth.getUser(jwt);
  if (error) {
    console.error('getUser error', error.message);
    return null;
  }
  return data?.user?.id ?? null;
}

type CheckinRow = {
  week_start: string;
  report_json: CheckinReport;
  chosen_experiment: string | null;
  completed_at: string | null;
};

function rowBody(r: CheckinRow) {
  return {
    week_start: r.week_start,
    report: r.report_json,
    chosen_experiment: r.chosen_experiment,
    completed_at: r.completed_at,
  };
}

async function findRow(userId: string, weekStart: string) {
  const { data, error } = await admin
    .from('weekly_checkins')
    .select('week_start, report_json, chosen_experiment, completed_at')
    .eq('user_id', userId)
    .eq('week_start', weekStart)
    .maybeSingle();
  if (error) throw new Error(`weekly_checkins select: ${error.message}`);
  return data as CheckinRow | null;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  const userId = await getUserId(req);
  if (!userId) return json({ error: 'unauthorized' }, 401);

  let tzOffsetMin = DEFAULT_TZ_OFFSET_MIN;
  try {
    tzOffsetMin = parseTzOffset((await req.json())?.tz_offset_min);
  } catch {
    // body 없음 → 기본값
  }

  const weekStart = weekStartFor(Date.now(), tzOffsetMin);

  try {
    // 1) 캐시 — 이번 체크인 주의 행이 있으면 그대로.
    const existing = await findRow(userId, weekStart);
    if (existing) return json(rowBody(existing), 200, { 'x-foodiet-cache': 'hit' });

    // 2) 한 주 기록
    const { fromIso, toIso } = weekRangeUtc(weekStart, tzOffsetMin);
    const { data: entries, error: entErr } = await admin
      .from('entries')
      .select(
        'captured_at, kcal_total, shared_with_count, meal_slot, eating_type, macros',
      )
      .eq('user_id', userId)
      .eq('status', 'done')
      .gte('captured_at', fromIso)
      .lt('captured_at', toIso)
      .order('captured_at', { ascending: true });
    if (entErr) throw new Error(`entries select: ${entErr.message}`);

    const summary = summarizeWeek(
      (entries ?? []) as EntryRow[],
      tzOffsetMin,
      weekStart,
    );
    if (summary.daysLogged < MIN_DAYS) {
      return json(insufficientBody(weekStart, summary.daysLogged), 200, {
        'x-foodiet-state': 'insufficient',
      });
    }

    // 3) 맥락 — 프로필·체중·지난 실험·GLP-1 (실패해도 기본값으로 진행)
    const [profileRes, weightRes, prevRes, medRes] = await Promise.all([
      admin
        .from('profiles')
        .select('nickname, daily_kcal_target, goal_weight_kg, weight_kg, sex, goal_mode')
        .eq('user_id', userId)
        .maybeSingle(),
      admin
        .from('weight_logs')
        .select('logged_at, weight_kg')
        .eq('user_id', userId)
        .gte('logged_at', fromIso)
        .lt('logged_at', toIso)
        .order('logged_at', { ascending: true }),
      admin
        .from('weekly_checkins')
        .select('chosen_experiment, week_start')
        .eq('user_id', userId)
        .lt('week_start', weekStart)
        .not('chosen_experiment', 'is', null)
        .order('week_start', { ascending: false })
        .limit(1),
      admin
        .from('medication_plans')
        .select('active, coach_context')
        .eq('user_id', userId)
        .maybeSingle(),
    ]);

    const p = (profileRes.data ?? {}) as Record<string, unknown>;
    const weightKg = toNum(p.weight_kg);
    const goalKg = toNum(p.goal_weight_kg);
    let mode: 'lose' | 'maintain' | 'gain' =
      p.goal_mode === 'maintain' || p.goal_mode === 'gain' ? p.goal_mode : 'lose';
    // 결정사항: lose 인데 목표 체중 > 현재 체중이면 실효 모드는 gain.
    if (mode === 'lose' && weightKg !== null && goalKg !== null && goalKg > weightKg) {
      mode = 'gain';
    }

    const weights = ((weightRes.data ?? []) as Array<{ weight_kg: number | string }>)
      .map((w) => Number(w.weight_kg))
      .filter((w) => Number.isFinite(w) && w > 0);
    const med = medRes.data as { active?: boolean; coach_context?: boolean } | null;
    // 사용자가 직접 쓴 실험일 수 있다 → 위험 문구면 프롬프트에서 뺀다.
    const prev = safePrevExperiment(prevRes.data?.[0]?.chosen_experiment);

    const userPrompt = buildUserPrompt({
      nickname: (p.nickname as string) || '친구',
      // 프로필 목표가 하한 아래여도 LLM 에는 하한 이상만 '목표'로 보낸다.
      targetKcal: Math.max(
        toNum(p.daily_kcal_target) ?? 1800,
        p.sex === 'male' ? 1500 : 1200,
      ),
      floorKcal: p.sex === 'male' ? 1500 : 1200,
      mode,
      glp1: med?.active === true && med?.coach_context !== false,
      prevExperiment: prev,
      weekStart,
      summary,
      weight: weights.length === 0
        ? null
        : { first: weights[0], last: weights[weights.length - 1], count: weights.length },
    });

    // 4) LLM
    let raw: unknown;
    try {
      raw = await claudeJson<unknown>({
        tag: 'weekly-checkin',
        system: SYSTEM_PROMPT,
        content: userPrompt,
        schema: RESPONSE_SCHEMA,
        maxTokens: 8000,
      });
    } catch (e) {
      console.error('claude failed', e);
      return json({ error: 'llm_failed' }, 502);
    }
    const report: CheckinReport = {
      ...postProcessReport(raw),
      days_logged: summary.daysLogged,
    };

    // 5) 저장 — 동시 요청이 먼저 넣었으면(23505) 그 행을 돌려준다.
    const { error: insErr } = await admin.from('weekly_checkins').insert({
      user_id: userId,
      week_start: weekStart,
      report_json: report,
      source_model: CLAUDE_MODEL,
    });
    if (insErr) {
      if (insErr.code === '23505') {
        const raced = await findRow(userId, weekStart);
        if (raced) return json(rowBody(raced));
      }
      // 저장이 안 돼도 이번 응답은 돌려준다 (다음 호출 때 다시 생성될 수 있음).
      console.error('weekly_checkins insert failed', insErr.message);
    }

    return json({
      week_start: weekStart,
      report,
      chosen_experiment: null,
      completed_at: null,
    });
  } catch (e) {
    console.error('weekly-checkin failed', e);
    return json({ error: 'internal' }, 500);
  }
});
