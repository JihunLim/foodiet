// home-coach — 홈 화면 AI 가이드 카드용 식단 코칭.
//
// 입력: 현재 로그인 사용자의 오늘자 entries(완료분) + 프로필 + 현재 시각(로컬).
//       + 맥락(0017): 지난 7일(오늘 제외) 요약, 최근 14일 주간 체크인 실험,
//         목표 모드(goal_mode → 실효 lose/maintain/gain), GLP-1 사용 여부
//         (medication_plans.active && coach_context — 투약 기록·용량은 보내지 않음),
//         이번 주 식단의 오늘 끼니 이름.
//       맥락 조회는 각각 실패해도 무시한다 (0017 전 DB 에서도 기존처럼 동작).
// 출력: { emoji, headline, review, next_tip, focus } 구조화 JSON 한 건.
// 순수 로직(요약·프롬프트·시그니처)은 ./context.ts.
//
// 트리거: Flutter 클라이언트가 홈 화면에 진입했을 때 invoke(). 완료된 엔트리 수
//         또는 kcal 합계가 바뀔 때마다 클라이언트가 재호출.
//
// coach_messages 에는 저장하지 않는다 (실시간 응답용). 기록은 analyze-entry /
// generate-coach 쪽에서 남긴다.
//
// ENV:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   ANTHROPIC_API_KEY
//   ANTHROPIC_MODEL        (default 'claude-opus-5-5')

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { claudeJson } from '../_shared/claude.ts';
import { safePrevExperiment } from '../weekly-checkin/schema.ts';
import {
  buildSignature,
  buildSystemPrompt,
  buildUserPrompt,
  type CoachResult,
  effectiveMode,
  kcalFloor,
  mondayKey,
  RESPONSE_SCHEMA,
  sanitizeResult,
  shiftDateKey,
  summarizeWeek,
  todayKeyFor,
  todayPlanMeals,
  type WeekRow,
  weekdayIndex,
  weekSummaryKey,
} from './context.ts';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

// ── 타임존 유틸 ───────────────────────────────────────────────────────
// 클라이언트가 전달한 `tz_offset_min` 을 그대로 사용. 유효하지 않으면
// KST(+540) 로 폴백. 값을 함수마다 파라미터로 넘겨 의도를 명시한다.
const DEFAULT_TZ_OFFSET_MIN = 540; // Asia/Seoul

function parseTzOffset(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    return DEFAULT_TZ_OFFSET_MIN;
  }
  // IANA 실제 범위는 -12:00 ~ +14:00. 분 단위로 ±720~840.
  if (raw < -720 || raw > 840) return DEFAULT_TZ_OFFSET_MIN;
  return Math.round(raw);
}

function nowLocal(tzOffsetMin: number): Date {
  return new Date(Date.now() + tzOffsetMin * 60 * 1000);
}

function formatLocalTime(
  iso: string | null | undefined,
  tzOffsetMin: number,
): string {
  if (!iso) return '??:??';
  const d = new Date(new Date(iso).getTime() + tzOffsetMin * 60 * 1000);
  const hh = String(d.getUTCHours()).padStart(2, '0');
  const mm = String(d.getUTCMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

function startOfTodayUtc(tzOffsetMin: number): string {
  const local = nowLocal(tzOffsetMin);
  const midnightLocalMs =
    Date.UTC(
      local.getUTCFullYear(),
      local.getUTCMonth(),
      local.getUTCDate(),
    ) -
    tzOffsetMin * 60 * 1000;
  return new Date(midnightLocalMs).toISOString();
}

async function getUserId(
  req: Request,
): Promise<{ userId: string | null; reason?: string }> {
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth) {
    return { userId: null, reason: 'no_authorization_header' };
  }
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!jwt) {
    return { userId: null, reason: 'malformed_bearer' };
  }
  // JWT 모양이 아닌 publishable key 가 들어온 경우 (sb_publishable_... 등).
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
  nickname: string | null;
  daily_kcal_target: number | null;
  goal_weight_kg: number | null;
  diet_restrictions: string[] | null;
  activity_level: number | null;
  weight_kg: number | null;
  sex: string | null;
};

type TodayEntryRow = {
  title: string | null;
  meal_slot: string | null;
  kcal_total: number | null;
  macros: Record<string, number> | null;
  captured_at: string | null;
  shared_with_count: number | null;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }

  const { userId, reason } = await getUserId(req);
  if (!userId) {
    console.error('unauthorized:', reason);
    return new Response(
      JSON.stringify({ error: 'unauthorized', reason }),
      { status: 401, headers: { 'content-type': 'application/json' } },
    );
  }

  // 클라이언트에서 보낸 디바이스 로컬 타임존 offset (분). 없거나 비정상이면 KST.
  let tzOffsetMin = DEFAULT_TZ_OFFSET_MIN;
  try {
    const reqBody = await req.json();
    tzOffsetMin = parseTzOffset(reqBody?.tz_offset_min);
  } catch {
    // body 없거나 파싱 실패 → 기본값 그대로.
  }

  // 프로필 (select 문자열을 이어 붙이면 supabase-js 가 행 타입을 추론하지 못하므로
  // 명시 타입으로 받는다.)
  const { data: profileData } = await admin
    .from('profiles')
    .select(
      'nickname, locale, daily_kcal_target, goal_weight_kg, goal_deadline, ' +
        'diet_restrictions, activity_level, weight_kg, height_cm, sex, birth_date',
    )
    .eq('user_id', userId)
    .maybeSingle();
  const profile = profileData as unknown as ProfileRow | null;

  // 오늘 완료된 엔트리
  const { data: entriesData } = await admin
    .from('entries')
    .select(
      'title, meal_slot, eating_type, kcal_total, macros, ' +
        'captured_at, shared_with_count, status',
    )
    .eq('user_id', userId)
    .eq('status', 'done')
    .gte('captured_at', startOfTodayUtc(tzOffsetMin))
    .order('captured_at', { ascending: true });
  const entries = entriesData as unknown as TodayEntryRow[] | null;

  // 1인분 환산 합산
  let kcalConsumed = 0;
  let carb = 0;
  let protein = 0;
  let fat = 0;
  let sodium = 0;
  let sugar = 0;
  const eaten: Array<{
    time: string;
    title: string;
    slot: string;
    kcal: number;
  }> = [];
  for (const e of entries ?? []) {
    const share = Math.max(1, (e.shared_with_count as number) ?? 1);
    const k = Math.round(((e.kcal_total as number) ?? 0) / share);
    kcalConsumed += k;
    const m = (e.macros as Record<string, number> | null) ?? {};
    carb += ((m.carb_g as number) ?? 0) / share;
    protein += ((m.protein_g as number) ?? 0) / share;
    fat += ((m.fat_g as number) ?? 0) / share;
    sodium += ((m.sodium_mg as number) ?? 0) / share;
    sugar += ((m.sugar_g as number) ?? 0) / share;
    eaten.push({
      time: formatLocalTime(e.captured_at as string, tzOffsetMin),
      title: (e.title as string) ?? '식사',
      slot: (e.meal_slot as string) ?? 'unknown',
      kcal: k,
    });
  }

  const nickname = (profile?.nickname as string) ?? '유저';
  // 프로필 편집은 800 kcal 까지 허용하므로, 코칭 기준 목표는 안전 하한(남 1500 / 여·미입력
  // 1200) 아래로 내려가지 않게 올린다 — 하한 미만 목표를 "남은 kcal" 로 안내하지 않기 위해.
  const target = Math.max(
    kcalFloor(profile?.sex),
    (profile?.daily_kcal_target as number) ?? 1800,
  );
  const remaining = Math.max(0, target - kcalConsumed);
  const local = nowLocal(tzOffsetMin);
  const nowLabel =
    `${String(local.getUTCHours()).padStart(2, '0')}:` +
    `${String(local.getUTCMinutes()).padStart(2, '0')}`;

  // ── 안티-셰임 가드 (특수 상태는 LLM 대신 결정적 메시지로 보장) ──────────
  // 톤·안전이 중요한 분기라 LLM 변동에 맡기지 않고 고정 문구로 반환한다.
  const localHourNow = local.getUTCHours(); // local 은 offset shift 된 Date.

  // (1) 끊김 회복: 오늘 기록 0건 + 마지막 기록이 3일+ 전 → 따뜻한 환영.
  if (eaten.length === 0) {
    const { data: lastRows } = await admin
      .from('entries')
      .select('captured_at')
      .eq('user_id', userId)
      .eq('status', 'done')
      .lt('captured_at', startOfTodayUtc(tzOffsetMin))
      .order('captured_at', { ascending: false })
      .limit(1);
    const lastBefore = lastRows?.[0]?.captured_at as string | undefined;
    if (lastBefore) {
      const gapDays = Math.floor(
        (Date.now() - new Date(lastBefore).getTime()) / 86400000,
      );
      if (gapDays >= 3) {
        return new Response(JSON.stringify(welcomeBack(nickname, gapDays)), {
          headers: {
            'content-type': 'application/json',
            'x-foodiet-state': 'welcome-back',
          },
        });
      }
    }
  } else if (localHourNow >= 21 && kcalConsumed > 0 && kcalConsumed < 800) {
    // (2) §10.3 극단 절식 가드 — 늦은 시각 + 오늘 섭취가 매우 적음.
    //     "적게 먹어 잘했다" 축하 금지. 미기록일 수도 있으니 비난 없이 챙김 권유.
    return new Response(
      JSON.stringify(careLowIntake(nickname, kcalConsumed < 500)),
      {
        headers: {
          'content-type': 'application/json',
          'x-foodiet-state': 'care-low-intake',
        },
      },
    );
  }

  // ── 맥락 (0017) ─────────────────────────────────────────────────────
  // 각 조회는 독립적으로 실패를 삼킨다 — 0017 전 DB(컬럼·테이블 없음)나 일시 오류여도
  // 기존 오늘 데이터만으로 코칭이 나가야 한다.
  const ctx = await loadCoachContext(userId, tzOffsetMin, profile);

  // ── 캐시 + 레이트리밋 ────────────────────────────────────────────────
  // coach_messages 에 `scope='daily'`, `body_json.kind='home_coach'` 로 저장.
  // 같은 시그니처(= done 엔트리 수·kcal 합 + 날짜·7일 요약·실험·모드·GLP-1·오늘 식단 수)
  // 면 캐시 재사용, 하루 5회 초과 시에도 최신 캐시를 그대로 돌려주어 LLM 비용을 차단.
  //
  // 마지막(5번째) 호출은 로컬 18시 이후에만 허용 — 저녁 식사 타이밍에 맞춘
  // 업데이트를 보장하기 위해 슬롯 하나를 아껴둔다. 사용자 타임존이 파악 안 되면
  // 한국(KST) 기준으로 폴백.
  const signature = buildSignature({
    base: `d:${eaten.length}|k:${kcalConsumed}|c:${carb.toFixed(0)}` +
      `|p:${protein.toFixed(0)}|f:${fat.toFixed(0)}`,
    dayKey: ctx.todayKey,
    weekKey: weekSummaryKey(ctx.week),
    experiment: ctx.experiment,
    mode: ctx.mode,
    glp1: ctx.glp1,
    planCount: ctx.planMeals.length,
    target,
  });
  const DAILY_LIMIT = 5;
  const LAST_SLOT_UNLOCK_HOUR = 18;
  const localHour = local.getUTCHours(); // local 은 이미 offset shift 된 Date.

  const { data: todayCoachRows } = await admin
    .from('coach_messages')
    .select('id, body_json, created_at')
    .eq('user_id', userId)
    .eq('scope', 'daily')
    .gte('created_at', startOfTodayUtc(tzOffsetMin))
    .contains('body_json', { kind: 'home_coach' })
    .order('created_at', { ascending: false });

  const todayRows = todayCoachRows ?? [];
  const latestRow = todayRows[0];
  const latestBody = (latestRow?.body_json ?? null) as
    | (CoachResult & { signature?: string; kind?: string })
    | null;

  // 같은 시그니처면 무조건 캐시.
  if (latestBody && latestBody.signature === signature) {
    return new Response(JSON.stringify(stripMeta(latestBody)), {
      headers: { 'content-type': 'application/json' },
    });
  }
  // 오늘 이미 한도 초과 → 최신 캐시 반환 (없으면 아래로 내려가 1회는 허용).
  if (todayRows.length >= DAILY_LIMIT && latestBody) {
    return new Response(JSON.stringify(stripMeta(latestBody)), {
      headers: {
        'content-type': 'application/json',
        'x-foodiet-cache': 'rate-limited',
      },
    });
  }
  // 5번째 슬롯은 사용자 로컬 18시 이후에만 사용.
  // 즉 이미 4번 썼고 현재 18시 전이라면 추가 생성 없이 최신 캐시 유지.
  if (
    todayRows.length >= DAILY_LIMIT - 1 &&
    localHour < LAST_SLOT_UNLOCK_HOUR &&
    latestBody
  ) {
    return new Response(JSON.stringify(stripMeta(latestBody)), {
      headers: {
        'content-type': 'application/json',
        'x-foodiet-cache': 'reserved-for-evening',
      },
    });
  }

  const systemPrompt = buildSystemPrompt(ctx.floor);
  const userPrompt = buildUserPrompt({
    nickname,
    target,
    floor: ctx.floor,
    goalWeightKg: profile?.goal_weight_kg,
    activityLevel: profile?.activity_level,
    dietRestrictions: Array.isArray(profile?.diet_restrictions)
      ? profile!.diet_restrictions
      : [],
    nowLabel,
    eaten,
    kcalConsumed,
    remaining,
    carb,
    protein,
    fat,
    sodium,
    sugar,
    week: ctx.week,
    experiment: ctx.experiment,
    mode: ctx.mode,
    glp1: ctx.glp1,
    planMeals: ctx.planMeals,
  });

  let parsed: CoachResult;
  try {
    parsed = await claudeJson<CoachResult>({
      tag: 'home-coach',
      system: systemPrompt,
      content: userPrompt,
      schema: RESPONSE_SCHEMA,
    });
  } catch (e) {
    console.error('claude failed', e);
    return new Response(
      JSON.stringify({ error: 'llm_failed' }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  }

  // §7.9 사후 필터. 금지어가 들어간 필드는 중립 문구로 대체.
  parsed = sanitizeResult(parsed);

  // 캐시에 저장. body_json 은 response 에 signature/kind 메타를 덧붙인 형태.
  const cacheBody = {
    ...parsed,
    kind: 'home_coach',
    signature,
    persona: 'foodie',
  };
  const { error: insertErr } = await admin.from('coach_messages').insert({
    user_id: userId,
    scope: 'daily',
    body_json: cacheBody,
  });
  if (insertErr) console.error('coach_messages insert failed', insertErr);

  return new Response(JSON.stringify(parsed), {
    headers: { 'content-type': 'application/json' },
  });
});

// ── 맥락 로딩 (0017) ─────────────────────────────────────────────────
// 5개 조회를 병렬로. 어느 하나가 실패(테이블·컬럼 없음 포함)해도 기본값으로 진행.

type LoadedContext = {
  todayKey: string;
  week: ReturnType<typeof summarizeWeek>;
  experiment: string | null;
  mode: ReturnType<typeof effectiveMode>;
  glp1: boolean;
  floor: number;
  planMeals: ReturnType<typeof todayPlanMeals>;
};

async function loadCoachContext(
  userId: string,
  tzOffsetMin: number,
  profile: ProfileRow | null,
): Promise<LoadedContext> {
  const todayKey = todayKeyFor(Date.now(), tzOffsetMin);
  const todayStartMs = new Date(startOfTodayUtc(tzOffsetMin)).getTime();
  const weekFromIso = new Date(todayStartMs - 7 * 86400000).toISOString();
  const todayStartIso = new Date(todayStartMs).toISOString();

  // 실패를 삼키고 data(또는 null)만 돌려준다.
  const safe = async <T>(
    label: string,
    q: PromiseLike<{ data: T | null; error: unknown }>,
  ): Promise<T | null> => {
    try {
      const { data, error } = await q;
      if (error) {
        console.error(`home-coach context ${label} failed`, error);
        return null;
      }
      return data;
    } catch (e) {
      console.error(`home-coach context ${label} threw`, e);
      return null;
    }
  };

  const [weekRows, modeRow, medRow, checkinRows, planRow] = await Promise.all([
    // 지난 7일(오늘 제외) 완료 기록.
    safe<WeekRow[]>(
      'week',
      admin
        .from('entries')
        .select('captured_at, kcal_total, macros, shared_with_count, meal_slot')
        .eq('user_id', userId)
        .eq('status', 'done')
        .gte('captured_at', weekFromIso)
        .lt('captured_at', todayStartIso) as unknown as PromiseLike<
          { data: WeekRow[] | null; error: unknown }
        >,
    ),
    // goal_mode 는 0017 컬럼 — 기존 프로필 select 와 분리해 실패가 번지지 않게.
    safe<{ goal_mode: string | null }>(
      'goal_mode',
      admin
        .from('profiles')
        .select('goal_mode')
        .eq('user_id', userId)
        .maybeSingle() as unknown as PromiseLike<
          { data: { goal_mode: string | null } | null; error: unknown }
        >,
    ),
    // GLP-1: 사용 여부만. 투약 기록·용량은 LLM 에 보내지 않는다.
    safe<{ active: boolean | null; coach_context: boolean | null }>(
      'medication',
      admin
        .from('medication_plans')
        .select('active, coach_context')
        .eq('user_id', userId)
        .maybeSingle() as unknown as PromiseLike<
          {
            data: { active: boolean | null; coach_context: boolean | null } | null;
            error: unknown;
          }
        >,
    ),
    // 최근 14일 안에 고른 주간 체크인 실험 (가장 최근 주).
    safe<Array<{ chosen_experiment: string | null }>>(
      'checkin',
      admin
        .from('weekly_checkins')
        .select('chosen_experiment, week_start')
        .eq('user_id', userId)
        .not('chosen_experiment', 'is', null)
        .gte('week_start', shiftDateKey(todayKey, -14))
        .order('week_start', { ascending: false })
        .limit(1) as unknown as PromiseLike<
          { data: Array<{ chosen_experiment: string | null }> | null; error: unknown }
        >,
    ),
    // 이번 주 식단 (week_start_date = 이번 주 월요일, 로컬).
    safe<{ plan_json: unknown }>(
      'meal_plan',
      admin
        .from('meal_plans')
        .select('plan_json')
        .eq('user_id', userId)
        .eq('week_start_date', mondayKey(todayKey))
        .eq('status', 'done')
        .maybeSingle() as unknown as PromiseLike<
          { data: { plan_json: unknown } | null; error: unknown }
        >,
    ),
  ]);

  const exp = checkinRows?.[0]?.chosen_experiment?.trim() ?? '';

  return {
    todayKey,
    week: summarizeWeek(weekRows ?? [], tzOffsetMin, todayKey),
    // 사용자가 직접 입력한 실험일 수 있으므로 금지어·굶기·효과 보장 문구는 걸러낸다.
    experiment: safePrevExperiment(exp),
    mode: effectiveMode(
      modeRow?.goal_mode,
      profile?.goal_weight_kg,
      profile?.weight_kg,
    ),
    glp1: medRow?.active === true && medRow?.coach_context !== false,
    floor: kcalFloor(profile?.sex),
    planMeals: todayPlanMeals(planRow?.plan_json, weekdayIndex(todayKey)),
  };
}

// ── 안티-셰임 결정적 메시지 (LLM 대신 고정 문구) ───────────────────────
// 금지어(실패/어겼다/망쳤다/해주세요) 없이 작성. 푸디 반말 톤.

// 끊김 회복 — 며칠 쉬고 돌아온 사용자를 혼내지 않고 환영한다.
function welcomeBack(nickname: string, days: number): CoachResult {
  return {
    emoji: '🌱',
    headline: '다시 와줘서 반가워!',
    review:
      `${nickname}야, ${days}일 만이네. 며칠 쉬었어도 정말 괜찮아 — ` +
      '다이어트는 완벽하게가 아니라 다시 돌아오는 게 진짜야.',
    next_tip: '오늘은 거창하지 않아도 돼. 사진 한 장으로 가볍게 다시 시작해보자.',
    focus: '다시 시작',
  };
}

// §10.3 극단 절식 가드 — 적게 먹은 걸 칭찬하지 않고 부드럽게 챙김을 권한다.
// extreme(아주 적음)이면 혼자 버겁지 않게 가벼운 상담 권유를 덧붙인다.
function careLowIntake(nickname: string, extreme: boolean): CoachResult {
  return {
    emoji: '🌿',
    headline: '오늘은 천천히 가도 돼',
    review: extreme
      ? `${nickname}야, 오늘 먹은 게 많이 적네. 못 챙긴 거면 지금이라도 가볍게 먹자. ` +
        '혼자 버겁다면 가까운 사람이나 전문가에게 얘기하는 것도 괜찮아 🌷'
      : '오늘 기록이 좀 적네. 더 먹은 게 있으면 추가해줘. ' +
        '일부러 적게 먹는 거라도 너무 무리하면 오히려 더 힘들어져.',
    next_tip: '에너지가 부족하면 다이어트도 흔들려. 단백질이랑 따뜻한 국물로 가볍게라도 챙기자.',
    focus: '충분히 먹기',
  };
}

// 응답에는 kind/signature/persona 같은 내부 메타를 빼고 advice 필드만 돌려준다.
function stripMeta(body: Record<string, unknown>): CoachResult {
  return {
    emoji: (body.emoji as string) ?? '🍓',
    headline: (body.headline as string) ?? '',
    review: (body.review as string) ?? '',
    next_tip: (body.next_tip as string) ?? '',
    focus: (body.focus as string) ?? '',
  };
}
