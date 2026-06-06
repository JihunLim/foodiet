// gpt55_probe — analyze-entry / home-coach 가 쓰는 OpenAI 페이로드를 실제 모델로
// 직접 때려보는 진단 스크립트. (배포되는 함수가 아님 — `_`-prefix 라 supabase 가 무시)
//
// 무엇을 증명하나
//   1) [버그 재현]  temperature 를 보내면 gpt-5.5 가 400 으로 거부하는가
//                   → analyze-entry/home-coach 가 그동안 "안 됐던" 직접 원인.
//   2) [수정 검증]  temperature 없이(+reasoning_effort) 보내면 200 + 스키마 JSON 인가
//                   → 특히 VISION(image_url) 경로가 gpt-5.5 에서 동작하는지.
//   3) [텍스트 경로] home-coach 모양(텍스트 전용)도 200 인지.
//
// 실행 (키는 절대 코드/리포에 넣지 말 것):
//   OPENAI_API_KEY=sk-... \
//   deno run --allow-net --allow-env \
//     app/supabase/functions/_tests/gpt55_probe.ts
//
// 선택 env:
//   OPENAI_MODEL     (default 'gpt-5.5')   — prod 와 동일하게 맞춰서 테스트
//   OPENAI_ENDPOINT  (default openai chat)
//   IMAGE_URL        (음식 사진 URL — 공개 접근 가능해야 함. 기본값은 공용 도메인 음식 사진)

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY');
const OPENAI_MODEL = Deno.env.get('OPENAI_MODEL') ?? 'gpt-5.5';
const OPENAI_ENDPOINT =
  Deno.env.get('OPENAI_ENDPOINT') ?? 'https://api.openai.com/v1/chat/completions';
// OpenAI 가 서버사이드에서 직접 fetch 하는 URL. 접근 안 되면 이미지 다운로드 에러가 난다.
const IMAGE_URL = Deno.env.get('IMAGE_URL') ??
  'https://upload.wikimedia.org/wikipedia/commons/6/6d/Good_Food_Display_-_NCI_Visuals_Online.jpg';

if (!OPENAI_API_KEY) {
  console.error('✗ OPENAI_API_KEY 가 필요합니다. (Edge Function Secrets 의 그 키)');
  Deno.exit(2);
}

// analyze-entry/index.ts 의 RESPONSE_SCHEMA 와 동일 (충실한 재현).
const RESPONSE_SCHEMA = {
  name: 'foodiet_analysis',
  strict: true,
  schema: {
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
          required: ['name', 'qty_g', 'kcal', 'carb_g', 'protein_g', 'fat_g', 'sodium_mg', 'sugar_g', 'confidence'],
          properties: {
            name: { type: 'string' },
            qty_g: { type: 'number' },
            kcal: { type: 'integer' },
            carb_g: { type: 'number' },
            protein_g: { type: 'number' },
            fat_g: { type: 'number' },
            sodium_mg: { type: 'integer' },
            sugar_g: { type: 'number' },
            confidence: { type: 'number', minimum: 0, maximum: 1 },
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
      confidence: { type: 'number', minimum: 0, maximum: 1 },
    },
  },
};

const visionMessages = [
  {
    role: 'system',
    content: 'You are a nutrition analyst for a Korean diet tracking app. ' +
      'Analyze the meal photo and return strict JSON matching the provided schema. ' +
      'Names in Korean. Lower confidence is better than wrong.',
  },
  {
    role: 'user',
    content: [
      { type: 'text', text: 'Return JSON only. No prose.' },
      { type: 'image_url', image_url: { url: IMAGE_URL, detail: 'low' } },
    ],
  },
];

const HOME_SCHEMA = {
  name: 'foodie_home_coach',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['emoji', 'headline', 'review', 'next_tip', 'focus'],
    properties: {
      emoji: { type: 'string' },
      headline: { type: 'string' },
      review: { type: 'string' },
      next_tip: { type: 'string' },
      focus: { type: 'string' },
    },
  },
};

async function call(body: Record<string, unknown>) {
  const startedAt = Date.now();
  const resp = await fetch(OPENAI_ENDPOINT, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${OPENAI_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const ms = Date.now() - startedAt;
  const text = await resp.text();
  let json: any = null;
  try { json = JSON.parse(text); } catch { /* keep raw text */ }
  return { status: resp.status, ok: resp.ok, ms, text, json };
}

function header(t: string) {
  console.log('\n' + '─'.repeat(72) + '\n' + t + '\n' + '─'.repeat(72));
}

const results: Record<string, boolean> = {};

console.log(`모델=${OPENAI_MODEL}  엔드포인트=${OPENAI_ENDPOINT}`);
console.log(`이미지=${IMAGE_URL}`);

// ── Probe 1: temperature 동봉 → gpt-5.5 가 거부(400)하는지 (버그 원인 재현) ──
header('Probe 1 ─ VISION + temperature:0.2  (기대: 400, "temperature" 언급)');
{
  const r = await call({
    model: OPENAI_MODEL,
    messages: visionMessages,
    response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
    temperature: 0.2,
  });
  const mentionsTemp = /temperature/i.test(r.text);
  console.log(`status=${r.status} (${r.ms}ms)  temperature 언급=${mentionsTemp}`);
  console.log('  → ' + r.text.slice(0, 400).replace(/\n/g, ' '));
  // 버그가 맞다면 400 + temperature 언급. (모델이 temperature 를 그냥 무시해 200 이 나오면
  //  버그 원인은 temperature 가 아니라는 신호 → 그래도 Probe 2 가 핵심.)
  results['probe1_temperature_rejected'] = r.status === 400 && mentionsTemp;
}

// ── Probe 2: 수정된 페이로드 (temperature 없음 + reasoning_effort) → 200 + 스키마 JSON ──
header('Probe 2 ─ VISION + reasoning_effort:low, NO temperature  (기대: 200 + 스키마 JSON)');
{
  let body: Record<string, unknown> = {
    model: OPENAI_MODEL,
    messages: visionMessages,
    response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
    reasoning_effort: 'low',
  };
  let r = await call(body);
  // 함수와 동일하게: reasoning_effort 를 모델이 거부하면 떨구고 재시도.
  if (r.status === 400 && /reasoning_effort/i.test(r.text)) {
    console.log('  (모델이 reasoning_effort 거부 → 떨구고 재시도)');
    delete body.reasoning_effort;
    r = await call(body);
  }
  console.log(`status=${r.status} (${r.ms}ms)`);
  let schemaOk = false;
  if (r.ok) {
    const content = r.json?.choices?.[0]?.message?.content;
    try {
      const parsed = JSON.parse(content);
      const keys = ['meal_slot', 'eating_type', 'items', 'totals', 'confidence'];
      schemaOk = keys.every((k) => k in parsed) && Array.isArray(parsed.items);
      console.log('  파싱된 JSON 키:', Object.keys(parsed).join(', '));
      console.log('  meal_slot=%s eating_type=%s items=%d totals.kcal=%s confidence=%s',
        parsed.meal_slot, parsed.eating_type, parsed.items?.length, parsed.totals?.kcal, parsed.confidence);
      console.log('  items[0]:', JSON.stringify(parsed.items?.[0] ?? null));
    } catch (e) {
      console.log('  ✗ content JSON 파싱 실패:', String(e), '\n  content=', String(content).slice(0, 300));
    }
  } else {
    console.log('  → ' + r.text.slice(0, 500).replace(/\n/g, ' '));
  }
  results['probe2_vision_ok'] = r.ok && schemaOk;
}

// ── Probe 3: home-coach 모양 (텍스트 전용) → 200 ──
header('Probe 3 ─ TEXT only + reasoning_effort:low  (기대: 200 + 스키마 JSON)');
{
  let body: Record<string, unknown> = {
    model: OPENAI_MODEL,
    messages: [
      { role: 'system', content: '당신은 Foodiet 앱의 AI 식단 코치 "푸디". 한국어 반말. JSON 스키마에만 맞춰 응답.' },
      { role: 'user', content: '오늘 점심에 김치볶음밥 600kcal 먹었어. 다음 끼니 가이드 한 줄 줘.' },
    ],
    response_format: { type: 'json_schema', json_schema: HOME_SCHEMA },
    reasoning_effort: 'low',
  };
  let r = await call(body);
  if (r.status === 400 && /reasoning_effort/i.test(r.text)) {
    delete body.reasoning_effort;
    r = await call(body);
  }
  console.log(`status=${r.status} (${r.ms}ms)`);
  let ok = false;
  if (r.ok) {
    try {
      const parsed = JSON.parse(r.json?.choices?.[0]?.message?.content);
      ok = ['emoji', 'headline', 'review', 'next_tip', 'focus'].every((k) => k in parsed);
      console.log('  headline=%s  focus=%s', parsed.headline, parsed.focus);
    } catch (e) {
      console.log('  ✗ JSON 파싱 실패:', String(e));
    }
  } else {
    console.log('  → ' + r.text.slice(0, 500).replace(/\n/g, ' '));
  }
  results['probe3_text_ok'] = ok;
}

// ── 요약 ──
header('요약');
for (const [k, v] of Object.entries(results)) {
  console.log(`${v ? '✓ PASS' : '✗ FAIL'}  ${k}`);
}
const verdict =
  results['probe2_vision_ok'] && results['probe3_text_ok']
    ? '\n✅ 결론: gpt-5.5 가 (temperature 제거 후) VISION+텍스트 모두 정상. 수정된 함수 페이로드가 동작함.'
    : '\n⚠️  결론: Probe 2/3 중 실패가 있음 — 위 상세 출력을 확인. (모델명/키/쿼터/엔드포인트 점검)';
console.log(verdict);
// CI 친화: 핵심(2,3) 실패 시 비정상 종료코드.
Deno.exit(results['probe2_vision_ok'] && results['probe3_text_ok'] ? 0 : 1);
