/// 일일 권장 섭취량(TDEE) 계산.
///
/// 기획안 §4.5 — Mifflin-St Jeor + 활동계수 + 감량/증량 적자.
/// BMR (kcal/day):
///   male   = 10*kg + 6.25*cm - 5*age + 5
///   female = 10*kg + 6.25*cm - 5*age - 161
///   ⚠️ App Store guideline 5.1.1(v) — 성별·생년월일은 선택 입력.
///   둘 중 하나라도 비어있으면 중립값으로 대체:
///     - sex 누락 → male/female 평균 (-78)
///     - age 누락 → 30 세
///   덕분에 사용자가 개인정보를 강제로 입력하지 않아도 계산은 동작한다.
/// TDEE = BMR * activity factor
///   1 (sedentary)    = 1.2
///   2 (light)        = 1.375
///   3 (moderate)     = 1.55
///   4 (active)       = 1.725
///   5 (very active)  = 1.9
///
/// 감량/증량 적자:
///   · 지방 1kg ≈ 7,700 kcal.
///   · 기한이 있으면:
///       daily_deficit = |diff_kg| × 7700 ÷ days_until_deadline
///     기한이 없으면:
///       daily_deficit = 500 (주 0.5kg 감량/증량 가정)
///   · 안전 캡: 주 1kg 초과 속도 금지 → 일 적자 최대 1000 kcal.
///   · 안전 하한: 남 1500 / 여 1200 kcal/일. (sex 미입력시 1200 — 보수적)
///
/// 출처:
///   - Mifflin MD et al. "A new predictive equation for resting energy
///     expenditure in healthy individuals." Am J Clin Nutr 1990;51(2):241-7.
///     PMID: 2305711
///   - 활동계수: Harris-Benedict / ACSM convention.
///   - 안전 하한: Academy of Nutrition and Dietetics (1200/1500 kcal/day).
library;

enum Sex { male, female }
enum KcalMode { maintain, cut, bulk }

/// sex 가 null 일 때 BMR 공식의 보정값 (-78 = (-161 + 5) / 2 의 평균).
const double _bmrNeutralOffset = -78;

/// age 가 null 일 때 기본값 (30 세 — 성인 평균).
const int _defaultAge = 30;

double _bmrOffset(Sex? sex) {
  if (sex == null) return _bmrNeutralOffset;
  return sex == Sex.male ? 5 : -161;
}

class KcalTargetInput {
  const KcalTargetInput({
    required this.sex,
    required this.ageYears,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel, // 1~5
    this.goalWeightKg,
    this.goalDeadline,
    this.now,
  });
  final Sex? sex; // 선택 입력. null 이면 중립값 사용.
  final int? ageYears; // 선택 입력. null 이면 30 으로 가정.
  final double heightCm;
  final double weightKg;
  final int activityLevel;
  final double? goalWeightKg;
  final DateTime? goalDeadline;

  /// 테스트에서 주입 가능. 기본은 DateTime.now().
  final DateTime? now;
}

class KcalTargetResult {
  const KcalTargetResult({
    required this.bmr,
    required this.tdee,
    required this.dailyKcalTarget,
    required this.mode,
    required this.weeklyChangeKg,
    required this.clampedBySafety,
    required this.usedDeadline,
  });

  final int bmr;
  final int tdee;

  /// 최종 권장 칼로리 (하한 클램프 포함).
  final int dailyKcalTarget;

  /// maintain | cut | bulk
  final KcalMode mode;

  /// 실제로 예상되는 주간 체중 변화량(kg). 음수 = 감량, 양수 = 증량.
  /// 안전 캡 또는 하한에 걸렸다면 사용자가 원래 기한에 도달하지 못할 수도.
  final double weeklyChangeKg;

  /// true = 주 1kg 초과 속도 or 일일 하한(1200/1500)에 걸려서
  /// 목표 기한보다 더 오래 걸릴 수 있음을 의미.
  final bool clampedBySafety;

  /// true = 기한 기반 계산을 사용했다. false = 기본값(±500) 사용.
  final bool usedDeadline;
}

const double kcalPerKgFat = 7700;
const double _maxDailyDeficit = 1000; // 주 1kg

/// BMR + 활동계수만 반영한 **원시** TDEE (kcal/day).
///
/// [computeKcalTarget] 는 감량/증량 적자·안전 하한(1200/1500)·주 1kg 캡을
/// 걸어 "**설정용** 권장치" 를 돌려줘. 반면 **관찰/예측** 용도로는 이 clamp
/// 들이 오히려 잘못된 답을 만들어. 예: 여성 1200 하한에 걸린 profile 의
/// tdee 를 가지고 체중 예측을 돌리면 실제 소비량보다 적게 잡혀 "살 안빠짐"
/// 처럼 보이게 된다.
///
/// 이 함수는 키·체중·활동량이 있으면 값이 나옴.
/// - 필수: heightCm, weightKg, activityLevel
/// - 선택: sex (null → 평균), birthDate (null → 30 세 가정)
int? computeTdee({
  required Sex? sex,
  required DateTime? birthDate,
  required double? heightCm,
  required double? weightKg,
  required int? activityLevel,
  DateTime? now,
}) {
  if (heightCm == null || weightKg == null || activityLevel == null) {
    return null;
  }
  int age = _defaultAge;
  if (birthDate != null) {
    final today = now ?? DateTime.now();
    age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age -= 1;
    }
    if (age < 0) age = 0;
  }

  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  final bmr = base + _bmrOffset(sex);

  final factor = switch (activityLevel) {
    1 => 1.2,
    2 => 1.375,
    3 => 1.55,
    4 => 1.725,
    5 => 1.9,
    _ => 1.4,
  };
  return (bmr * factor).round();
}

KcalTargetResult computeKcalTarget(KcalTargetInput i) {
  final age = i.ageYears ?? _defaultAge;
  final base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * age;
  final bmr = base + _bmrOffset(i.sex);

  final factor = switch (i.activityLevel) {
    1 => 1.2,
    2 => 1.375,
    3 => 1.55,
    4 => 1.725,
    5 => 1.9,
    _ => 1.4,
  };
  final tdee = bmr * factor;

  var mode = KcalMode.maintain;
  var adjusted = tdee;
  var clamped = false;
  var usedDeadline = false;
  var weeklyChangeKg = 0.0;

  final goal = i.goalWeightKg;
  if (goal != null) {
    final diffKg = goal - i.weightKg; // 음수 = 감량, 양수 = 증량
    if (diffKg.abs() >= 0.5) {
      double dailyDelta;
      final deadline = i.goalDeadline;
      if (deadline != null) {
        final now = i.now ?? DateTime.now();
        // 기한까지 남은 일수. 1주 미만이면 1주로 본다 (너무 짧으면 1000 캡에 걸림).
        final rawDays = deadline.difference(now).inDays;
        final days = rawDays < 7 ? 7 : rawDays;
        dailyDelta = diffKg.abs() * kcalPerKgFat / days;
        usedDeadline = true;
      } else {
        // 기한 없음 → 기본 주 0.5kg 감량/증량 가정.
        dailyDelta = 500;
      }

      // 안전 캡: 주 1kg 초과 금지.
      if (dailyDelta > _maxDailyDeficit) {
        dailyDelta = _maxDailyDeficit;
        clamped = true;
      }

      if (diffKg < 0) {
        mode = KcalMode.cut;
        adjusted = tdee - dailyDelta;
        weeklyChangeKg = -dailyDelta * 7 / kcalPerKgFat;
      } else {
        mode = KcalMode.bulk;
        adjusted = tdee + dailyDelta;
        weeklyChangeKg = dailyDelta * 7 / kcalPerKgFat;
      }
    }
  }

  // 안전 하한 (남 1500, 여 1200, sex 미입력은 보수적으로 1200).
  final safeMin = i.sex == Sex.male ? 1500 : 1200;
  final daily = adjusted.round().clamp(safeMin, 10000);

  // 하한에 걸렸다면 원하는 속도로 못 감량 → clamped.
  if (adjusted < safeMin) {
    clamped = true;
    if (mode == KcalMode.cut) {
      // 실제 주간 감량량 재계산.
      final actualDailyDeficit = tdee - safeMin;
      weeklyChangeKg = -actualDailyDeficit.clamp(0, _maxDailyDeficit) *
          7 /
          kcalPerKgFat;
    }
  }

  return KcalTargetResult(
    bmr: bmr.round(),
    tdee: tdee.round(),
    dailyKcalTarget: daily,
    mode: mode,
    weeklyChangeKg: weeklyChangeKg,
    clampedBySafety: clamped,
    usedDeadline: usedDeadline,
  );
}
