// analyze-entry 한 끼 피드백 후처리(postProcessFeedback) 단위 테스트. 네트워크 없음.
//
// 실행:
//   deno test --node-modules-dir=none --allow-read \
//     app/supabase/functions/_tests/feedback_postprocess_test.ts

import assert from 'node:assert/strict';
import {
  FEEDBACK_FALLBACK_HEADLINE,
  postProcessFeedback,
} from '../analyze-entry/schema.ts';
import {
  buildUserContextLine,
  effectiveGoalMode,
  localDayStartUtc,
} from '../analyze-entry/context.ts';

function base(check: unknown) {
  return {
    headline: '단백질 든든한 점심',
    good: '제육에 채소까지 같이 챙겼네.',
    next: '다음엔 국물은 반만 남겨보자.',
    check,
  };
}

const opt = (label: string, kf: number, sf: number) => ({
  label,
  kcal_factor: kf,
  sodium_factor: sf,
});

Deno.test('factor 는 [0.2, 1.3] 로 clamp', () => {
  const fb = postProcessFeedback(base({
    kind: 'rice',
    question: '밥은 얼마나 먹었어?',
    options: [opt('다 먹었어', 1, 1), opt('곱빼기', 5.0, 5.0), opt('조금', -1, -1)],
  }));
  assert.ok(fb);
  const o = fb.check.options;
  assert.equal(o.length, 3);
  assert.equal(o[1].kcal_factor, 1.3);
  assert.equal(o[1].sodium_factor, 1.3);
  assert.equal(o[2].kcal_factor, 0.2);
  assert.equal(o[2].sodium_factor, 0.2);
});

Deno.test('options 6개 → 4개', () => {
  const fb = postProcessFeedback(base({
    kind: 'portion',
    question: '얼마나 먹었어?',
    options: [
      opt('다 먹었어', 1, 1),
      opt('3/4', 0.75, 0.75),
      opt('반', 0.5, 0.5),
      opt('1/4', 0.25, 0.25),
      opt('한입', 0.2, 0.2),
      opt('더 먹었어', 1.2, 1.2),
    ],
  }));
  assert.ok(fb);
  assert.equal(fb.check.options.length, 4);
});

Deno.test('잘릴 위치의 1.0 옵션은 살아남는다', () => {
  const fb = postProcessFeedback(base({
    kind: 'portion',
    question: '얼마나 먹었어?',
    options: [
      opt('3/4', 0.75, 0.75),
      opt('반', 0.5, 0.5),
      opt('1/4', 0.25, 0.25),
      opt('한입', 0.2, 0.2),
      opt('다 먹었어', 1, 1),
    ],
  }));
  assert.ok(fb);
  assert.equal(fb.check.options.length, 4);
  assert.equal(fb.check.options[0].label, '다 먹었어');
});

Deno.test('kcal 만 1.0 인 soup 옵션은 "다 먹었어" 가 아님 — 1/1 옵션이 첫 자리', () => {
  const fb = postProcessFeedback(base({
    kind: 'soup',
    question: '국물은 얼마나 마셨어?',
    options: [
      opt('국물은 남겼어', 1, 0.4),
      opt('반쯤 마셨어', 1, 0.7),
      opt('건더기도 남겼어', 0.7, 0.3),
      opt('조금만', 0.5, 0.3),
      opt('다 마셨어', 1, 1),
    ],
  }));
  assert.ok(fb);
  assert.equal(fb.check.options.length, 4);
  assert.equal(fb.check.options[0].label, '다 마셨어');
  assert.equal(fb.check.options[1].label, '국물은 남겼어');
});

Deno.test('1/1 옵션이 없으면 "다 먹었어" 를 첫 자리에 채움', () => {
  const fb = postProcessFeedback(base({
    kind: 'rice',
    question: '밥은 얼마나 먹었어?',
    options: [opt('반 공기', 0.6, 1), opt('한 숟갈', 0.3, 1)],
  }));
  assert.ok(fb);
  assert.deepEqual(fb.check.options.map((o) => o.label), ['다 먹었어', '반 공기', '한 숟갈']);
  assert.equal(fb.check.options[0].kcal_factor, 1);
  assert.equal(fb.check.options[0].sodium_factor, 1);
});

Deno.test("kind 'none' → options [] · question ''", () => {
  const fb = postProcessFeedback(base({
    kind: 'none',
    question: '혹시?',
    options: [opt('다 먹었어', 1, 1), opt('반', 0.5, 0.5)],
  }));
  assert.ok(fb);
  assert.equal(fb.check.kind, 'none');
  assert.deepEqual(fb.check.options, []);
  assert.equal(fb.check.question, '');
});

Deno.test('유효 옵션 2개 미만이면 none 으로 내림', () => {
  const fb = postProcessFeedback(base({
    kind: 'soup',
    question: '국물은 얼마나 마셨어?',
    options: [opt('다 마셨어', 1, 1), { label: '', kcal_factor: 0.5, sodium_factor: 0.5 }],
  }));
  assert.ok(fb);
  assert.equal(fb.check.kind, 'none');
  assert.deepEqual(fb.check.options, []);
});

Deno.test('같은 label 중복은 하나만', () => {
  const fb = postProcessFeedback(base({
    kind: 'rice',
    question: '밥은 얼마나 먹었어?',
    options: [opt('다 먹었어', 1, 1), opt('다 먹었어', 0.5, 0.5), opt('반 공기', 0.6, 1)],
  }));
  assert.ok(fb);
  assert.deepEqual(fb.check.options.map((o) => o.label), ['다 먹었어', '반 공기']);
});

Deno.test('sodium_factor 없거나 숫자 아니면 1.0, kcal_factor 숫자 아니면 옵션 제외', () => {
  const fb = postProcessFeedback(base({
    kind: 'sauce',
    question: '소스는 얼마나 찍어 먹었어?',
    options: [
      { label: '다 먹었어', kcal_factor: 1 },
      { label: '조금', kcal_factor: 0.8, sodium_factor: 'x' },
      { label: '이상', kcal_factor: 'x', sodium_factor: 0.5 },
    ],
  }));
  assert.ok(fb);
  assert.equal(fb.check.options.length, 2);
  assert.equal(fb.check.options[0].sodium_factor, 1);
  assert.equal(fb.check.options[1].sodium_factor, 1);
});

Deno.test('headline 금지어 → 기본 문구', () => {
  const fb = postProcessFeedback({
    ...base({ kind: 'none', question: '', options: [] }),
    headline: '오늘 식단 망쳤다',
  });
  assert.ok(fb);
  assert.equal(fb.headline, FEEDBACK_FALLBACK_HEADLINE);
  assert.equal(FEEDBACK_FALLBACK_HEADLINE, '오늘도 잘 챙겼어');
});

Deno.test("headline '나쁜 음식' 도 금지어", () => {
  const fb = postProcessFeedback({
    ...base({ kind: 'none', question: '', options: [] }),
    headline: '나쁜 음식은 아니야',
  });
  assert.ok(fb);
  assert.equal(fb.headline, '오늘도 잘 챙겼어');
});

Deno.test('good / next 금지어 → 중립 문구 (금지어 없음)', () => {
  const fb = postProcessFeedback({
    ...base({ kind: 'none', question: '', options: [] }),
    good: '어제 실패했지만 오늘은 괜찮아.',
    next: '다음엔 채소를 꼭 더해주세요.',
  });
  assert.ok(fb);
  for (const s of [fb.good, fb.next]) {
    for (const w of ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식']) {
      assert.ok(!s.includes(w), `${s} 에 ${w}`);
    }
  }
  assert.notEqual(fb.good, '어제 실패했지만 오늘은 괜찮아.');
  assert.notEqual(fb.next, '다음엔 채소를 꼭 더해주세요.');
});

Deno.test('question 에 금지어 → check none', () => {
  const fb = postProcessFeedback(base({
    kind: 'rice',
    question: '밥 양을 선택해주세요',
    options: [opt('다 먹었어', 1, 1), opt('반', 0.5, 0.5)],
  }));
  assert.ok(fb);
  assert.equal(fb.check.kind, 'none');
  assert.deepEqual(fb.check.options, []);
});

Deno.test('옵션 label 금지어 → 그 옵션 제외', () => {
  const fb = postProcessFeedback(base({
    kind: 'rice',
    question: '밥은 얼마나 먹었어?',
    options: [opt('다 먹었어', 1, 1), opt('반 공기', 0.6, 1), opt('조절 실패', 1.3, 1.3)],
  }));
  assert.ok(fb);
  assert.deepEqual(fb.check.options.map((o) => o.label), ['다 먹었어', '반 공기']);
});

Deno.test('headline 20자 초과 → 코드포인트 기준 20자', () => {
  const long = '🍚'.repeat(5) + '가'.repeat(30);
  const fb = postProcessFeedback({
    ...base({ kind: 'none', question: '', options: [] }),
    headline: long,
  });
  assert.ok(fb);
  assert.equal([...fb.headline].length, 20);
  assert.ok(fb.headline.startsWith('🍚🍚🍚🍚🍚'));
});

Deno.test('구조 깨짐 → null', () => {
  assert.equal(postProcessFeedback(null), null);
  assert.equal(postProcessFeedback(undefined), null);
  assert.equal(postProcessFeedback('feedback'), null);
  assert.equal(postProcessFeedback([]), null);
  assert.equal(postProcessFeedback({ headline: 3, good: 'a', next: 'b' }), null);
  assert.equal(postProcessFeedback({ headline: 'a', good: '', next: 'b' }), null);
  assert.equal(postProcessFeedback({ headline: 'a', good: 'b' }), null);
});

Deno.test('check 가 깨져도 피드백은 살리고 none', () => {
  for (const check of [undefined, null, 'x', { kind: 'weird', question: 'q', options: [] }, { kind: 'rice' }]) {
    const fb = postProcessFeedback(base(check));
    assert.ok(fb);
    assert.deepEqual(fb.check, { kind: 'none', question: '', options: [] });
  }
});

Deno.test('answered 는 절대 내보내지 않음', () => {
  const fb = postProcessFeedback(base({
    kind: 'rice',
    question: '밥은 얼마나 먹었어?',
    options: [opt('다 먹었어', 1, 1), opt('반', 0.5, 0.5)],
    answered: '반',
  }));
  assert.ok(fb);
  assert.ok(!('answered' in fb.check));
});

Deno.test('앞뒤 공백 정리', () => {
  const fb = postProcessFeedback({
    headline: '  든든한 한 끼  ',
    good: ' 좋아. ',
    next: ' 물 한 컵 더하자. ',
    check: { kind: 'none', question: '', options: [] },
  });
  assert.ok(fb);
  assert.equal(fb.headline, '든든한 한 끼');
  assert.equal(fb.good, '좋아.');
  assert.equal(fb.next, '물 한 컵 더하자.');
});

// ── 사용자 컨텍스트 (순수 함수) ─────────────────────────────────────

Deno.test("effectiveGoalMode: lose + 목표 > 현재 → gain", () => {
  assert.equal(effectiveGoalMode('lose', 60, 55), 'gain');
  assert.equal(effectiveGoalMode('lose', 60, 70), 'lose');
  assert.equal(effectiveGoalMode('maintain', 60, 55), 'maintain');
  assert.equal(effectiveGoalMode('gain', 60, 70), 'gain');
  assert.equal(effectiveGoalMode(null, null, null), 'lose');
  assert.equal(effectiveGoalMode('weird', 60, 55), 'gain');
});

Deno.test('localDayStartUtc: KST 자정 직후·직전', () => {
  // 2026-11-16 00:10 KST = 2026-11-15T15:10Z → 그날 시작 2026-11-15T15:00Z
  assert.equal(localDayStartUtc('2026-11-15T15:10:00Z', 540), '2026-11-15T15:00:00.000Z');
  // 2026-11-15 23:50 KST = 2026-11-15T14:50Z → 2026-11-14T15:00Z
  assert.equal(localDayStartUtc('2026-11-15T14:50:00Z', 540), '2026-11-14T15:00:00.000Z');
  assert.equal(localDayStartUtc('2026-11-15T14:50:00Z', 0), '2026-11-15T00:00:00.000Z');
});

Deno.test('buildUserContextLine', () => {
  const line = buildUserContextLine({
    dailyKcalTarget: 1800,
    priorKcalToday: 640,
    mode: 'lose',
    glp1: true,
    sex: 'female',
    sharedWithCount: 2,
  });
  assert.ok(line.includes('1800'));
  assert.ok(line.includes('640'));
  assert.ok(line.includes('GLP-1 사용 중'));
  assert.ok(line.includes('2명'));
  const none = buildUserContextLine({
    dailyKcalTarget: null,
    priorKcalToday: null,
    mode: 'maintain',
    glp1: false,
    sex: null,
    sharedWithCount: 1,
  });
  assert.ok(none.includes('목표 미설정'));
  assert.ok(!none.includes('GLP-1 사용 중'));
  assert.ok(!none.includes('명이 나눠'));
});
