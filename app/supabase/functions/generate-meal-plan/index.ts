// generate-meal-plan — 사용자 목표·알레르기·재료를 기반으로 일주일치 식단을 만들고
// meal_plans 테이블에 한 행으로 저장한다.
//
// 호출 정책:
//   * 사용자 1인당 같은 주(week_start_date) 에 1회만 생성 가능 — DB 의 unique 제약
//     이 fallback. 본 함수도 동일 주차 plan 존재 시 409 로 거절.
//
// 입력 (POST JSON):
//   {
//     "tz_offset_min": 540,
//     "allergies":        string[],  // 칩 선택분
//     "allergy_notes":    string,    // 자유기재
//     "ingredients":      string[],
//     "ingredient_notes": string,
//     "cuisine_styles":   string[],  // ['korean','western','japanese','simple']
//     "meal_slots":       string[]   // ['breakfast','lunch','dinner','snack'] 중 선택
//   }
//
// 출력:
//   { id, week_start_date, plan_json, source_model }
//
// ENV:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, OPENAI_API_KEY,
//   OPENAI_MODEL (default 'gpt-5.4-mini'), OPENAI_ENDPOINT (default openai chat).

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

const DEFAULT_TZ_OFFSET_MIN = 540;

// 음식 이미지 — 네이버 이미지검색(한식 커버리지 우수). 검색 키는 서버 전용.
// 키 미설정/실패 시 null → 클라이언트가 스타일 헤더로 폴백. (출처 사이트 링크라
// 상업 출시 전엔 라이선스 이미지로 교체 권장.)
const NAVER_CLIENT_ID = Deno.env.get('NAVER_CLIENT_ID');
const NAVER_CLIENT_SECRET = Deno.env.get('NAVER_CLIENT_SECRET');

async function searchFoodImage(name: string): Promise<string | null> {
  if (!NAVER_CLIENT_ID || !NAVER_CLIENT_SECRET || !name.trim()) return null;
  try {
    const url =
      'https://openapi.naver.com/v1/search/image?display=1&sort=sim&filter=large&query=' +
      encodeURIComponent(`${name} 음식`);
    const r = await fetch(url, {
      headers: {
        'X-Naver-Client-Id': NAVER_CLIENT_ID,
        'X-Naver-Client-Secret': NAVER_CLIENT_SECRET,
      },
    });
    if (!r.ok) return null;
    const j = await r.json();
    // thumbnail 은 네이버 CDN 호스팅이라 앱에서 바로 로드된다. link(원본 사이트)는
    // 핫링크 차단으로 자주 실패 → thumbnail 우선, 없으면 link 폴백.
    const item = j?.items?.[0];
    const img = (item?.thumbnail as string | undefined) ??
      (item?.link as string | undefined);
    return typeof img === 'string' && img.startsWith('http') ? img : null;
  } catch (_) {
    return null;
  }
}

// plan_json 의 각 meal 에 image_url 을 채운다. 이름 중복은 캐시, 베스트에포트.
async function attachMealImages(planJson: unknown): Promise<void> {
  if (!NAVER_CLIENT_ID || !NAVER_CLIENT_SECRET) return;
  const days = (planJson as {
    days?: Array<{ meals?: Array<Record<string, unknown>> }>;
  })?.days;
  if (!Array.isArray(days)) return;
  const meals: Array<Record<string, unknown>> = [];
  for (const d of days) {
    for (const m of d?.meals ?? []) meals.push(m);
  }
  const cache = new Map<string, string | null>();
  await Promise.all(meals.map(async (m) => {
    const nm = String(m?.name ?? '');
    if (!cache.has(nm)) cache.set(nm, await searchFoodImage(nm));
    m.image_url = cache.get(nm) ?? null;
  }));
}

const ALLOWED_SLOTS = ['breakfast', 'lunch', 'dinner', 'snack'] as const;
type Slot = typeof ALLOWED_SLOTS[number];

// 끼니별 하루 칼로리 비율 — 아침·점심·저녁은 모두 먹는다고 가정해 각각 약 1/3,
// 간식은 작은 추가분. 선택한 끼니만 만들되, 선택 안 한 끼니의 몫을 다른 끼니에
// 합쳐 키우지 않는다 (예: 저녁만 선택 → 저녁은 하루의 약 1/3 으로 구성).
const SLOT_FRACTION: Record<Slot, number> = {
  breakfast: 0.33,
  lunch: 0.33,
  dinner: 0.34,
  snack: 0.10,
};
const SLOT_LABEL_KO: Record<Slot, string> = {
  breakfast: '아침',
  lunch: '점심',
  dinner: '저녁',
  snack: '간식',
};

const RESPONSE_SCHEMA = {
  name: 'foodiet_meal_plan',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['weekly_summary', 'caveats', 'days'],
    properties: {
      weekly_summary: {
        type: 'string',
        description: '이번 주 식단 컨셉 1~2문장 요약 (반말).',
      },
      caveats: {
        type: 'array',
        items: { type: 'string' },
        description: '알레르기/제약을 어떻게 반영했는지 한 줄씩.',
      },
      days: {
        type: 'array',
        minItems: 7,
        maxItems: 7,
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['date_offset', 'label', 'total_kcal', 'meals'],
          properties: {
            date_offset: {
              type: 'integer',
              minimum: 0,
              maximum: 6,
              description: 'week_start_date 로부터 더할 일수 (월=0)',
            },
            label: { type: 'string', description: '요일 한글 (예: 월요일)' },
            total_kcal: { type: 'integer' },
            meals: {
              type: 'array',
              items: {
                type: 'object',
                additionalProperties: false,
                required: [
                  'slot', 'name', 'kcal', 'carb_g', 'protein_g', 'fat_g',
                  'ingredients', 'recipe_brief', 'steps', 'shopping',
                ],
                properties: {
                  slot: { type: 'string', enum: ALLOWED_SLOTS as unknown as string[] },
                  name: { type: 'string' },
                  kcal: { type: 'integer' },
                  carb_g: { type: 'integer' },
                  protein_g: { type: 'integer' },
                  fat_g: { type: 'integer' },
                  ingredients: {
                    type: 'array',
                    items: { type: 'string' },
                    description: '주요 재료 5개 이내, 한국식 이름.',
                  },
                  recipe_brief: {
                    type: 'string',
                    description: '조리법 1~2문장 (반말).',
                  },
                  steps: {
                    type: 'array',
                    items: { type: 'string' },
                    description: '만드는 방법 단계별 3~6개. 각 한 문장, 반말.',
                  },
                  shopping: {
                    type: 'array',
                    description: '장보기 목록 — 이 요리에 필요한 재료와 양.',
                    items: {
                      type: 'object',
                      additionalProperties: false,
                      required: ['name', 'qty'],
                      properties: {
                        name: { type: 'string', description: '재료명 (한국식).' },
                        qty: {
                          type: 'string',
                          description: '필요한 양 (예: 200g, 1개, 2큰술).',
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
} as const;

function parseTzOffset(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return DEFAULT_TZ_OFFSET_MIN;
  if (raw < -720 || raw > 840) return DEFAULT_TZ_OFFSET_MIN;
  return Math.round(raw);
}

function mondayOfThisWeek(tzOffsetMin: number): string {
  const local = new Date(Date.now() + tzOffsetMin * 60 * 1000);
  // UTC getDay: 0=Sun, 1=Mon... 6=Sat. 월요일 기준으로 정렬.
  const dow = (local.getUTCDay() + 6) % 7; // 0=Mon..6=Sun
  local.setUTCDate(local.getUTCDate() - dow);
  const y = local.getUTCFullYear();
  const m = String(local.getUTCMonth() + 1).padStart(2, '0');
  const d = String(local.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
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
  if (error) return { userId: null, reason: `getUser_error:${error.message}` };
  if (!data?.user) return { userId: null, reason: 'no_user' };
  return { userId: data.user.id };
}

function sanitizeStrArray(raw: unknown, max = 20): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((x) => typeof x === 'string')
    .map((x) => (x as string).trim())
    .filter((s) => s.length > 0 && s.length <= 60)
    .slice(0, max);
}

function sanitizeSlots(raw: unknown): Slot[] {
  const arr = sanitizeStrArray(raw, 4);
  const out: Slot[] = [];
  for (const s of arr) {
    if ((ALLOWED_SLOTS as readonly string[]).includes(s) && !out.includes(s as Slot)) {
      out.push(s as Slot);
    }
  }
  if (out.length === 0) return ['breakfast', 'lunch', 'dinner'];
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }

  const { userId, reason } = await getUserId(req);
  if (!userId) {
    return new Response(
      JSON.stringify({ error: 'unauthorized', reason }),
      { status: 401, headers: { 'content-type': 'application/json' } },
    );
  }

  let reqBody: Record<string, unknown> = {};
  try {
    reqBody = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: 'invalid_json' }),
      { status: 400, headers: { 'content-type': 'application/json' } },
    );
  }

  const tzOffsetMin = parseTzOffset(reqBody?.tz_offset_min);
  const weekStart = mondayOfThisWeek(tzOffsetMin);

  const allergies = sanitizeStrArray(reqBody?.allergies, 10);
  const allergyNotes = typeof reqBody?.allergy_notes === 'string'
    ? (reqBody.allergy_notes as string).trim().slice(0, 300) : '';
  const ingredients = sanitizeStrArray(reqBody?.ingredients, 30);
  const ingredientNotes = typeof reqBody?.ingredient_notes === 'string'
    ? (reqBody.ingredient_notes as string).trim().slice(0, 300) : '';
  const cuisineStyles = sanitizeStrArray(reqBody?.cuisine_styles, 6);
  const slots = sanitizeSlots(reqBody?.meal_slots);

  // 이번 주 plan 이 이미 있으면 덮어쓴다 (재생성/갱신 허용).
  // 주의: 원래 "주 1회" 비용 가드를 푼 것 — 필요하면 409 로 다시 막을 수 있음.
  const { data: existing } = await admin
    .from('meal_plans')
    .select('id')
    .eq('user_id', userId)
    .eq('week_start_date', weekStart)
    .maybeSingle();
  if (existing) {
    await admin.from('meal_plans').delete().eq('id', existing.id);
  }

  const { data: profile } = await admin
    .from('profiles')
    .select(
      'nickname, locale, daily_kcal_target, goal_weight_kg, weight_kg, ' +
        'activity_level, diet_restrictions, sex',
    )
    .eq('user_id', userId)
    .maybeSingle();

  const target = (profile?.daily_kcal_target as number | null) ?? 1800;
  const goalKg = profile?.goal_weight_kg as number | null;
  const currentKg = profile?.weight_kg as number | null;
  const activity = (profile?.activity_level as number | null) ?? 3;
  const sex = (profile?.sex as string | null) ?? null;
  const dietRestr = Array.isArray(profile?.diet_restrictions)
    ? (profile!.diet_restrictions as string[]) : [];

  // 끼니별 목표 칼로리 — 하루 목표에서 고정 비율만 배정. 선택한 끼니 합이
  // plannedDaily (하루 목표보다 작을 수 있음 = 정상).
  const slotKcal = slots.map((s) => ({
    label: SLOT_LABEL_KO[s],
    kcal: Math.round(target * SLOT_FRACTION[s]),
  }));
  const slotTargetsStr = slotKcal.map((x) => `${x.label} ${x.kcal}kcal`).join(', ');
  const plannedDaily = slotKcal.reduce((sum, x) => sum + x.kcal, 0);

  const systemPrompt = `당신은 Foodiet 앱의 영양 코치 "푸디"예요.
한국어 반말 + 친근한 톤으로, 일반인 대상 균형 잡힌 식단을 제안합니다.

반드시 지킬 규칙:
- 의료·치료적 조언 금지. 일반적인 영양 균형 가이드만.
- 알레르기에 등재된 재료는 어떤 형태로도 들어가면 안 돼.
- 사용자가 보유한 재료를 우선 활용. 부족한 건 마트에서 쉽게 살 수 있는 한국 식재료로 보완.
- 아침·점심·저녁을 모두 먹는다고 가정하고, 끼니마다 하루 목표(${target} kcal)의 정해진 비율만 차지해요(아침·점심·저녁 각 약 1/3, 간식 약 10%). 선택 안 한 끼니의 칼로리를 선택한 끼니에 합쳐서 키우면 절대 안 돼요.
- 끼니별 목표 칼로리(각 ±15% 이내로): ${slotTargetsStr}.
- 각 day 의 total_kcal 은 선택한 끼니들의 합(약 ${plannedDaily} kcal)이며, 하루 목표(${target} kcal)보다 작아도 정상이에요. 억지로 ${target} 에 맞추지 마세요.
- 같은 메뉴를 7일 동안 두 번 이상 반복하지 마세요.
- 사용자가 선택한 끼니(${slots.join(', ')})만 채우세요. 그 외 슬롯은 비웁니다.
- 응답은 JSON 스키마에만 엄격히 맞추세요.`;

  const userPrompt = `[프로필]
닉네임: ${profile?.nickname ?? '유저'}
성별: ${sex ?? '미설정'}
현재 체중: ${currentKg ?? '미설정'} kg
목표 체중: ${goalKg ?? '미설정'} kg
일일 목표: ${target} kcal
활동 수준(1~5): ${activity}
프로필 식단 제약: ${dietRestr.length ? dietRestr.join(', ') : '없음'}

[입력]
알레르기(선택): ${allergies.length ? allergies.join(', ') : '없음'}
알레르기(기타): ${allergyNotes || '없음'}
냉장고 재료(선택): ${ingredients.length ? ingredients.join(', ') : '없음'}
냉장고 재료(기타): ${ingredientNotes || '없음'}
선호 식단 스타일: ${cuisineStyles.length ? cuisineStyles.join(', ') : '특별한 선호 없음'}
포함할 끼니: ${slots.join(', ')}
끼니별 목표 칼로리: ${slotTargetsStr} (각 끼니는 이 값 근처로, 선택 안 한 끼니 몫을 합치지 말 것)

[요청]
이번 주(월~일) 7일치 식단을 JSON 으로 만들어줘.
- days 는 정확히 7개, date_offset 0~6 (월=0, 일=6).
- 각 day 의 meals 는 선택한 끼니만 포함하고, 각 끼니 kcal 은 위 끼니별 목표 근처로. day 의 total_kcal 은 그 합(약 ${plannedDaily} kcal).
- caveats 에는 알레르기·재료 활용 반영 내역을 한 줄씩.
- weekly_summary 는 이번 주 컨셉을 반말 1~2문장.
- 각 meal 의 steps 는 집에서 따라 할 수 있는 만드는 방법 3~6단계(각 한 문장, 반말), shopping 은 그 요리에 필요한 재료와 양(마트에서 살 단위)으로 채워.`;

  const body = {
    model: OPENAI_MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
    temperature: 0.7,
  };

  let planJson: unknown;
  try {
    const resp = await fetch(OPENAI_ENDPOINT, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${OPENAI_API_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!resp.ok) {
      const err = await resp.text();
      console.error('openai error', resp.status, err);
      return new Response(
        JSON.stringify({ error: 'openai_failed', status: resp.status, detail: err.slice(0, 500) }),
        { status: 502, headers: { 'content-type': 'application/json' } },
      );
    }
    const j = await resp.json();
    const content: string = j?.choices?.[0]?.message?.content ?? '';
    planJson = JSON.parse(content);
  } catch (e) {
    console.error('openai exception', e);
    return new Response(
      JSON.stringify({ error: 'openai_exception', detail: String(e).slice(0, 300) }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  }

  // 각 meal 에 음식 이미지 URL 주입 (네이버 키 있을 때만, 베스트에포트).
  await attachMealImages(planJson);

  const { data: inserted, error: insertErr } = await admin
    .from('meal_plans')
    .insert({
      user_id: userId,
      week_start_date: weekStart,
      allergies,
      allergy_notes: allergyNotes || null,
      ingredients,
      ingredient_notes: ingredientNotes || null,
      cuisine_styles: cuisineStyles,
      meal_slots: slots,
      goal_weight_kg: goalKg,
      current_weight_kg: currentKg,
      daily_kcal_target: target,
      activity_level: activity,
      plan_json: planJson,
      source_model: OPENAI_MODEL,
      status: 'done',
    })
    .select('id, week_start_date, plan_json, source_model, created_at')
    .single();

  if (insertErr || !inserted) {
    console.error('insert error', insertErr);
    return new Response(
      JSON.stringify({ error: 'db_insert_failed', detail: insertErr?.message ?? null }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  return new Response(JSON.stringify(inserted), {
    headers: { 'content-type': 'application/json' },
  });
});
