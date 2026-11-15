/// 추세 체중(EMA)·스파이크·정체기·목표 재계산 순수 로직 테스트.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/profile_provider.dart';
import 'package:foodiet/services/kcal_calc.dart';
import 'package:foodiet/services/weight_trend.dart';

final _today = DateTime(2026, 11, 16);

/// [daysAgo] 목록에 같은 체중을 찍은 로그.
List<({DateTime at, double kg})> _flat(List<int> daysAgo, double kg) => [
      for (final d in daysAgo)
        (
          at: _today.subtract(Duration(days: d)).add(const Duration(hours: 8)),
          kg: kg
        ),
    ];

AppProfile _profile({
  Sex? sex = Sex.female,
  double? heightCm = 160,
  double? weightKg = 60,
  int? activityLevel = 2,
  double? goalWeightKg = 55,
  DateTime? goalDeadline,
  DateTime? birthDate,
}) =>
    AppProfile(
      userId: 'u',
      nickname: 't',
      locale: 'ko',
      unitEnergy: 'kcal',
      unitMass: 'kg',
      sex: sex,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      goalWeightKg: goalWeightKg,
      goalDeadline: goalDeadline,
      birthDate: birthDate ?? DateTime(1990, 1, 1),
    );

void main() {
  group('trendSeries', () {
    test('EMA 첫 값은 원값 그대로', () {
      final s = trendSeries([(at: _today, kg: 70.4)]);
      expect(s, hasLength(1));
      expect(s.first.trendKg, 70.4);
      expect(s.first.kg, 70.4);
    });

    test('α=0.25 EMA', () {
      final s = trendSeries([
        (at: _today.subtract(const Duration(days: 1)), kg: 70.0),
        (at: _today, kg: 72.0),
      ]);
      expect(s.last.trendKg, closeTo(70.5, 1e-9));
    });

    test('정렬 안 된 입력 + 같은 날 두 번 → 날짜별 마지막 값', () {
      final s = trendSeries([
        (at: DateTime(2026, 11, 16, 21), kg: 71.0), // 같은 날 늦은 값
        (at: DateTime(2026, 11, 15, 8), kg: 70.0),
        (at: DateTime(2026, 11, 16, 7), kg: 73.0), // 같은 날 이른 값
      ]);
      expect(s, hasLength(2));
      expect(s.first.date, DateTime(2026, 11, 15));
      expect(s.last.date, DateTime(2026, 11, 16));
      expect(s.last.kg, 71.0);
      expect(s.last.trendKg, closeTo(70.25, 1e-9));
    });

    test('빈 입력 → 빈 시리즈', () {
      expect(trendSeries(const []), isEmpty);
    });
  });

  group('detectSpike', () {
    test('평평하다가 +1.2 → true', () {
      final logs = [
        ..._flat([6, 5, 4, 3, 2, 1], 70.0),
        (at: _today, kg: 71.2),
      ];
      expect(detectSpike(trendSeries(logs)), isTrue);
    });

    test('+0.8 → false', () {
      final logs = [
        ..._flat([3, 2, 1], 70.0),
        (at: _today, kg: 70.8),
      ];
      expect(detectSpike(trendSeries(logs)), isFalse);
    });

    test('점 1개 → false', () {
      expect(detectSpike(trendSeries([(at: _today, kg: 80.0)])), isFalse);
    });

    test('하락은 스파이크 아님', () {
      final logs = [
        ..._flat([2, 1], 70.0),
        (at: _today, kg: 68.0),
      ];
      expect(detectSpike(trendSeries(logs)), isFalse);
    });
  });

  group('detectPlateau', () {
    test('plateau_requires_14_days — 10일치 평평 → false', () {
      final logs = _flat([9, 8, 7, 6, 5, 4, 3, 2, 1, 0], 70.0);
      expect(detectPlateau(trendSeries(logs), _today), isFalse);
    });

    test('15일 평평 6점 → true', () {
      final logs = _flat([14, 11, 8, 5, 2, 0], 70.0);
      expect(detectPlateau(trendSeries(logs), _today), isTrue);
    });

    test('15일 6점이지만 꾸준히 감소 → false', () {
      final logs = [
        (at: _today.subtract(const Duration(days: 14)), kg: 72.0),
        (at: _today.subtract(const Duration(days: 11)), kg: 71.4),
        (at: _today.subtract(const Duration(days: 8)), kg: 70.8),
        (at: _today.subtract(const Duration(days: 5)), kg: 70.2),
        (at: _today.subtract(const Duration(days: 2)), kg: 69.6),
        (at: _today, kg: 69.0),
      ];
      expect(detectPlateau(trendSeries(logs), _today), isFalse);
    });

    test('최근 14일 안 점이 5개 미만 → false', () {
      final logs = _flat([20, 14, 9, 4, 0], 70.0)
        ..removeAt(1); // 20, 9, 4, 0 — 창 안은 3개
      expect(detectPlateau(trendSeries(logs), _today), isFalse);
    });

    test('추세 변화 0.3 근처 경계 — 0.25 → true, 0.35 → false', () {
      List<({DateTime at, double kg})> drift(double total) {
        // 첫 점(−14일)부터 마지막(0일)까지 trend 가 total 만큼 움직이게
        // 마지막 점에 몰아준다: Δtrend = 0.25 × Δkg.
        return [
          ..._flat([14, 11, 8, 5, 2], 70.0),
          (at: _today, kg: 70.0 - total / 0.25),
        ];
      }

      expect(detectPlateau(trendSeries(drift(0.25)), _today), isTrue);
      expect(detectPlateau(trendSeries(drift(0.35)), _today), isFalse);
    });
  });

  group('needsRecalc', () {
    test('차이 1.9 → false, 2.0 → true (소수점 입력)', () {
      expect(needsRecalc(68.1, 70.0), isFalse);
      expect(needsRecalc(68.1, 70.1), isTrue);
      expect(needsRecalc(70.1, 68.1), isTrue);
    });

    test('하나라도 null → false', () {
      expect(needsRecalc(null, 70.0), isFalse);
      expect(needsRecalc(70.0, null), isFalse);
    });
  });

  group('recalcTarget', () {
    final now = DateTime(2026, 11, 16);

    test('maintain 목표는 여성 하한 1200 이상', () {
      // 작고 활동 적은 고령 여성 — TDEE 가 1200 아래로 떨어지는 프로필.
      final p = _profile(
        sex: Sex.female,
        heightCm: 145,
        activityLevel: 1,
        birthDate: DateTime(1950, 1, 1),
        goalWeightKg: 40,
      );
      final u = recalcTarget(p, weightKg: 42, mode: 'maintain', now: now)!;
      expect(u.dailyKcal, greaterThanOrEqualTo(1200));
      expect(u.dailyKcal, 1200);
      expect(u.mode, 'maintain');
      expect(u.basisKg, 42.0);
    });

    test('maintain 목표는 남성 하한 1500 이상', () {
      final p = _profile(
        sex: Sex.male,
        heightCm: 150,
        activityLevel: 1,
        birthDate: DateTime(1945, 1, 1),
        goalWeightKg: 40,
      );
      final u = recalcTarget(p, weightKg: 45, mode: 'maintain', now: now)!;
      expect(u.dailyKcal, 1500);
    });

    test('maintain 은 적자 0 = TDEE (하한 위일 때)', () {
      final p = _profile(goalWeightKg: 50);
      final u = recalcTarget(p, weightKg: 60, mode: 'maintain', now: now)!;
      final tdee = computeKcalTarget(const KcalTargetInput(
        sex: Sex.female,
        ageYears: 36,
        heightCm: 160,
        weightKg: 60,
        activityLevel: 2,
      )).tdee;
      expect(u.dailyKcal, tdee);
    });

    test('lose 는 기존 목표·기한으로 적자 적용, basisKg 는 0.1 반올림', () {
      final p = _profile(goalWeightKg: 55);
      final u = recalcTarget(p, weightKg: 62.37, mode: 'lose', now: now)!;
      final maintain =
          recalcTarget(p, weightKg: 62.37, mode: 'maintain', now: now)!;
      expect(u.dailyKcal, lessThan(maintain.dailyKcal));
      expect(u.dailyKcal, greaterThanOrEqualTo(1200));
      expect(u.basisKg, 62.4);
      expect(u.mode, 'lose');
    });

    test('지난 기한은 기한 없음으로 취급 (최대 적자 방지)', () {
      final past =
          _profile(goalWeightKg: 50, goalDeadline: DateTime(2026, 10, 1));
      final none = _profile(goalWeightKg: 50);
      final a = recalcTarget(past, weightKg: 60, mode: 'lose', now: now)!;
      final b = recalcTarget(none, weightKg: 60, mode: 'lose', now: now)!;
      expect(a.dailyKcal, b.dailyKcal);
    });

    test('키·활동량 없으면 null', () {
      expect(
          recalcTarget(_profile(heightCm: null),
              weightKg: 60, mode: 'lose', now: now),
          isNull);
      expect(
          recalcTarget(_profile(activityLevel: null),
              weightKg: 60, mode: 'lose', now: now),
          isNull);
    });
  });

  group('effectiveGoalMode', () {
    test('lose 인데 목표가 현재보다 무거우면 gain', () {
      expect(effectiveGoalMode('lose', goalKg: 70, currentKg: 60), 'gain');
      expect(effectiveGoalMode('lose', goalKg: 55, currentKg: 60), 'lose');
      expect(
          effectiveGoalMode('maintain', goalKg: 70, currentKg: 60), 'maintain');
      expect(effectiveGoalMode('lose', goalKg: null, currentKg: 60), 'lose');
    });
  });
}
