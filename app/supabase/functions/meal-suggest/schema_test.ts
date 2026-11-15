// meal-suggest 순수 로직 단위 테스트 (네트워크 없음).
//
// 실행:
//   deno test --node-modules-dir=none --allow-read \
//     app/supabase/functions/meal-suggest/schema_test.ts

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  BANNED,
  buildSystemPrompt,
  buildUserPrompt,
  effectiveMode,
  effectiveTarget,
  hasBanned,
  HOESIK_SCHEMA,
  LIGHT_INTRO,
  OPTIONS_SCHEMA,
  parseSituation,
  postprocessHoesik,
  postprocessOptions,
  type SuggestContext,
} from './schema.ts';

const opt = (name: string, kcal: number, extra: Partial<Record<string, unknown>> = {}) => ({
  name,
  kcal,
  protein_g: 20.4,
  carb_g: 30.6,
  fat_g: 8.2,
  why: '단백질이 채워져서 든든해',
  tip: '소스는 반만 넣자',
  ...extra,
});

function ctx(over: Partial<SuggestContext> = {}): SuggestContext {
  return {
    situation: 'convenience',
    nowLabel: '13:10',
    target: 1800,
    consumed: 1100,
    remaining: 700,
    proteinG: 48,
    eatenTitles: ['그릭요거트', '제육덮밥'],
    mode: 'lose',
    glp1: false,
    dietRestrictions: [],
    ...over,
  };
}

// ── 스키마: structured outputs 금지 키워드가 없어야 한다 ─────────────
Deno.test('schemas_have_no_unsupported_constraints', () => {
  const forbidden = [
    'minimum', 'maximum', 'minItems', 'maxItems', 'minLength', 'maxLength',
    'exclusiveMinimum', 'exclusiveMaximum',
  ];
  for (const schema of [OPTIONS_SCHEMA, HOESIK_SCHEMA]) {
    const json = JSON.stringify(schema);
    for (const k of forbidden) {
      assert(!json.includes(`"${k}"`), `schema contains ${k}`);
    }
  }
});

// ── situation 파싱 ──────────────────────────────────────────────────
Deno.test('parseSituation_accepts_known_rejects_unknown', () => {
  assertEquals(parseSituation('home'), 'home');
  assertEquals(parseSituation('hoesik'), 'hoesik');
  assertEquals(parseSituation('eating_out'), 'eating_out');
  assertEquals(parseSituation('picnic'), null);
  assertEquals(parseSituation(undefined), null);
  assertEquals(parseSituation(3), null);
});

// ── 목표·모드 ────────────────────────────────────────────────────────
Deno.test('effectiveTarget_applies_floor_by_sex', () => {
  assertEquals(effectiveTarget(1000, 'male'), 1500);
  assertEquals(effectiveTarget(1000, 'female'), 1200);
  assertEquals(effectiveTarget(1000, null), 1200);
  assertEquals(effectiveTarget(null, null), 1800);
  assertEquals(effectiveTarget(2100, 'male'), 2100);
});

Deno.test('effectiveMode_lose_with_higher_goal_is_gain', () => {
  assertEquals(effectiveMode({ goal_mode: 'lose', goal_weight_kg: 70, weight_kg: 60 }), 'gain');
  assertEquals(effectiveMode({ goal_mode: 'lose', goal_weight_kg: 55, weight_kg: 60 }), 'lose');
  assertEquals(effectiveMode({ goal_mode: 'maintain', goal_weight_kg: 70, weight_kg: 60 }), 'maintain');
  assertEquals(effectiveMode({ goal_mode: 'gain' }), 'gain');
  assertEquals(effectiveMode({}), 'lose');
  assertEquals(effectiveMode(null), 'lose');
  assertEquals(effectiveMode({ goal_mode: 'weird' }), 'lose');
});

// ── 옵션 후처리 ──────────────────────────────────────────────────────
Deno.test('postprocessOptions_slices_to_3_and_rounds', () => {
  const r = postprocessOptions(
    { intro: '편의점에서 이렇게 골라보자', options: [opt('a', 300.6), opt('b', 410), opt('c', 250), opt('d', 200)] },
    700,
  );
  assertEquals(r.kind, 'options');
  assertEquals(r.options.length, 3);
  assertEquals(r.options[0].kcal, 301);
  assertEquals(r.options[0].protein_g, 20);
  assertEquals(r.options[0].carb_g, 31);
  assertEquals(r.remaining_kcal, 700);
  assertEquals(r.intro, '편의점에서 이렇게 골라보자');
});

Deno.test('postprocessOptions_clamps_negative_numbers', () => {
  const r = postprocessOptions({ intro: 'hi', options: [opt('a', -20, { fat_g: -3 })] }, 500);
  assertEquals(r.options[0].kcal, 0);
  assertEquals(r.options[0].fat_g, 0);
});

Deno.test('postprocessOptions_remaining_zero_keeps_at_most_2_and_light_intro', () => {
  const r = postprocessOptions(
    { intro: '아무 말', options: [opt('삶은 계란', 80), opt('두유', 130), opt('닭가슴살', 120)] },
    0,
  );
  assertEquals(r.options.length, 2);
  assertEquals(r.remaining_kcal, 0);
  assertEquals(r.intro, LIGHT_INTRO);
  assert(r.intro.includes('오늘은 여기까지 가볍게'));
});

Deno.test('postprocessOptions_negative_remaining_reported_as_zero', () => {
  const r = postprocessOptions({ intro: 'x', options: [opt('a', 80)] }, -350);
  assertEquals(r.remaining_kcal, 0);
  assertEquals(r.intro, LIGHT_INTRO);
});

Deno.test('postprocessOptions_drops_options_with_banned_words', () => {
  const r = postprocessOptions(
    {
      intro: '좋아',
      options: [
        opt('컵라면', 400, { why: '나쁜 음식이지만 괜찮아' }),
        opt('샐러드', 200),
        opt('김밥', 350, { tip: '어제 망쳤다면 오늘은 조금만' }),
      ],
    },
    700,
  );
  assertEquals(r.options.map((o) => o.name), ['샐러드']);
});

Deno.test('postprocessOptions_banned_intro_replaced', () => {
  const r = postprocessOptions({ intro: '이건 꼭 해주세요', options: [opt('샐러드', 200)] }, 700);
  for (const b of BANNED) assert(!r.intro.includes(b));
  assert(r.intro.length > 0);
});

Deno.test('postprocessOptions_drops_empty_names_and_tolerates_garbage', () => {
  const r = postprocessOptions(
    { intro: 3, options: [{ name: '  ' }, 'x', null, opt('샐러드', 200)] } as unknown,
    700,
  );
  assertEquals(r.options.length, 1);
  assertEquals(r.options[0].name, '샐러드');
  assert(typeof r.intro === 'string' && r.intro.length > 0);
});

Deno.test('postprocessOptions_null_input_gives_empty_options', () => {
  const r = postprocessOptions(null, 700);
  assertEquals(r.options, []);
  assertEquals(r.kind, 'options');
});

Deno.test('banned_list_includes_bad_food', () => {
  assert(BANNED.includes('나쁜 음식'));
  assert(BANNED.includes('실패'));
});

Deno.test('hasBanned_catches_efficacy_and_medication_talk', () => {
  assert(hasBanned('이거 먹으면 3kg 감량'));
  assert(hasBanned('살 빠지는 음식이야'));
  assert(hasBanned('살이 쭉 빠져'));
  assert(hasBanned('효과 보장'));
  assert(hasBanned('투약한 날엔 이걸 먹어'));
  assert(hasBanned('위고비 맞는 중이면 소량으로'));
  assert(!hasBanned('닭가슴살 샐러드에 드레싱은 따로'));
  assert(!hasBanned('물 한 잔 같이 마시자'));
  assert(!hasBanned(LIGHT_INTRO));
});

// ── 회식 후처리 ──────────────────────────────────────────────────────
Deno.test('postprocessHoesik_trims_filters_and_caps', () => {
  const r = postprocessHoesik({
    intro: '회식도 즐기면서 가자',
    before: ['  출발 전에 단백질 간식 하나  ', '', '실패해도 괜찮아'],
    order_tips: ['a', 'b', 'c', 'd', 'e', 'f'],
    drink_tips: ['술 한 잔에 물 한 잔'],
    next_day: ['평소처럼 아침 먹기'],
  });
  assertEquals(r.kind, 'hoesik');
  assertEquals(r.before, ['출발 전에 단백질 간식 하나']);
  assertEquals(r.order_tips.length, 4);
  assertEquals(r.drink_tips, ['술 한 잔에 물 한 잔']);
  assertEquals(r.next_day, ['평소처럼 아침 먹기']);
});

Deno.test('postprocessHoesik_garbage_gives_fallback_items', () => {
  const r = postprocessHoesik({ intro: null, before: 'x' } as unknown);
  assert(r.intro.length > 0);
  assert(r.before.length > 0);
  assert(r.order_tips.length > 0);
  assert(r.drink_tips.length > 0);
  assert(r.next_day.length > 0);
  const all = [r.intro, ...r.before, ...r.order_tips, ...r.drink_tips, ...r.next_day].join(' ');
  for (const b of BANNED) assert(!all.includes(b));
  // 다음 날 굶기 권유가 고정 문구에 없어야 한다.
  assert(!all.includes('굶'));
});

// ── 프롬프트 ─────────────────────────────────────────────────────────
Deno.test('systemPrompt_contains_safety_rules', () => {
  const s = buildSystemPrompt(ctx());
  assert(s.includes('굶'), 'no-skipping rule');
  assert(s.includes('1200') && s.includes('1500'), 'kcal floor');
  for (const b of ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식']) {
    assert(s.includes(b), `banned word listed: ${b}`);
  }
});

Deno.test('systemPrompt_glp1_line_only_when_flagged', () => {
  assert(!buildSystemPrompt(ctx({ glp1: false })).includes('GLP-1'));
  const s = buildSystemPrompt(ctx({ glp1: true }));
  assert(s.includes('GLP-1'));
  assert(s.includes('수분'));
});

Deno.test('userPrompt_remaining_zero_does_not_say_over', () => {
  const u = buildUserPrompt(ctx({ consumed: 2100, remaining: 0 }));
  assert(!u.includes('초과'));
  assert(u.includes('남은 0'));
});

Deno.test('userPrompt_mode_and_situation_reflected', () => {
  const u = buildUserPrompt(ctx({ mode: 'maintain', situation: 'delivery' }));
  assert(u.includes('유지'));
  assert(u.includes('배달'));
  const h = buildUserPrompt(ctx({ situation: 'hoesik' }));
  assert(h.includes('회식'));
});

Deno.test('userPrompt_convenience_mentions_real_store', () => {
  const s = buildSystemPrompt(ctx({ situation: 'convenience' }));
  assert(s.includes('편의점'));
});
