// home-coach/context.ts 순수 함수 테스트 (네트워크 없음).
//
//   deno test --node-modules-dir=none --allow-read \
//     app/supabase/functions/_tests/home_coach_context_test.ts

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from 'jsr:@std/assert@1';
import {
  BANNED,
  buildSignature,
  buildSystemPrompt,
  buildUserPrompt,
  type CoachContext,
  effectiveMode,
  kcalFloor,
  localDateKey,
  mondayKey,
  sanitizeResult,
  shiftDateKey,
  summarizeWeek,
  todayPlanMeals,
  weekdayIndex,
  weekSummaryKey,
} from '../home-coach/context.ts';

const KST = 540;

// 2026-11-16 은 월요일. 지난 7일 = 11-09(월) ~ 11-15(일).
const TODAY = '2026-11-16';

function row(
  localIso: string,
  kcal: number,
  opts: { slot?: string; sodium?: number; share?: number } = {},
) {
  // localIso 는 KST 벽시계 시각. UTC 로 바꿔 captured_at 으로 넣는다.
  const utc = new Date(new Date(`${localIso}+09:00`).getTime()).toISOString();
  return {
    captured_at: utc,
    kcal_total: kcal,
    macros: { sodium_mg: opts.sodium ?? 0 },
    shared_with_count: opts.share ?? 1,
    meal_slot: opts.slot ?? 'lunch',
  };
}

Deno.test('localDateKey: KST 자정 직후는 다음 날', () => {
  // 2026-11-15T15:30Z = KST 11-16 00:30
  assertEquals(localDateKey('2026-11-15T15:30:00Z', KST), '2026-11-16');
  assertEquals(localDateKey('2026-11-15T14:59:00Z', KST), '2026-11-15');
});

Deno.test('shiftDateKey / weekdayIndex / mondayKey', () => {
  assertEquals(shiftDateKey('2026-11-16', -1), '2026-11-15');
  assertEquals(shiftDateKey('2026-03-01', -1), '2026-02-28');
  assertEquals(weekdayIndex('2026-11-16'), 0); // 월
  assertEquals(weekdayIndex('2026-11-22'), 6); // 일
  assertEquals(mondayKey('2026-11-22'), '2026-11-16');
  assertEquals(mondayKey('2026-11-16'), '2026-11-16');
});

Deno.test('summarizeWeek: 기록 없음', () => {
  const s = summarizeWeek([], KST, TODAY);
  assertEquals(s.loggedDays, 0);
  assertEquals(s.avgKcal, 0);
  assertEquals(s.yesterdayKcal, null);
  assertEquals(s.weekdayAvgKcal, null);
  assertEquals(s.weekendAvgKcal, null);
});

Deno.test('summarizeWeek: 기록일 기준 평균·야식·주말/평일·어제', () => {
  const rows = [
    row('2026-11-10T12:00:00', 600, { sodium: 1000 }), // 화
    row('2026-11-10T19:00:00', 900, { sodium: 1000 }),
    row('2026-11-11T23:00:00', 500, { slot: 'late_night', sodium: 500 }), // 수 야식
    row('2026-11-14T12:00:00', 1200, { sodium: 2000 }), // 토
    row('2026-11-15T12:00:00', 2400, { sodium: 3000, share: 2 }), // 일(=어제), 1인분 1200
    row('2026-11-15T23:30:00', 600, { slot: 'late_night' }),
    // 오늘 기록은 들어와도 무시되어야 한다.
    row('2026-11-16T08:00:00', 999),
  ];
  const s = summarizeWeek(rows, KST, TODAY);
  assertEquals(s.loggedDays, 4);
  // 일별 합: 화 1500, 수 500, 토 1200, 일 1800 → 평균 1250
  assertEquals(s.avgKcal, 1250);
  assertEquals(s.lateNightDays, 2);
  assertEquals(s.weekdayAvgKcal, 1000); // (1500+500)/2
  assertEquals(s.weekendAvgKcal, 1500); // (1200+1800)/2
  // 나트륨 일별: 화 2000, 수 500, 토 2000, 일 1500 → 평균 1500
  assertEquals(s.avgSodiumMg, 1500);
  assertEquals(s.yesterdayKcal, 1800);
});

Deno.test('summarizeWeek: 7일보다 오래된 기록은 제외', () => {
  const s = summarizeWeek([row('2026-11-08T12:00:00', 700)], KST, TODAY);
  assertEquals(s.loggedDays, 0);
});

Deno.test('weekSummaryKey 는 같은 요약이면 같고 다르면 다르다', () => {
  const a = summarizeWeek([row('2026-11-10T12:00:00', 600)], KST, TODAY);
  const b = summarizeWeek([row('2026-11-10T12:00:00', 600)], KST, TODAY);
  const c = summarizeWeek([row('2026-11-10T12:00:00', 700)], KST, TODAY);
  assertEquals(weekSummaryKey(a), weekSummaryKey(b));
  assert(weekSummaryKey(a) !== weekSummaryKey(c));
  assert(!weekSummaryKey(a).includes('|'), 'signature 구분자와 겹치면 안 됨');
});

Deno.test('effectiveMode: lose 인데 목표>현재면 gain, 그 외 그대로', () => {
  assertEquals(effectiveMode('lose', 70, 60), 'gain');
  assertEquals(effectiveMode('lose', 55, 60), 'lose');
  assertEquals(effectiveMode('maintain', 70, 60), 'maintain');
  assertEquals(effectiveMode('gain', null, null), 'gain');
  assertEquals(effectiveMode(undefined, null, 60), 'lose');
  assertEquals(effectiveMode('weird', '70', '60'), 'gain');
});

Deno.test('kcalFloor: 남 1500 / 여·미입력 1200', () => {
  assertEquals(kcalFloor('male'), 1500);
  assertEquals(kcalFloor('female'), 1200);
  assertEquals(kcalFloor(null), 1200);
});

Deno.test('todayPlanMeals: date_offset 매칭, 깨진 모양은 빈 배열', () => {
  const plan = {
    days: [
      { date_offset: 1, meals: [{ slot: 'lunch', name: '닭가슴살 샐러드' }] },
      {
        date_offset: 0,
        meals: [
          { slot: 'breakfast', name: '그릭요거트볼' },
          { slot: 'dinner', name: '연어 포케' },
          { slot: 'lunch' }, // 이름 없음 → 제외
        ],
      },
    ],
  };
  assertEquals(todayPlanMeals(plan, 0), [
    { slot: 'breakfast', name: '그릭요거트볼' },
    { slot: 'dinner', name: '연어 포케' },
  ]);
  assertEquals(todayPlanMeals(plan, 1).map((m) => m.name), ['닭가슴살 샐러드']);
  assertEquals(todayPlanMeals(plan, 5), []);
  assertEquals(todayPlanMeals(null, 0), []);
  assertEquals(todayPlanMeals({ days: 'x' }, 0), []);
});

function baseCtx(over: Partial<CoachContext> = {}): CoachContext {
  return {
    nickname: '지훈',
    target: 1800,
    floor: 1500,
    goalWeightKg: 70,
    activityLevel: 3,
    dietRestrictions: [],
    nowLabel: '13:10',
    eaten: [{ time: '08:20', slot: 'breakfast', title: '그릭요거트', kcal: 320 }],
    kcalConsumed: 320,
    remaining: 1480,
    carb: 40,
    protein: 20,
    fat: 8,
    sodium: 120,
    sugar: 18,
    week: summarizeWeek([row('2026-11-15T12:00:00', 2600)], KST, TODAY),
    experiment: null,
    mode: 'lose',
    glp1: false,
    planMeals: [],
    ...over,
  };
}

Deno.test('buildUserPrompt: 새 블록 5개가 모두 들어간다', () => {
  const p = buildUserPrompt(baseCtx({
    experiment: '야식이 당기면 따뜻한 차 먼저 마시기',
    glp1: true,
    mode: 'maintain',
    planMeals: [{ slot: 'dinner', name: '연어 포케' }],
  }));
  for (const block of ['[최근 7일]', '[이번 주 실험]', '[모드]', '[GLP-1]', '[오늘 추천 식단]']) {
    assertStringIncludes(p, block);
  }
  assertStringIncludes(p, '야식이 당기면 따뜻한 차 먼저 마시기');
  assertStringIncludes(p, '연어 포케');
  assertStringIncludes(p, '유지');
  assertStringIncludes(p, '어제');
});

Deno.test('buildUserPrompt: 없는 정보는 "없음" 으로 표시', () => {
  const p = buildUserPrompt(baseCtx({
    week: summarizeWeek([], KST, TODAY),
  }));
  assertStringIncludes(p, '[이번 주 실험]\n없음');
  assertStringIncludes(p, '[GLP-1]\n사용 안 함');
  assertStringIncludes(p, '[오늘 추천 식단]\n없음');
  assertStringIncludes(p, '최근 7일 기록 없음');
});

Deno.test('buildSystemPrompt: 굶기 금지·하한·GLP-1·실험 규칙 포함', () => {
  const s = buildSystemPrompt(1200);
  assertStringIncludes(s, '1200');
  assertStringIncludes(s, '굶');
  assertStringIncludes(s, 'GLP-1');
  assertStringIncludes(s, '실험');
  for (const b of BANNED) assertStringIncludes(s, b); // 금지어 목록 명시
  // 사용자가 직접 입력한 실험이 굶기·하한 미만이면 상기하지 않는다.
  assertStringIncludes(s, '실험이 끼니 거르기·굶기·단식이거나 하루 1200 kcal 아래');
});

Deno.test('buildSignature: 날짜·주간 요약·실험·모드·GLP-1 포함', () => {
  const sig = buildSignature({
    base: 'd:1|k:320|c:40|p:20|f:8',
    dayKey: TODAY,
    weekKey: 'abc',
    experiment: '차 먼저',
    mode: 'gain',
    glp1: true,
    planCount: 2,
  });
  assertEquals(
    sig,
    'd:1|k:320|c:40|p:20|f:8|day:2026-11-16|w:abc|x:차 먼저|m:gain|g:1|pl:2',
  );
  const none = buildSignature({
    base: 'b',
    dayKey: TODAY,
    weekKey: 'w',
    experiment: null,
    mode: 'lose',
    glp1: false,
    planCount: 0,
  });
  assertEquals(none, 'b|day:2026-11-16|w:w|x:|m:lose|g:0|pl:0');
});

Deno.test('sanitizeResult: 금지어가 들어간 필드는 안전 문구로', () => {
  const r = sanitizeResult({
    emoji: '🍓',
    headline: '어제 망쳤다',
    review: '나쁜 음식을 먹었어.',
    next_tip: '저녁은 굶어서 만회해주세요.',
    focus: '단백질',
  });
  for (const b of BANNED) {
    assert(!r.headline.includes(b));
    assert(!r.review.includes(b));
    assert(!r.next_tip.includes(b));
  }
  assertEquals(r.focus, '단백질');

  const ok = sanitizeResult({
    emoji: '🥗',
    headline: '좋은 흐름이야',
    review: '단백질 잘 챙겼어.',
    next_tip: '저녁은 채소 듬뿍.',
    focus: '식이섬유',
  });
  assertEquals(ok.review, '단백질 잘 챙겼어.');
});

Deno.test('sanitizeResult: 20자 초과 headline·투약 어휘·빈 필드는 안전 문구로', () => {
  const r = sanitizeResult({
    emoji: '',
    headline: '어제 많이 먹었어도 오늘 균형 있게 먹으면 충분해', // 20자 초과
    review: '투약 다음 날이라 입맛이 없을 수 있어.',
    next_tip: '주사 맞은 날엔 양을 줄여봐.',
    focus: '',
  });
  assert([...r.headline].length <= 20);
  assertEquals(r.headline, '오늘도 같이 가보자');
  for (const w of ['투약', '용량', '주사']) {
    assert(!r.review.includes(w));
    assert(!r.next_tip.includes(w));
  }
  assertEquals(r.focus, '균형');
  assertEquals(r.emoji, '🍓');

  const ok = sanitizeResult({
    emoji: '🥗',
    headline: '스무자 딱 맞는 헤드라인이야 좋아좋아',
    review: '좋아.',
    next_tip: '물 한 잔.',
    focus: '단백질',
  });
  assertEquals(ok.headline, '스무자 딱 맞는 헤드라인이야 좋아좋아');
});
