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

// 끼니 1개 상세 스키마 — 2단계(요일별 상세 생성)에서 재사용.
const MEAL_SCHEMA = {
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
      description:
        '만드는 방법을 요리 초보도 보고 그대로 따라 만들 수 있을 만큼 ' +
        '자세하게 5~9단계로. 각 단계는 재료 양·불 세기·시간·익힘 정도 등을 ' +
        '구체적으로(반말). 예: "달군 팬에 식용유 1큰술 두르고 중불에서 ' +
        '다진 마늘 1작은술을 30초 볶아 향을 낸다."',
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
} as const;

// 1단계: 일주일 메뉴 뼈대 — 요리 이름·끼니·목표 칼로리만. 출력이 작아 빠르고,
// 7일을 한 컨텍스트에서 함께 짜 메뉴 중복을 막고 주간 다양성을 확보한다.
const SKELETON_SCHEMA = {
  name: 'foodiet_meal_skeleton',
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
          required: ['date_offset', 'label', 'meals'],
          properties: {
            date_offset: {
              type: 'integer',
              minimum: 0,
              maximum: 6,
              description: 'week_start_date 로부터 더할 일수 (월=0)',
            },
            label: { type: 'string', description: '요일 한글 (예: 월요일)' },
            meals: {
              type: 'array',
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['slot', 'name', 'target_kcal'],
                properties: {
                  slot: { type: 'string', enum: ALLOWED_SLOTS as unknown as string[] },
                  name: {
                    type: 'string',
                    description: '요리 이름 (한국식). 한 주에 같은 요리를 반복하지 말 것.',
                  },
                  target_kcal: { type: 'integer', description: '이 끼니 목표 칼로리.' },
                },
              },
            },
          },
        },
      },
    },
  },
} as const;

// 2단계: 하루치 상세 — 뼈대에서 정한 요리들의 상세 레시피/영양/장보기.
const DAY_SCHEMA = {
  name: 'foodiet_meal_day',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['date_offset', 'label', 'total_kcal', 'meals'],
    properties: {
      date_offset: { type: 'integer', minimum: 0, maximum: 6 },
      label: { type: 'string', description: '요일 한글 (예: 월요일)' },
      total_kcal: { type: 'integer' },
      meals: { type: 'array', items: MEAL_SCHEMA },
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

// OpenAI chat completions 1회 호출. 선택 파라미터(temperature 등)는 params 로
// 주입하고, 모델이 거부하면 호출부(chat)에서 그 키를 떨군 뒤 재시도한다.
async function postChat(
  schema: unknown,
  system: string,
  user: string,
  params: Record<string, unknown>,
): Promise<Response> {
  return await fetch(OPENAI_ENDPOINT, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${OPENAI_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      response_format: { type: 'json_schema', json_schema: schema },
      ...params,
    }),
  });
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

  // 재생성/갱신은 "비파괴적"으로 한다. 기존 plan 을 미리 지우지 않는다 —
  // 생성이 실패해도(OpenAI 504/네트워크 등) 기존 식단이 그대로 남도록, 아래에서
  // 성공했을 때만 upsert(user_id,week_start_date)로 원자적으로 덮어쓴다.
  // (예전엔 먼저 delete 후 ~80s 생성 → 생성 실패 시 식단이 통째로 사라졌다.)

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

  // 공통 컨텍스트 — 1·2단계 프롬프트가 공유한다.
  const baseContext = `[프로필]
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
끼니별 목표 칼로리: ${slotTargetsStr}`;

  const allergyLine =
    `${allergies.length ? allergies.join(', ') : '없음'}` +
    `${allergyNotes ? ', ' + allergyNotes : ''}`;

  // gpt-5.x reasoning 계열은 추론 토큰이 지연을 좌우한다. reasoning_effort='low'
  // 로 추론을 줄여(기본 effort 는 호출당 ~2000 토큰) 7일 병렬 생성이 150s edge
  // 한도 안에 들어오게 한다. temperature 는 이 계열이 거부하므로 보내지 않는다.
  // 모델이 특정 파라미터를 거부(400)하면 그 키를 떨군 뒤 재시도한다(1단계에서
  // 정리되면 2단계 병렬 호출은 정리된 params 를 그대로 쓴다).
  const params: Record<string, unknown> = { reasoning_effort: 'low' };

  async function chat(
    schema: unknown,
    system: string,
    user: string,
    tag: string,
  ): Promise<{ json?: unknown; error?: { status: number; detail: string } }> {
    const startedAt = Date.now();
    let resp = await postChat(schema, system, user, params);
    for (let attempt = 0; attempt < 2 && !resp.ok && resp.status === 400; attempt++) {
      const err = await resp.text();
      const lower = err.toLowerCase();
      const dropped = Object.keys(params).filter((p) => lower.includes(p.toLowerCase()));
      if (dropped.length === 0) return { error: { status: resp.status, detail: err.slice(0, 500) } };
      for (const p of dropped) delete params[p];
      console.warn(`[${tag}] openai 400 dropping [${dropped.join(',')}]: ${err.slice(0, 300)}`);
      resp = await postChat(schema, system, user, params);
    }
    if (!resp.ok) {
      const err = await resp.text();
      return { error: { status: resp.status, detail: err.slice(0, 500) } };
    }
    const j = await resp.json();
    const u = (j as { usage?: Record<string, unknown> })?.usage ?? {};
    console.log(`usage[${tag}] ` + JSON.stringify({
      ms: Date.now() - startedAt,
      completion: u.completion_tokens,
      reasoning:
        (u.completion_tokens_details as { reasoning_tokens?: number } | undefined)
          ?.reasoning_tokens,
    }));
    return { json: j };
  }

  function parseContent(j: unknown): unknown {
    const content =
      (j as { choices?: Array<{ message?: { content?: string } }> })
        ?.choices?.[0]?.message?.content ?? '';
    return JSON.parse(content);
  }

  const openaiFail = (stage: string, e: { status: number; detail: string }) => {
    console.error(`openai error [${stage}]`, e.status, e.detail);
    return new Response(
      JSON.stringify({ error: 'openai_failed', stage, status: e.status, detail: e.detail }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  };
  const openaiExc = (stage: string, e: unknown) => {
    console.error(`openai exception [${stage}]`, e);
    return new Response(
      JSON.stringify({ error: 'openai_exception', stage, detail: String(e).slice(0, 300) }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  };

  // ---- 1단계: 일주일 메뉴 뼈대(이름·목표 칼로리)만 한 번에 (중복 방지·다양성) ----
  const skeletonSystem = `당신은 Foodiet 앱의 영양 코치 "푸디"예요.
한국어 반말 + 친근한 톤으로, 일반인 대상 균형 잡힌 식단을 제안합니다.

반드시 지킬 규칙:
- 의료·치료적 조언 금지. 일반적인 영양 균형 가이드만.
- 알레르기에 등재된 재료는 어떤 형태로도 들어가면 안 돼.
- 사용자가 보유한 재료를 우선 활용. 부족한 건 마트에서 쉽게 살 수 있는 한국 식재료로 보완.
- 아침·점심·저녁을 모두 먹는다고 가정하고, 끼니마다 하루 목표(${target} kcal)의 정해진 비율만 차지해요(아침·점심·저녁 각 약 1/3, 간식 약 10%).
- 끼니별 목표 칼로리(각 ±15% 이내로): ${slotTargetsStr}.
- 같은 요리를 7일 동안 두 번 이상 반복하지 마세요. 매일 다른 메뉴로 다양하게.
- 사용자가 선택한 끼니(${slots.join(', ')})만 채우세요. 그 외 슬롯은 비웁니다.
- 응답은 JSON 스키마에만 엄격히 맞추세요.`;

  const skeletonUser = `${baseContext}

[요청] 이번 주(월~일) 7일치 "메뉴 뼈대"를 JSON 으로 만들어줘.
- days 는 정확히 7개, date_offset 0~6 (월=0, 일=6), label 은 한글 요일.
- 각 day 의 meals 는 선택한 끼니만, 각 끼니에 요리 이름(name)과 목표 칼로리(target_kcal)만 채워.
- 하루 끼니 목표 칼로리 합은 약 ${plannedDaily} kcal.
- 상세 레시피는 다음 단계에서 만드니 여기선 이름·칼로리만. 7일간 메뉴가 겹치지 않게 다양하게.
- caveats: 알레르기·재료 반영 내역 한 줄씩. weekly_summary: 이번 주 컨셉 반말 1~2문장.`;

  const s1 = await chat(SKELETON_SCHEMA, skeletonSystem, skeletonUser, 'skeleton');
  if (s1.error) return openaiFail('skeleton', s1.error);
  let skeleton: { weekly_summary?: string; caveats?: unknown; days?: unknown[] };
  try {
    skeleton = parseContent(s1.json) as typeof skeleton;
  } catch (e) {
    return openaiExc('skeleton', e);
  }
  const skelDays = Array.isArray(skeleton?.days)
    ? (skeleton.days as Array<{
      date_offset?: number;
      label?: string;
      meals?: Array<{ slot?: string; name?: string; target_kcal?: number }>;
    }>)
    : [];
  if (skelDays.length === 0) return openaiExc('skeleton', new Error('no days in skeleton'));

  // ---- 2단계: 요일별 상세 레시피를 병렬 생성 (각 호출 출력이 작아 150s 안에 끝남) ----
  const daySystem = `당신은 Foodiet 앱의 영양 코치 "푸디"예요. 한국어 반말.
주어진 "오늘의 메뉴"에 대해서만 상세 레시피를 작성합니다.

반드시 지킬 규칙:
- 알레르기 재료(${allergyLine})는 어떤 형태로도 넣지 마.
- meals 의 slot·name 은 주어진 그대로 유지하고, 나머지(kcal·carb_g·protein_g·fat_g·ingredients·recipe_brief·steps·shopping)를 채워.
- 각 끼니 kcal 은 주어진 target_kcal 의 ±15% 이내로. total_kcal 은 그 끼니들 kcal 의 합.
- steps 는 요리 초보도 그대로 따라 만들 수 있을 만큼 5~9단계로 아주 자세히(각 단계에 재료 양·불 세기·시간·익힘 정도를 구체적으로, 반말). 한 줄짜리 대충 설명 금지.
- ingredients 는 주요 재료 5개 이내(한국식), shopping 은 재료명+양(마트에서 살 단위).
- 응답은 JSON 스키마에만 엄격히 맞추세요.`;

  const startedAll = Date.now();
  const dayResults = await Promise.all(skelDays.map((d) => {
    const planned = (d?.meals ?? [])
      .map((m) =>
        `- ${SLOT_LABEL_KO[m.slot as Slot] ?? m.slot} (slot=${m.slot}): ${m.name} / 목표 ${m.target_kcal}kcal`
      )
      .join('\n');
    const dayUser = `${baseContext}

[오늘 = ${d?.label ?? ''} (date_offset ${d?.date_offset})]
아래 끼니들의 상세 레시피를 만들어줘 (slot·name 은 그대로 유지):
${planned}`;
    return chat(DAY_SCHEMA, daySystem, dayUser, `day${d?.date_offset}`);
  }));

  const days: unknown[] = [];
  for (let i = 0; i < dayResults.length; i++) {
    const r = dayResults[i];
    if (r.error) return openaiFail(`day${skelDays[i]?.date_offset}`, r.error);
    try {
      days.push(parseContent(r.json));
    } catch (e) {
      return openaiExc(`day${skelDays[i]?.date_offset}`, e);
    }
  }
  console.log('mealplan_done ' + JSON.stringify({
    model: OPENAI_MODEL,
    stage2_ms: Date.now() - startedAll,
    days: days.length,
  }));

  const planJson: unknown = {
    weekly_summary: skeleton?.weekly_summary ?? '',
    caveats: Array.isArray(skeleton?.caveats) ? skeleton.caveats : [],
    days,
  };

  const { data: inserted, error: insertErr } = await admin
    .from('meal_plans')
    .upsert({
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
    }, { onConflict: 'user_id,week_start_date' })
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
