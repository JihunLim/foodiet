// generate-coach — 푸디의 한마디 생성.
//
// 기획안 §4.4 / §8.3 / §10.
// 트리거: (1) entries.status='done' 직후, (2) 데일리/주간 스케줄.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const LLM_ENDPOINT = Deno.env.get('LLM_ENDPOINT')!;
const LLM_API_KEY = Deno.env.get('LLM_API_KEY')!;

// 금지어 필터 (§7.9 · §10.2 headline 후처리).
const BANNED = ['실패', '어겼다', '망쳤다', '해주세요'];

Deno.serve(async (req) => {
  const { user_id, scope, entry_id } = await req.json() as {
    user_id: string;
    scope: 'in_meal' | 'daily' | 'weekly';
    entry_id?: string;
  };

  const { data: profile } = await admin.from('profiles')
    .select('nickname, locale, daily_kcal_target, macros_target, goal_weight_kg, goal_deadline, diet_restrictions, activity_level')
    .eq('user_id', user_id).maybeSingle();

  // 오늘 합계 (PT 뷰와 달리 여기서는 본인이라 macros 포함 가능)
  const today = new Date().toISOString().slice(0, 10);
  const { data: todayRows } = await admin.from('entries')
    .select('kcal_total, macros, meal_slot')
    .eq('user_id', user_id)
    .gte('captured_at', `${today}T00:00:00Z`);

  const body = {
    profile,
    today_rows: todayRows,
    entry_id,
    scope,
    locale: profile?.locale ?? 'ko',
    style: 'friendly_banmal',
    persona: 'foodie',
  };

  const llmResp = await fetch(LLM_ENDPOINT, {
    method: 'POST',
    headers: { 'authorization': `Bearer ${LLM_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!llmResp.ok) return new Response('llm failed', { status: 502 });
  const raw = await llmResp.json() as {
    headline: string;
    why?: string;
    suggested_next_action?: unknown;
    warnings?: unknown[];
    tone?: string;
  };

  const headline = sanitize(raw.headline);
  if (!headline) return new Response(JSON.stringify({ skipped: 'banned_words' }), { status: 200 });

  const message = {
    headline,
    why: raw.why ?? null,
    suggested_next_action: raw.suggested_next_action ?? null,
    warnings: raw.warnings ?? [],
    tone: raw.tone ?? 'encouraging',
    persona: 'foodie',   // §10.2 — 프런트는 이 값이 있을 때만 FoodieBubble 렌더
  };

  const { data: inserted } = await admin.from('coach_messages').insert({
    user_id, scope, entry_id: entry_id ?? null, body_json: message,
  }).select('id').single();

  return new Response(JSON.stringify({ id: inserted?.id, message }), {
    headers: { 'content-type': 'application/json' },
  });
});

function sanitize(text: string | undefined): string | null {
  if (!text) return null;
  if (BANNED.some((b) => text.includes(b))) return null;
  return text.trim();
}
