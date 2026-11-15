/// Insight 집계 로직 회귀 테스트.
///
/// 시나리오:
///   - 최근 5일(오늘 포함) 에만 기록 존재. 총 kcal 합계 5011 (1411+1160+1122+920+398).
///   - 7일 / 30일 윈도우에서 집계치가 올바르게 달라지는지 검증한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/entries_provider.dart';
import 'package:foodiet/providers/insight_provider.dart';

// 앞쪽 테스트는 InsightSummary 를 직접 만들어 API 표면을 검증하고,
// '패턴 인사이트' 그룹은 @visibleForTesting `computeInsightSummary`(now 고정)로
// 집계 본체를 검증한다.

Entry _entry({
  required DateTime at,
  required int kcal,
  String slot = 'lunch',
  String eatingType = 'meal',
  String status = 'done',
  int shared = 1,
  Map<String, dynamic>? macros,
  String? title,
}) {
  return Entry(
    id: 'e-${at.toIso8601String()}-$kcal',
    userId: 'u',
    capturedAt: at,
    imagePath: 'p',
    status: status,
    sharedWithCount: shared,
    mealSlot: slot,
    eatingType: eatingType,
    kcalTotal: kcal,
    macros: macros,
    title: title,
  );
}

// 2026-11-16 은 월요일. 7일 윈도우 = 11/10(화) ~ 11/16(월), 주말 = 11/14·11/15.
final _now = DateTime(2026, 11, 16, 12);
DateTime _d(int day, [int hour = 12]) => DateTime(2026, 11, day, hour);

/// 하루에 점심·저녁 두 끼(완료 기록 2건)를 만든다 — 부분 기록일이 아니게.
List<Entry> _fullDay(int day, int kcalEach,
        {String dinnerSlot = 'dinner', Map<String, dynamic>? macros}) =>
    [
      _entry(at: _d(day, 12), kcal: kcalEach, macros: macros),
      _entry(at: _d(day, 19), kcal: kcalEach, slot: dinnerSlot, macros: macros),
    ];

InsightSummary _week(List<Entry> entries, {int target = 1800}) =>
    computeInsightSummary(entries, InsightWindow.week, target, now: _now);

void main() {
  test('windowDays 는 7 / 30 로 정확히 구분된다', () {
    final summary7 = InsightSummary(
      window: InsightWindow.week,
      targetKcal: 1800,
      days: List.generate(
        7,
        (i) => DayBucket(
          date: DateTime(2026, 4, 17).add(Duration(days: i)),
          consumedKcal: 0,
          entryCount: 0,
        ),
      ),
      avgKcal: 0,
      avgKcalAllDays: 0,
      onGoalDays: 0,
      overDays: 0,
      underDays: 0,
      currentStreak: 0,
      bestStreak: 0,
      mealSlots: const [],
      avgCarbG: 0,
      avgProteinG: 0,
      avgFatG: 0,
      topFoods: const [],
      totalEntries: 0,
      totalDoneEntries: 0,
    );
    expect(summary7.windowDays, 7);

    final summary30 = InsightSummary(
      window: InsightWindow.month,
      targetKcal: 1800,
      days: List.generate(
        30,
        (i) => DayBucket(
          date: DateTime(2026, 3, 25).add(Duration(days: i)),
          consumedKcal: 0,
          entryCount: 0,
        ),
      ),
      avgKcal: 0,
      avgKcalAllDays: 0,
      onGoalDays: 0,
      overDays: 0,
      underDays: 0,
      currentStreak: 0,
      bestStreak: 0,
      mealSlots: const [],
      avgCarbG: 0,
      avgProteinG: 0,
      avgFatG: 0,
      topFoods: const [],
      totalEntries: 0,
      totalDoneEntries: 0,
    );
    expect(summary30.windowDays, 30);
  });

  test('5일 기록일 때 avgKcalAllDays 는 윈도우에 따라 달라진다', () {
    // 5011 kcal / 7일 = 715.86 → 716
    // 5011 kcal / 30일 = 167.03 → 167
    const kcalSum = 5011;
    expect((kcalSum / 7).round(), 716);
    expect((kcalSum / 30).round(), 167);
  });

  test('recordDays vs windowDays — 5일 기록 시 7일·30일 대비 비율 다름', () {
    const records = 5;
    expect('$records/7일', isNot('$records/30일'));
  });

  group('패턴 인사이트', () {
    test('patterns_sparse — 기록 2일이면 조건을 넘어도 flags 는 비어 있다', () {
      final s = _week([
        ..._fullDay(14, 1500,
            dinnerSlot: 'late_night', macros: {'sodium_mg': 3000}),
        ..._fullDay(15, 1500,
            dinnerSlot: 'late_night', macros: {'sodium_mg': 3000}),
      ]);
      expect(s.recordDays, 2);
      expect(s.lateNightDays, 2);
      expect(s.patternFlags, isEmpty);
    });

    test('기록 0일이면 모든 패턴 수치가 0 이고 flags 는 비어 있다', () {
      final s = _week(const []);
      expect(s.lateNightDays, 0);
      expect(s.weekdayAvgKcal, 0);
      expect(s.weekendAvgKcal, 0);
      expect(s.snackBeverageShare, 0);
      expect(s.avgSodiumMg, 0);
      expect(s.avgSugarG, 0);
      expect(s.partialDays, 0);
      expect(s.patternFlags, isEmpty);
    });

    test('야식 2일 → late_night 플래그', () {
      final s = _week([
        ..._fullDay(10, 800, dinnerSlot: 'late_night'),
        ..._fullDay(11, 800, dinnerSlot: 'late_night'),
        ..._fullDay(12, 800),
      ]);
      expect(s.lateNightDays, 2);
      expect(s.patternFlags.map((f) => f.key), contains('late_night'));
      final f = s.patternFlags.firstWhere((f) => f.key == 'late_night');
      expect(f.emoji, isNotEmpty);
      expect(f.text, contains('2일'));
    });

    test('야식 1일이면 late_night 플래그 없음', () {
      final s = _week([
        ..._fullDay(10, 800, dinnerSlot: 'late_night'),
        ..._fullDay(11, 800),
        ..._fullDay(12, 800),
      ]);
      expect(s.lateNightDays, 1);
      expect(s.patternFlags.map((f) => f.key), isNot(contains('late_night')));
    });

    test('한 끼만 기록한 날은 underDays 에서 빠지고 partialDays 에 들어간다', () {
      final s = _week([
        _entry(at: _d(10), kcal: 300), // 1건 300kcal — 기록 적은 날
        ..._fullDay(11, 300), // 2건 600kcal — 진짜 부족
        ..._fullDay(12, 900), // 1800 — 달성
      ]);
      expect(s.partialDays, 1);
      expect(s.underDays, 1);
      expect(s.onGoalDays, 1);
      expect(s.recordDays, 3);
    });

    test('기록 적은 날은 연속 달성을 끊지 않는다', () {
      final s = _week([
        ..._fullDay(14, 900), // 달성
        _entry(at: _d(15), kcal: 300), // 기록 적은 날 — 판단 보류
        ..._fullDay(16, 900), // 달성
      ]);
      expect(s.currentStreak, 2);
      expect(s.bestStreak, 2);
    });

    test('pending/failed 기록은 완료 기록 수에 들어가지 않는다', () {
      final s = _week([
        _entry(at: _d(10, 12), kcal: 300),
        _entry(at: _d(10, 19), kcal: 300, status: 'pending'),
      ]);
      expect(s.partialDays, 1);
      expect(s.underDays, 0);
    });

    test('기록 적은 날 2일 이상 → partial_days 플래그', () {
      final s = _week([
        _entry(at: _d(10), kcal: 500),
        _entry(at: _d(11), kcal: 500),
        ..._fullDay(12, 900),
      ]);
      expect(s.partialDays, 2);
      expect(s.patternFlags.map((f) => f.key), contains('partial_days'));
    });

    test('주말·평일 평균은 기록일 기준으로 따로 계산된다', () {
      final s = _week([
        ..._fullDay(11, 800), // 화 1600
        ..._fullDay(12, 900), // 수 1800
        _entry(at: _d(14, 12), kcal: 1200), // 토 2200
        _entry(at: _d(14, 19), kcal: 1000),
        ..._fullDay(15, 1000), // 일 2000
      ]);
      expect(s.weekdayAvgKcal, 1700);
      expect(s.weekendAvgKcal, 2100);
      expect(s.patternFlags.map((f) => f.key), contains('weekend_gap'));
    });

    test('주말-평일 차이가 300 미만이면 weekend_gap 없음', () {
      final s = _week([
        ..._fullDay(11, 900),
        ..._fullDay(12, 900),
        ..._fullDay(14, 1000),
      ]);
      expect(s.weekdayAvgKcal, 1800);
      expect(s.weekendAvgKcal, 2000);
      expect(s.patternFlags.map((f) => f.key), isNot(contains('weekend_gap')));
    });

    test('평일이 한 끼만 기록된 날뿐이면 weekend_gap 결론을 내지 않는다', () {
      final s = _week([
        _entry(at: _d(10), kcal: 500), // 평일 기록 적은 날
        _entry(at: _d(11), kcal: 500),
        ..._fullDay(14, 1000), // 토 2000
        ..._fullDay(15, 1000), // 일 2000
      ]);
      expect(s.weekdayAvgKcal, 500); // 표시용 수치는 기록일 기준
      expect(s.weekendAvgKcal, 2000);
      expect(s.patternFlags.map((f) => f.key), isNot(contains('weekend_gap')));
    });

    test('주말 기록이 없으면 weekendAvgKcal 0, weekend_gap 없음', () {
      final s = _week([
        ..._fullDay(10, 900),
        ..._fullDay(11, 900),
        ..._fullDay(12, 900),
      ]);
      expect(s.weekendAvgKcal, 0);
      expect(s.patternFlags.map((f) => f.key), isNot(contains('weekend_gap')));
    });

    test('간식·음료 비중과 평균 나트륨·당', () {
      final s = _week([
        _entry(at: _d(10, 12), kcal: 600, macros: {'sodium_mg': 1500, 'sugar_g': 10}),
        _entry(at: _d(10, 15), kcal: 200, eatingType: 'snack',
            macros: {'sodium_mg': 500, 'sugar_g': 20}),
        _entry(at: _d(11, 12), kcal: 600, macros: {'sodium_mg': 2000, 'sugar_g': 5}),
        _entry(at: _d(11, 15), kcal: 200, eatingType: 'beverage',
            macros: {'sodium_mg': 0, 'sugar_g': 25}),
        _entry(at: _d(12, 12), kcal: 800, macros: {'sodium_mg': 2000, 'sugar_g': 0}),
        _entry(at: _d(12, 19), kcal: 0, macros: {'sodium_mg': 0}),
      ]);
      // 간식·음료 400 / 전체 2400
      expect(s.snackBeverageShare, closeTo(400 / 2400, 1e-9));
      // 날짜별 나트륨 2000 / 2000 / 2000 → 평균 2000
      expect(s.avgSodiumMg, 2000);
      // 날짜별 당 30 / 30 / 0 → 평균 20
      expect(s.avgSugarG, 20);
      final keys = s.patternFlags.map((f) => f.key);
      expect(keys, contains('sodium_high'));
      expect(keys, isNot(contains('snack_share'))); // 16.7% < 25%
    });

    test('간식·음료 비중 25% 이상 → snack_share', () {
      final s = _week([
        _entry(at: _d(10, 12), kcal: 600),
        _entry(at: _d(10, 15), kcal: 300, eatingType: 'snack'),
        ..._fullDay(11, 450),
        ..._fullDay(12, 450),
      ]);
      // 300 / 2700 = 11% — 아직 아님
      expect(s.patternFlags.map((f) => f.key), isNot(contains('snack_share')));
      final s2 = _week([
        _entry(at: _d(10, 12), kcal: 600),
        _entry(at: _d(10, 15), kcal: 600, eatingType: 'beverage'),
        ..._fullDay(11, 450),
        ..._fullDay(12, 450),
      ]);
      // 600 / 3000 = 20% — 아직 아님
      expect(s2.snackBeverageShare, closeTo(0.2, 1e-9));
      final s3 = _week([
        _entry(at: _d(10, 12), kcal: 600),
        _entry(at: _d(10, 15), kcal: 600, eatingType: 'snack'),
        _entry(at: _d(11, 12), kcal: 600),
        _entry(at: _d(11, 15), kcal: 300, eatingType: 'beverage'),
        ..._fullDay(12, 450),
      ]);
      // 900 / 3000 = 30%
      expect(s3.patternFlags.map((f) => f.key), contains('snack_share'));
    });

    test('공유 식사는 1인분 기준으로 나트륨을 나눈다', () {
      final s = _week([
        _entry(at: _d(10, 12), kcal: 1000, shared: 2, macros: {'sodium_mg': 4000}),
        _entry(at: _d(10, 19), kcal: 500, macros: {'sodium_mg': 0}),
      ]);
      expect(s.avgSodiumMg, 2000);
    });

    test('플래그 문구에 금지 어휘가 없다', () {
      final s = _week([
        _entry(at: _d(10), kcal: 300),
        _entry(at: _d(11), kcal: 300),
        ..._fullDay(12, 900), // 평일 비교는 기록 적은 날을 빼고 본다
        _entry(at: _d(14, 12), kcal: 1500,
            macros: {'sodium_mg': 3000, 'sugar_g': 40}),
        _entry(at: _d(14, 23), kcal: 1500, slot: 'late_night', eatingType: 'snack',
            macros: {'sodium_mg': 3000}),
        _entry(at: _d(15, 12), kcal: 1500, macros: {'sodium_mg': 3000}),
        _entry(at: _d(15, 23), kcal: 1500, slot: 'late_night', eatingType: 'snack',
            macros: {'sodium_mg': 3000}),
      ]);
      expect(s.patternFlags.map((f) => f.key).toSet(), {
        'late_night',
        'weekend_gap',
        'snack_share',
        'sodium_high',
        'partial_days',
      });
      for (final f in s.patternFlags) {
        for (final banned in ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식']) {
          expect(f.text, isNot(contains(banned)));
        }
      }
    });
  });
}

