/// 추세 체중 · 스파이크 · 정체기 · 목표 재계산 — 순수 로직.
///
/// 하루하루 체중은 수분·염분·변비 등으로 ±1kg 쯤 흔들린다. 그래서 체중 탭은
/// 날마다 찍은 값보다 지수이동평균(EMA, α=0.25 ≈ 7일) "추세 체중" 을 기준으로
/// 안내한다.
///   - 스파이크: 오늘 값이 어제까지의 추세보다 1.0kg 이상 높음 → "수분일 가능성" 안내.
///   - 정체기: 최근 14일 추세 변화가 0.3kg 미만 (점 5개 이상, 기록 14일 이상) → 점검 목록.
///   - 재계산: 목표 kcal 을 계산할 때 쓴 체중과 지금 추세가 2kg 이상 벌어짐.
///
/// UI·DB 의존이 없어 단위 테스트로 고정한다 (test/weight_trend_test.dart).
library;

import '../providers/profile_provider.dart';
import 'kcal_calc.dart';

/// EMA 평활 계수. 0.25 ≈ 최근 7일 가중.
const double kTrendAlpha = 0.25;

/// 스파이크 판정 임계(kg).
const double kSpikeThresholdKg = 1.0;

/// 정체기 판정 — 창 길이(일), 최소 점 수, 추세 변화 상한(kg).
const int kPlateauWindowDays = 14;
const int kPlateauMinPoints = 5;
const double kPlateauMaxDeltaKg = 0.3;

/// 목표 재계산 제안 임계(kg).
const double kRecalcThresholdKg = 2.0;

/// 부동소수 경계(68.1 → 70.1 이 1.9999… 가 되는 것) 보정.
const double _eps = 1e-6;

class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.kg,
    required this.trendKg,
  });

  /// 로컬 날짜(시각 0시).
  final DateTime date;

  /// 그날 마지막으로 찍은 체중.
  final double kg;

  /// 그날까지의 EMA 추세 체중.
  final double trendKg;

  @override
  String toString() => 'TrendPoint($date, $kg, $trendKg)';
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// 로컬 날짜별 마지막 값 → 날짜 오름차순 → EMA(α=0.25, 첫 값은 원값).
List<TrendPoint> trendSeries(List<({DateTime at, double kg})> logs) {
  if (logs.isEmpty) return const [];
  final sorted = [...logs]..sort((a, b) => a.at.compareTo(b.at));
  final byDay = <DateTime, double>{};
  for (final l in sorted) {
    byDay[_day(l.at)] = l.kg; // 정렬돼 있으니 나중 값이 덮어씀 = 마지막 값.
  }
  final days = byDay.keys.toList()..sort();
  final out = <TrendPoint>[];
  double? trend;
  for (final d in days) {
    final kg = byDay[d]!;
    trend = trend == null ? kg : trend + kTrendAlpha * (kg - trend);
    out.add(TrendPoint(date: d, kg: kg, trendKg: trend));
  }
  return out;
}

/// 최신 값이 "직전까지의 추세" 보다 1.0kg 이상 높으면 true.
///
/// 마지막 점의 trendKg 는 이미 오늘 값을 0.25 만큼 반영하므로, 기준선은
/// 바로 앞 점의 trendKg 로 잡는다 (+1.2kg 급등이 0.9 로 희석되지 않게).
bool detectSpike(List<TrendPoint> s) {
  if (s.length < 2) return false;
  final last = s.last;
  final baseline = s[s.length - 2].trendKg;
  return last.kg - baseline >= kSpikeThresholdKg - _eps;
}

/// 최근 14일 추세가 거의 평평하면 true.
///
/// 조건 (모두 만족):
///   - 기록 기간: 시리즈 첫 점이 오늘로부터 14일 이상 전 (신규 사용자 억지 결론 방지).
///   - 창: date >= today − 14일 (오늘 포함 15일치) 안의 점이 5개 이상.
///   - 창 안 첫 점과 마지막 점의 trendKg 차이 < 0.3kg.
bool detectPlateau(List<TrendPoint> s, DateTime today) {
  if (s.isEmpty) return false;
  final t = _day(today);
  // Duration 빼기는 서머타임 경계에서 0시가 어긋나므로 달력 날짜로 계산.
  final windowStart = DateTime(t.year, t.month, t.day - kPlateauWindowDays);
  if (s.first.date.isAfter(windowStart)) return false;
  final window = s
      .where((p) => !p.date.isBefore(windowStart) && !p.date.isAfter(t))
      .toList();
  if (window.length < kPlateauMinPoints) return false;
  final delta = (window.last.trendKg - window.first.trendKg).abs();
  return delta < kPlateauMaxDeltaKg - _eps;
}

/// 목표 kcal 계산 기준 체중과 최신 추세가 2.0kg 이상 벌어졌으면 true.
bool needsRecalc(double? basisKg, double? latestTrendKg) {
  if (basisKg == null || latestTrendKg == null) return false;
  return (latestTrendKg - basisKg).abs() >= kRecalcThresholdKg - _eps;
}

/// 서버와 같은 규칙의 실효 목표 모드 — 'lose' 인데 목표가 현재보다 무거우면 'gain'.
String effectiveGoalMode(String goalMode,
    {required double? goalKg, required double? currentKg}) {
  if (goalMode == 'maintain') return 'maintain';
  if (goalMode == 'gain') return 'gain';
  if (goalKg != null && currentKg != null && goalKg > currentKg) return 'gain';
  return 'lose';
}

class TargetUpdate {
  const TargetUpdate({
    required this.dailyKcal,
    required this.mode,
    required this.basisKg,
  });

  /// 새 일일 목표 kcal (하한 1200/1500 적용 후).
  final int dailyKcal;

  /// 저장할 profiles.goal_mode.
  final String mode;

  /// 저장할 profiles.target_weight_basis_kg / weight_kg (0.1 반올림).
  final double basisKg;
}

/// [weightKg] 기준으로 일일 목표를 다시 계산.
///
/// - maintain: 적자 0 (goalWeightKg 를 넘기지 않음) → TDEE, 하한 적용.
/// - 그 외: 프로필의 목표 체중·기한으로 기존 [computeKcalTarget] 그대로.
/// 키·활동량이 없으면 계산할 수 없어 null.
TargetUpdate? recalcTarget(
  AppProfile p, {
  required double weightKg,
  required String mode,
  DateTime? now,
}) {
  final h = p.heightCm;
  final act = p.activityLevel;
  if (h == null || act == null) return null;
  final at = now ?? DateTime.now();
  int? age;
  final b = p.birthDate;
  if (b != null) {
    age = at.year - b.year;
    if (at.month < b.month || (at.month == b.month && at.day < b.day)) {
      age -= 1;
    }
    if (age < 0) age = 0;
  }
  final basis = (weightKg * 10).round() / 10;
  final r = computeKcalTarget(KcalTargetInput(
    sex: p.sex,
    ageYears: age,
    heightCm: h,
    weightKg: basis,
    activityLevel: act,
    goalWeightKg: mode == 'maintain' ? null : p.goalWeightKg,
    // 지난 기한은 computeKcalTarget 이 7일로 보고 최대 적자를 걸어버리므로,
    // 재계산에서는 기한 없음(주 0.5kg 가정)으로 취급한다.
    goalDeadline: mode == 'maintain' ||
            p.goalDeadline == null ||
            p.goalDeadline!.isBefore(DateTime(at.year, at.month, at.day))
        ? null
        : p.goalDeadline,
    now: at,
  ));
  return TargetUpdate(dailyKcal: r.dailyKcalTarget, mode: mode, basisKg: basis);
}
