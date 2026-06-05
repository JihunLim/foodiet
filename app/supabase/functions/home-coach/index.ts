// home-coach — 홈 화면 AI 가이드 카드용 식단 코칭.
//
// 입력: 현재 로그인 사용자의 오늘자 entries(완료분) + 프로필 + 현재 시각(로컬).
// 출력: { emoji, headline, review, next_tip, focus } 구조화 JSON 한 건.
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
//   OPENAI_API_KEY
//   OPENAI_MODEL           (default 'gpt-5.4-mini')
//   OPENAI_ENDPOINT        (default 'https://api.openai.com/v1/chat/completions')

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!;
const OPENAI_MODEL = Deno.env.get('OPENAI_MODEL') ?? 'gpt-5.4-mini';
const OPENAI_ENDPOINT =
  Deno.env.get('OPENAI_ENDPOINT') ?? 'https://api.openai.com/v1/chat/completions';

// §7.9 — 금지어 (부정 표현). headline 에서 하나라도 등장하면 무난한 fallback 으로 대체.
const BANNED = ['실패', '어겼다', '망쳤다', '해주세요'];

const RESPONSE_SCHEMA = {
  name: 'foodie_home_coach',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['emoji', 'headline', 'review', 'next_tip', 'focus'],
    properties: {
      emoji: {
        type: 'string',
        description: '오늘의 분위기 이모지 1개.',
      },
      headline: {
        type: 'string',
        description: '15자 내외 반말, 긍정/격려. 20자 초과 금지.',
      },
      review: {
        type: 'string',
        description: '지금까지 먹은 음식에 대한 2~3문장 긍정 코멘트.',
      },
      next_tip: {
        type: 'string',
        description: '현재 시각 기준 다음 식사/간식 1~2문장 구체 가이드.',
      },
      focus: {
        type: 'string',
        description: '지금 신경쓰면 좋을 영양소 1~2단어 (예: 단백질, 식이섬유).',
      },
    },
  },
} as const;

type CoachResult = {
  emoji: string;
  headline: string;
  review: string;
  next_tip: string;
  focus: string;
};

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

  // 프로필
  const { data: profile } = await admin
    .from('profiles')
    .select(
      'nickname, locale, daily_kcal_target, goal_weight_kg, goal_deadline, ' +
        'diet_restrictions, activity_level, weight_kg, height_cm, sex, birth_date',
    )
    .eq('user_id', userId)
    .maybeSingle();

  // 오늘 완료된 엔트리
  const { data: entries } = await admin
    .from('entries')
    .select(
      'title, meal_slot, eating_type, kcal_total, macros, ' +
        'captured_at, shared_with_count, status',
    )
    .eq('user_id', userId)
    .eq('status', 'done')
    .gte('captured_at', startOfTodayUtc(tzOffsetMin))
    .order('captured_at', { ascending: true });

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
  const target = (profile?.daily_kcal_target as number) ?? 1800;
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

  // ── 캐시 + 레이트리밋 ────────────────────────────────────────────────
  // coach_messages 에 `scope='daily'`, `body_json.kind='home_coach'` 로 저장.
  // 같은 시그니처(= done 엔트리 수·kcal 합) 면 캐시 재사용, 하루 5회 초과 시에도
  // 최신 캐시를 그대로 돌려주어 LLM 비용을 차단.
  //
  // 마지막(5번째) 호출은 로컬 18시 이후에만 허용 — 저녁 식사 타이밍에 맞춘
  // 업데이트를 보장하기 위해 슬롯 하나를 아껴둔다. 사용자 타임존이 파악 안 되면
  // 한국(KST) 기준으로 폴백.
  const signature = `d:${eaten.length}|k:${kcalConsumed}|c:${carb.toFixed(0)}` +
    `|p:${protein.toFixed(0)}|f:${fat.toFixed(0)}`;
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

  const systemPrompt = `당신은 Foodiet 앱의 AI 식단 코치 "푸디"입니다.
한국어 반말, 친근하고 긍정적인 톤으로 사용자의 다이어트를 응원하세요.

반드시 지킬 규칙:
- "실패", "어겼다", "망쳤다", "해주세요" 등 부정/사무적인 어휘는 금지.
- 의료·치료 조언 금지. 일반적인 영양 균형 가이드만.
- 현재 시각(사용자 로컬)을 고려해 다음 가이드를 제안:
  · 아침(06~10): 단백질+탄수 균형, 커피는 식후로.
  · 점심 전(10~13): 점심으로 채소+단백질 추천.
  · 오후(14~17): 당 과다 피하기, 간식이면 견과·과일.
  · 저녁(17~20): 지방 낮고 식이섬유 풍부하게.
  · 야간(21~): 가벼운 수분·단백질 위주, 탄수 자제.
- 응답은 JSON 스키마에만 엄격히 맞춰주세요.
- headline 은 20자 이내. 이모지는 emoji 필드에만 넣고 본문에는 금지.`;

  const userPrompt = `[프로필]
닉네임: ${nickname}
일일 목표: ${target} kcal
목표 체중: ${profile?.goal_weight_kg ?? '미설정'} kg
활동 수준(1~5): ${profile?.activity_level ?? 3}
식단 제약: ${
    Array.isArray(profile?.diet_restrictions) && profile!.diet_restrictions.length
      ? (profile!.diet_restrictions as string[]).join(', ')
      : '없음'
  }

[현재 시각]
${nowLabel} (사용자 로컬)

[오늘 섭취 현황]
먹은 끼니 ${eaten.length}건:
${
    eaten.length === 0
      ? '  (아직 기록 없음)'
      : eaten
          .map(
            (e) =>
              `  - ${e.time} · ${e.slot} · ${e.title} (${e.kcal} kcal)`,
          )
          .join('\n')
  }

합계: ${kcalConsumed} / ${target} kcal (남은 ${remaining} kcal)
탄수 ${carb.toFixed(0)}g · 단백 ${protein.toFixed(0)}g · 지방 ${fat.toFixed(0)}g
나트륨 ${Math.round(sodium)}mg · 당 ${sugar.toFixed(0)}g

이 데이터를 바탕으로 JSON 으로 응답하세요:
- emoji: 오늘 분위기 이모지 1개
- headline: 15~20자 반말 요약 한 줄
- review: 지금까지 섭취에 대한 2~3문장 긍정 코멘트 (수치 언급 OK)
- next_tip: 현재 시각에 맞춰 다음 식사/간식 1~2문장 구체 가이드
- focus: 지금 신경쓰면 좋을 영양소 1~2단어`;

  const body = {
    model: OPENAI_MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
    temperature: 0.6,
  };

  const resp = await fetch(OPENAI_ENDPOINT, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${OPENAI_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const t = await resp.text().catch(() => '');
    console.error('openai failed', resp.status, t);
    return new Response(
      JSON.stringify({ error: 'llm_failed', status: resp.status }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  }

  const raw = await resp.json();
  const content: string | undefined = raw?.choices?.[0]?.message?.content;
  if (!content) {
    return new Response(
      JSON.stringify({ error: 'llm_empty' }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  }

  let parsed: CoachResult;
  try {
    parsed = JSON.parse(content) as CoachResult;
  } catch (e) {
    console.error('invalid json', e, content);
    return new Response(
      JSON.stringify({ error: 'llm_invalid_json' }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  }

  // §7.9 headline 사후 필터. 부정 단어 포함 시 중립 문구로 대체.
  if (BANNED.some((b) => parsed.headline?.includes(b))) {
    parsed.headline = '오늘도 같이 가보자 💪';
  }

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
