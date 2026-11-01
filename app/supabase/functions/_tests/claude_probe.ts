// claude_probe — analyze-entry / home-coach / generate-meal-plan 이 보내는 Claude
// 요청 모양을 실제 모델로 직접 때려보는 진단 스크립트. (배포되는 함수가 아님 —
// `_`-prefix 라 supabase 가 무시)
//
// 무엇을 증명하나 (모두 _shared/claude.ts 의 claudeJson 경유 = 배포 코드와 같은 경로)
//   1) [VISION]     base64 JPEG + analyze-entry 스키마 → 스키마 JSON 이 오는가
//   2) [텍스트]     home-coach 스키마 → 스키마 JSON + headline 20자 이내인가
//   3) [식단]       generate-meal-plan 뼈대 1회 + 요일 상세(기본 1일, FULL_WEEK=1 이면
//                   7일 병렬) → 스키마 JSON + 소요시간이 edge 150s 한도 안인가
//
// 실행 (키는 절대 코드/리포에 넣지 말 것):
//   ANTHROPIC_API_KEY=sk-ant-... \
//   deno run --allow-net --allow-env --node-modules-dir=none \
//     app/supabase/functions/_tests/claude_probe.ts
//
// 선택 env:
//   ANTHROPIC_MODEL  (default 'claude-opus-5-5')  — prod 와 동일하게 맞춰서 테스트
//   IMAGE_URL        (음식 사진 URL. 스크립트가 받아서 base64 로 보낸다)
//   FULL_WEEK=1      (식단 7일 병렬까지 — 실제 함수와 같은 부하/지연 측정)
//
// 스키마는 각 함수 index.ts 와 동일하게 유지할 것 (충실한 재현).

import { CLAUDE_MODEL, claudeJson } from '../_shared/claude.ts';

if (!Deno.env.get('ANTHROPIC_API_KEY')) {
  console.error('✗ ANTHROPIC_API_KEY 가 필요합니다. (Edge Function Secrets 의 그 키)');
  Deno.exit(2);
}

const IMAGE_URL = Deno.env.get('IMAGE_URL') ??
  'https://upload.wikimedia.org/wikipedia/commons/4/44/Dolsot-bibimbap.jpg';
const FULL_WEEK = Deno.env.get('FULL_WEEK') === '1';

// ── analyze-entry/index.ts RESPONSE_SCHEMA ─────────────────────────────
const ANALYZE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['meal_slot', 'eating_type', 'items', 'totals', 'confidence'],
  properties: {
    meal_slot: { type: 'string', enum: ['breakfast', 'lunch', 'dinner', 'late_night'] },
    eating_type: { type: 'string', enum: ['meal', 'snack', 'beverage'] },
    items: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'name', 'qty_g', 'kcal', 'carb_g', 'protein_g', 'fat_g',
          'sodium_mg', 'sugar_g', 'confidence',
        ],
        properties: {
          name: { type: 'string' },
          qty_g: { type: 'number' },
          kcal: { type: 'integer' },
          carb_g: { type: 'number' },
          protein_g: { type: 'number' },
          fat_g: { type: 'number' },
          sodium_mg: { type: 'integer' },
          sugar_g: { type: 'number' },
          confidence: { type: 'number', description: '0~1' },
        },
      },
    },
    totals: {
      type: 'object',
      additionalProperties: false,
      required: ['kcal', 'carb_g', 'protein_g', 'fat_g', 'sodium_mg', 'sugar_g'],
      properties: {
        kcal: { type: 'integer' },
        carb_g: { type: 'number' },
        protein_g: { type: 'number' },
        fat_g: { type: 'number' },
        sodium_mg: { type: 'integer' },
        sugar_g: { type: 'number' },
      },
    },
    confidence: { type: 'number', description: '0~1' },
  },
};

// ── home-coach/index.ts RESPONSE_SCHEMA ────────────────────────────────
const HOME_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['emoji', 'headline', 'review', 'next_tip', 'focus'],
  properties: {
    emoji: { type: 'string', description: '오늘의 분위기 이모지 1개.' },
    headline: { type: 'string', description: '15자 내외 반말, 긍정/격려. 20자 초과 금지.' },
    review: { type: 'string', description: '지금까지 먹은 음식에 대한 2~3문장 긍정 코멘트.' },
    next_tip: { type: 'string', description: '현재 시각 기준 다음 식사/간식 1~2문장 구체 가이드.' },
    focus: { type: 'string', description: '지금 신경쓰면 좋을 영양소 1~2단어 (예: 단백질, 식이섬유).' },
  },
};

// ── generate-meal-plan/index.ts MEAL / SKELETON / DAY 스키마 ──────────
const SLOTS = ['breakfast', 'lunch', 'dinner', 'snack'];
const MEAL_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'slot', 'name', 'kcal', 'carb_g', 'protein_g', 'fat_g',
    'ingredients', 'recipe_brief', 'steps', 'shopping',
  ],
  properties: {
    slot: { type: 'string', enum: SLOTS },
    name: { type: 'string' },
    kcal: { type: 'integer' },
    carb_g: { type: 'integer' },
    protein_g: { type: 'integer' },
    fat_g: { type: 'integer' },
    ingredients: { type: 'array', items: { type: 'string' }, description: '주요 재료 5개 이내, 한국식 이름.' },
    recipe_brief: { type: 'string', description: '조리법 1~2문장 (반말).' },
    steps: { type: 'array', items: { type: 'string' }, description: '5~9단계, 구체적으로(반말).' },
    shopping: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'qty'],
        properties: { name: { type: 'string' }, qty: { type: 'string' } },
      },
    },
  },
};
const SKELETON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['weekly_summary', 'caveats', 'days'],
  properties: {
    weekly_summary: { type: 'string' },
    caveats: { type: 'array', items: { type: 'string' } },
    days: {
      type: 'array',
      description: '정확히 7개 (월~일).',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['date_offset', 'label', 'meals'],
        properties: {
          date_offset: { type: 'integer', description: 'week_start_date 로부터 더할 일수 0~6 (월=0)' },
          label: { type: 'string' },
          meals: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['slot', 'name', 'target_kcal'],
              properties: {
                slot: { type: 'string', enum: SLOTS },
                name: { type: 'string' },
                target_kcal: { type: 'integer' },
              },
            },
          },
        },
      },
    },
  },
};
const DAY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['date_offset', 'label', 'total_kcal', 'meals'],
  properties: {
    date_offset: { type: 'integer', description: '0~6 (월=0)' },
    label: { type: 'string' },
    total_kcal: { type: 'integer' },
    meals: { type: 'array', items: MEAL_SCHEMA },
  },
};

function header(t: string) {
  console.log('\n' + '─'.repeat(72) + '\n' + t + '\n' + '─'.repeat(72));
}

function toBase64(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(bin);
}

const results: Record<string, boolean> = {};
console.log(`모델=${CLAUDE_MODEL}  FULL_WEEK=${FULL_WEEK}`);

// ── 1) VISION ─────────────────────────────────────────────────────────
header('1) VISION — analyze-entry (base64 JPEG)');
try {
  const img = await fetch(IMAGE_URL, { headers: { 'user-agent': 'foodiet-probe/1.0' } });
  if (!img.ok) throw new Error(`image fetch ${img.status}`);
  const bytes = new Uint8Array(await img.arrayBuffer());
  const t = Date.now();
  const r = await claudeJson<{ items: Array<{ name: string; kcal: number }>; totals: { kcal: number }; confidence: number }>({
    tag: 'probe-vision',
    system: 'You are a nutrition analyst for a Korean diet tracking app. ' +
      'Analyze the meal photo and return strict JSON matching the provided schema. ' +
      'totals.kcal MUST equal sum of items.kcal (within ±5%). ' +
      'Names in Korean. Lower confidence is better than wrong.',
    content: [
      { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: toBase64(bytes) } },
      { type: 'text', text: 'Captured at: 2026-11-01T12:30:00+09:00 (locale=ko).\nReturn JSON only. No prose.' },
    ],
    schema: ANALYZE_SCHEMA,
  });
  const sum = r.items.reduce((s, it) => s + it.kcal, 0);
  console.log(`✓ ${Date.now() - t}ms  items=${r.items.length}  totals.kcal=${r.totals.kcal}  Σitems=${sum}  conf=${r.confidence}`);
  console.log('  ' + r.items.map((it) => `${it.name}(${it.kcal})`).join(', '));
  results.vision = r.items.length > 0;
} catch (e) {
  console.log(`✗ ${e}`);
  results.vision = false;
}

// ── 2) home-coach ─────────────────────────────────────────────────────
header('2) TEXT — home-coach');
try {
  const t = Date.now();
  const r = await claudeJson<{ emoji: string; headline: string; review: string; next_tip: string; focus: string }>({
    tag: 'probe-home',
    system: `당신은 Foodiet 앱의 AI 식단 코치 "푸디"입니다.
한국어 반말, 친근하고 긍정적인 톤으로 사용자의 다이어트를 응원하세요.
- "실패", "어겼다", "망쳤다", "해주세요" 등 부정/사무적인 어휘는 금지.
- 응답은 JSON 스키마에만 엄격히 맞춰주세요.
- headline 은 20자 이내. 이모지는 emoji 필드에만 넣고 본문에는 금지.`,
    content: `[프로필]
닉네임: 지훈
일일 목표: 1800 kcal

[현재 시각]
13:10 (사용자 로컬)

[오늘 섭취 현황]
먹은 끼니 2건:
  - 08:20 · breakfast · 그릭요거트 · 바나나 (320 kcal)
  - 12:40 · lunch · 제육덮밥 · 미역국 (780 kcal)

합계: 1100 / 1800 kcal (남은 700 kcal)
탄수 150g · 단백 48g · 지방 30g
나트륨 1900mg · 당 32g`,
    schema: HOME_SCHEMA,
  });
  console.log(`✓ ${Date.now() - t}ms  ${r.emoji} ${r.headline} (${[...r.headline].length}자) / focus=${r.focus}`);
  console.log(`  review: ${r.review}\n  next_tip: ${r.next_tip}`);
  results.home = typeof r.headline === 'string' && r.headline.length > 0;
} catch (e) {
  console.log(`✗ ${e}`);
  results.home = false;
}

// ── 3) generate-meal-plan ─────────────────────────────────────────────
header(`3) MEAL PLAN — 뼈대 + 요일 상세 ${FULL_WEEK ? '7일 병렬' : '1일'}`);
try {
  const ctx = `[프로필]\n일일 목표: 1800 kcal\n[입력]\n알레르기(선택): 땅콩\n포함할 끼니: breakfast, lunch, dinner\n끼니별 목표 칼로리: 아침 594kcal, 점심 594kcal, 저녁 612kcal`;
  const t0 = Date.now();
  const sk = await claudeJson<{ days: Array<{ date_offset: number; label: string; meals: Array<{ slot: string; name: string; target_kcal: number }> }> }>({
    tag: 'probe-skeleton',
    system: '당신은 Foodiet 앱의 영양 코치 "푸디"예요. 한국어 반말. 알레르기 재료는 절대 넣지 마. ' +
      '같은 요리를 7일 동안 반복하지 마. 선택한 끼니만 채워. 응답은 JSON 스키마에만 엄격히 맞추세요.',
    content: `${ctx}\n\n[요청] 이번 주(월~일) 7일치 "메뉴 뼈대"를 JSON 으로 만들어줘. days 는 정확히 7개, date_offset 0~6.`,
    schema: SKELETON_SCHEMA,
  });
  const skMs = Date.now() - t0;
  console.log(`✓ skeleton ${skMs}ms  days=${sk.days.length}  ` +
    sk.days.map((d) => d.label).join(','));
  const targets = FULL_WEEK ? sk.days.slice(0, 7) : sk.days.slice(0, 1);
  const t1 = Date.now();
  const details = await Promise.all(targets.map((d) =>
    claudeJson<{ total_kcal: number; meals: Array<{ name: string; kcal: number; steps: string[] }> }>({
      tag: `probe-day${d.date_offset}`,
      system: '당신은 Foodiet 앱의 영양 코치 "푸디"예요. 한국어 반말. 알레르기 재료(땅콩)는 넣지 마. ' +
        'meals 의 slot·name 은 주어진 그대로. steps 는 5~9단계로 아주 자세히. 응답은 JSON 스키마에만 엄격히 맞추세요.',
      content: `${ctx}\n\n[오늘 = ${d.label} (date_offset ${d.date_offset})]\n` +
        d.meals.map((m) => `- slot=${m.slot}: ${m.name} / 목표 ${m.target_kcal}kcal`).join('\n'),
      schema: DAY_SCHEMA,
    })
  ));
  const dayMs = Date.now() - t1;
  for (const d of details) {
    console.log(`  · total=${d.total_kcal}  ` + d.meals.map((m) => `${m.name}(${m.kcal}, ${m.steps.length}단계)`).join(' / '));
  }
  const total = skMs + dayMs;
  console.log(`✓ 상세 ${targets.length}일 ${dayMs}ms  → 합계 ${total}ms (edge 한도 150000ms)`);
  results.mealplan = sk.days.length === 7 && details.every((d) => d.meals.length > 0) &&
    (!FULL_WEEK || total < 150_000);
} catch (e) {
  console.log(`✗ ${e}`);
  results.mealplan = false;
}

header('결과');
for (const [k, v] of Object.entries(results)) console.log(`${v ? '✓' : '✗'} ${k}`);
Deno.exit(Object.values(results).every(Boolean) ? 0 : 1);
