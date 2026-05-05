// analyze-entry — 업로드된 사진을 멀티모달 LLM 으로 분석.
//
// 기획안 §4.2 / §4.3 / §8.2 / §9 / §18.1 #7.
// 트리거: Flutter 클라이언트가 업로드 직후 invoke(). 재시도는 클라이언트 또는
//         cron 이 status='pending' 을 폴링해서 수행.
//
// 순서
//   1) entries row 조회 (service role — RLS 우회)
//   2) food-photos 버킷에서 서명 URL 생성 (5분)
//   3) OpenAI gpt-5.4-mini Vision 호출 (response_format: json_schema)
//   4) entries UPDATE + entry_items 다중 INSERT
//   5) 신뢰도 낮거나 meal_slot 경계시간이면 coach_messages 로 "확인해줘" 전송
//
// ENV (Supabase Dashboard → Edge Functions → Secrets):
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

const RESPONSE_SCHEMA = {
  name: 'foodiet_analysis',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['meal_slot', 'eating_type', 'items', 'totals', 'confidence'],
    properties: {
      meal_slot: {
        type: 'string',
        enum: ['breakfast', 'lunch', 'dinner', 'late_night'],
      },
      eating_type: {
        type: 'string',
        enum: ['meal', 'snack', 'beverage'],
      },
      items: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: [
            'name', 'qty_g', 'kcal',
            'carb_g', 'protein_g', 'fat_g',
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
            confidence: { type: 'number', minimum: 0, maximum: 1 },
          },
        },
      },
      totals: {
        type: 'object',
        additionalProperties: false,
        required: ['kcal', 'carb_g', 'protein_g', 'fat_g',
                   'sodium_mg', 'sugar_g'],
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
} as const;

type LlmResult = {
  meal_slot: 'breakfast' | 'lunch' | 'dinner' | 'late_night';
  eating_type: 'meal' | 'snack' | 'beverage';
  items: Array<{
    name: string;
    qty_g: number;
    kcal: number;
    carb_g: number;
    protein_g: number;
    fat_g: number;
    sodium_mg: number;
    sugar_g: number;
    confidence: number;
  }>;
  totals: {
    kcal: number;
    carb_g: number;
    protein_g: number;
    fat_g: number;
    sodium_mg: number;
    sugar_g: number;
  };
  confidence: number;
};

async function analyze(imageUrl: string, capturedAt: string, locale: string) {
  const priorSlot = timeBasedMealSlot(capturedAt, locale) ?? 'unknown';

  const systemPrompt = `You are a nutrition analyst for a Korean diet tracking app.
Analyze the meal photo and return strict JSON matching the provided schema.

Rules:
- meal_slot axis (time of day): breakfast / lunch / dinner / late_night.
  Time prior for this capture (local): ${priorSlot}.
  Use the prior as a strong hint unless the image strongly suggests otherwise.
- eating_type axis (food kind): meal / snack / beverage. Do NOT confuse with meal_slot.
  Coffee at 10pm → meal_slot=late_night, eating_type=beverage.
- Estimate per-item calories and macros in metric units (g, mg).
  If unsure of quantity, assume a typical serving for a Korean adult.
- totals.kcal MUST equal sum of items.kcal (within ±5%).
- confidence 0..1 overall; item-level confidence too. Lower is better than wrong.
- Names in Korean if locale starts with 'ko', English otherwise.`;

  const userPrompt = `Captured at: ${capturedAt} (locale=${locale}).
Return JSON only. No prose.`;

  const body = {
    model: OPENAI_MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      {
        role: 'user',
        content: [
          { type: 'text', text: userPrompt },
          { type: 'image_url', image_url: { url: imageUrl, detail: 'low' } },
        ],
      },
    ],
    response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
    temperature: 0.2,
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
    const text = await resp.text().catch(() => '');
    throw new Error(`OpenAI ${resp.status}: ${text.slice(0, 300)}`);
  }
  const json = await resp.json();
  const content: string = json?.choices?.[0]?.message?.content;
  if (!content) throw new Error('OpenAI: empty content');

  let parsed: LlmResult;
  try {
    parsed = JSON.parse(content) as LlmResult;
  } catch (e) {
    throw new Error(`OpenAI: invalid JSON: ${(e as Error).message}`);
  }
  return parsed;
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

  // 2) 서명 URL
  const { data: signed, error: sErr } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(entry.image_path, 300);
  if (sErr || !signed?.signedUrl) {
    console.error('sign url error', sErr);
    await admin.from('entries').update({ status: 'failed' }).eq('id', entry_id);
    return new Response('sign url failed', { status: 500 });
  }

  // 3) LLM 호출
  let result: LlmResult;
  try {
    result = await analyze(
      signed.signedUrl,
      entry.captured_at,
      entry.locale ?? 'ko',
    );
  } catch (e) {
    console.error('llm error', e);
    await admin.from('entries').update({ status: 'failed' }).eq('id', entry_id);
    return new Response(`llm failed: ${(e as Error).message}`, { status: 502 });
  }

  // 4) entries UPDATE + entry_items INSERT.
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

  const { error: uErr } = await admin
    .from('entries')
    .update({
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
    })
    .eq('id', entry_id);
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

  // 5) 저신뢰 또는 경계시간 → 확인 요청
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
