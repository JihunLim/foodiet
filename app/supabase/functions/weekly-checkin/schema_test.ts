// weekly-checkin 순수 로직 테스트 (네트워크 없음).
//   deno test --node-modules-dir=none --allow-read \
//     app/supabase/functions/weekly-checkin/schema_test.ts

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  BANNED,
  DEFAULT_EXPERIMENTS,
  insufficientBody,
  MIN_DAYS,
  postProcessReport,
  safePrevExperiment,
  summarizeWeek,
  weekRangeUtc,
  weekStartFor,
} from './schema.ts';

const KST = 540;
const ms = (iso: string) => new Date(iso).getTime();

// ── weekStartFor ──────────────────────────────────────────────────────
Deno.test('일요일 23:00 KST → 이번 주 월요일', () => {
  // 2026-11-15(일) 23:00 KST = 14:00Z
  assertEquals(weekStartFor(ms('2026-11-15T14:00:00Z'), KST), '2026-11-09');
});

Deno.test('월요일 09:00 KST → 지난 주 월요일', () => {
  // 2026-11-16(월) 09:00 KST = 00:00Z
  assertEquals(weekStartFor(ms('2026-11-16T00:00:00Z'), KST), '2026-11-09');
});

Deno.test('일요일 16:59 KST → 지난 주 월요일', () => {
  assertEquals(weekStartFor(ms('2026-11-15T07:59:00Z'), KST), '2026-11-02');
});

Deno.test('일요일 17:00 KST → 이번 주 월요일', () => {
  assertEquals(weekStartFor(ms('2026-11-15T08:00:00Z'), KST), '2026-11-09');
});

Deno.test('UTC 기준으론 토요일이지만 로컬은 일요일 18시', () => {
  // 2026-11-15(일) 18:00 KST = 2026-11-15T09:00Z — UTC 도 일요일이지만,
  // 2026-11-14(토)T23:30Z = 11-15(일) 08:30 KST → 아직 17시 전 → 지난 주.
  assertEquals(weekStartFor(ms('2026-11-14T23:30:00Z'), KST), '2026-11-02');
});

Deno.test('weekRangeUtc: 로컬 월 00:00 ~ 다음 월 00:00', () => {
  const r = weekRangeUtc('2026-11-09', KST);
  assertEquals(r.fromIso, '2026-11-08T15:00:00.000Z');
  assertEquals(r.toIso, '2026-11-15T15:00:00.000Z');
});

// ── summarizeWeek ─────────────────────────────────────────────────────
const e = (
  capturedAt: string,
  kcal: number,
  extra: Record<string, unknown> = {},
) => ({
  captured_at: capturedAt,
  kcal_total: kcal,
  shared_with_count: 1,
  meal_slot: 'lunch',
  eating_type: 'meal',
  macros: { protein_g: 20, sodium_mg: 1000 },
  ...extra,
});

Deno.test('summarizeWeek: 로컬 날짜 기준 기록일·공유 식사 1인분 환산', () => {
  const s = summarizeWeek(
    [
      // 11-10(화) 00:30 KST — UTC 로는 11-09 → 로컬 화요일로 들어가야 한다.
      e('2026-11-09T15:30:00Z', 400, { meal_slot: 'late_night' }),
      e('2026-11-10T03:00:00Z', 800, { shared_with_count: 2 }), // 11-10 12:00 → 400
      e('2026-11-11T03:00:00Z', 600),
      // 주 범위 밖(다음 주 월요일 09:00 KST) — 무시
      e('2026-11-16T00:00:00Z', 9999),
    ],
    KST,
    '2026-11-09',
  );
  assertEquals(s.daysLogged, 2);
  assertEquals(s.perDay.map((d) => d.date), ['2026-11-10', '2026-11-11']);
  assertEquals(s.perDay[0].kcal, 800);
  assertEquals(s.perDay[0].count, 2);
  assertEquals(s.avgKcal, 700);
  assertEquals(s.lateNightDays, 1);
  assertEquals(s.partialDays, 1); // 11-11 은 1건뿐
});

Deno.test('summarizeWeek: 주말/평일 평균, 간식·음료 비중', () => {
  const s = summarizeWeek(
    [
      e('2026-11-10T03:00:00Z', 1500), // 화
      e('2026-11-11T03:00:00Z', 1500), // 수
      e('2026-11-14T03:00:00Z', 2000), // 토
      e('2026-11-14T06:00:00Z', 500, { eating_type: 'snack' }), // 토
    ],
    KST,
    '2026-11-09',
  );
  assertEquals(s.weekdayAvgKcal, 1500);
  assertEquals(s.weekendAvgKcal, 2500);
  assertEquals(Math.round(s.snackBeverageShare * 100), 9); // 500 / 5500
});

Deno.test('summarizeWeek: 기록 없음 → 0 으로 안전', () => {
  const s = summarizeWeek([], KST, '2026-11-09');
  assertEquals(s.daysLogged, 0);
  assertEquals(s.avgKcal, 0);
  assertEquals(s.weekendAvgKcal, 0);
  assert(s.daysLogged < MIN_DAYS);
});

Deno.test('insufficientBody: LLM 없이 결정적 문구', () => {
  const b = insufficientBody('2026-11-09', 1);
  assertEquals(b.insufficient, true);
  assertEquals(b.headline, '기록이 쌓이면 같이 돌아보자');
  assertEquals(b.week_start, '2026-11-09');
});

// ── postProcessReport ─────────────────────────────────────────────────
const good = {
  emoji: '🌿',
  headline: '꾸준히 기록한 한 주',
  wins: ['5일 기록했어', '단백질을 잘 챙겼어', '세 번째는 잘려야 해'],
  pattern: '주말 저녁이 평일보다 조금 컸어.',
  experiments: [
    { if_then: '토요일 저녁엔 국물을 반만 먹기', why: '나트륨을 줄일 수 있어.' },
    { if_then: '배고프면 물 한 잔 먼저', why: '갈증과 허기를 구분해봐.' },
    { if_then: '점심에 단백질 반찬 하나 더', why: '오후 간식이 줄 수 있어.' },
    { if_then: '네 번째', why: '잘려야 해' },
  ],
  note: '다음 주도 같이 가보자.',
};

Deno.test('postProcess: wins ≤2, experiments 정확히 3', () => {
  const r = postProcessReport(good);
  assertEquals(r.wins.length, 2);
  assertEquals(r.experiments.length, 3);
  assertEquals(r.headline, '꾸준히 기록한 한 주');
});

Deno.test('postProcess: 실험이 부족하면 기본 실험으로 3개 채움', () => {
  const r = postProcessReport({ ...good, experiments: [good.experiments[0]] });
  assertEquals(r.experiments.length, 3);
  assertEquals(r.experiments[1], DEFAULT_EXPERIMENTS[0]);
});

Deno.test('postProcess: wins 비면 기본 1개', () => {
  const r = postProcessReport({ ...good, wins: [] });
  assertEquals(r.wins.length, 1);
});

Deno.test('postProcess: 금지어·효과 보장 문구 걸러냄', () => {
  const r = postProcessReport({
    ...good,
    headline: '주말에 망쳤다',
    pattern: '이대로면 한 달에 3kg 감량 가능!',
    wins: ['어제 실패했지만 괜찮아', '물을 잘 마셨어'],
    experiments: [
      { if_then: '저녁 굶기', why: '빨리 빠져' },
      ...good.experiments.slice(1, 3),
    ],
  });
  const all = JSON.stringify(r);
  for (const b of BANNED) assert(!all.includes(b), `금지어 남음: ${b}`);
  assert(!/\d\s*kg\s*감량/.test(all), '효과 보장 문구 남음');
  assert(!all.includes('굶'), '굶기 권유 남음');
  assertEquals(r.wins, ['물을 잘 마셨어']);
  assertEquals(r.experiments.length, 3);
});

Deno.test('postProcess: headline 20자 초과는 자름', () => {
  const r = postProcessReport({ ...good, headline: '가'.repeat(30) });
  assert([...r.headline].length <= 20);
});

Deno.test('postProcess: 잘못된 모양이어도 예외 없이 기본값', () => {
  const r = postProcessReport({ headline: 3, wins: 'x', experiments: null });
  assertEquals(r.experiments.length, 3);
  assertEquals(r.wins.length, 1);
  assert(r.headline.length > 0);
  assert(r.emoji.length > 0);
});

Deno.test('postProcess: 이모지 자리에 글자가 오면 기본 이모지', () => {
  assertEquals(postProcessReport({ ...good, emoji: 'good' }).emoji, '🌿');
  assertEquals(postProcessReport({ ...good, emoji: '좋아' }).emoji, '🌿');
  assertEquals(postProcessReport({ ...good, emoji: '🔥' }).emoji, '🔥');
});

Deno.test('postProcess: 끼니 거르기 권유는 버리고, 정상 실험은 남김', () => {
  const r = postProcessReport({
    ...good,
    experiments: [
      { if_then: '저녁 건너뛰기', why: '가볍게' },
      { if_then: '아침 거르기', why: '가볍게' },
      { if_then: '점심 생략하기', why: '가볍게' },
      { if_then: '저녁 먹고 간식 안 먹기', why: '야식을 줄여봐.' },
      { if_then: '저녁에 밥 반 공기 빼기', why: '탄수 조절.' },
      { if_then: '야식 건너뛰고 따뜻한 차 마시기', why: '대체 습관.' },
    ],
  });
  assertEquals(r.experiments.map((x) => x.if_then), [
    '저녁 먹고 간식 안 먹기',
    '저녁에 밥 반 공기 빼기',
    '야식 건너뛰고 따뜻한 차 마시기',
  ]);
});

Deno.test('safePrevExperiment: 위험 문구는 null, 길면 120자', () => {
  assertEquals(safePrevExperiment('저녁 건너뛰기'), null);
  assertEquals(safePrevExperiment('주말엔 굶기'), null);
  assertEquals(safePrevExperiment(null), null);
  assertEquals(safePrevExperiment('  물 먼저 마시기 '), '물 먼저 마시기');
  assertEquals([...(safePrevExperiment('가'.repeat(200)) ?? '')].length, 120);
});
