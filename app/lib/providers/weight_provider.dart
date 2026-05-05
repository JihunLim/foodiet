/// 체중 로그 (`weight_logs` 테이블) + 투영(prediction) 계산 프로바이더.
///
/// 핵심 목표: "이대로 가면 목표 체중에 도달할 수 있을까?" 를 **선형 근사**
/// 로 보여준다.
///
/// - 7700 kcal ≈ 체지방 1 kg 등가 가정 (Wishnofsky, 1958).
///   ±15% 정도 편차가 있는 대략값이라 UI 에 "대략적인 예측" 으로 표시.
/// - 최근 14일 **기록이 있는 날** 평균 섭취 (기록 없는 날 0 이 아님 — 그건
///   투영을 왜곡시킴).
/// - TDEE 는 `kcal_calc.dart::computeTdee` 가 돌려주는 **원시값** 사용.
///   `computeKcalTarget` 의 clamp(1200/1500 하한, 주 1kg 캡) 는 *설정용*
///   권장치이지 *관찰/예측* 용이 아님.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kcal_calc.dart';
import 'auth_provider.dart';
import 'entries_provider.dart';
import 'profile_provider.dart';
import 'supabase_provider.dart';

// ─── 모델 ─────────────────────────────────────────────────────────────────

class WeightLog {
  const WeightLog({
    required this.id,
    required this.loggedAt,
    required this.weightKg,
    required this.source,
  });
  final String id;
  final DateTime loggedAt;
  final double weightKg;
  final String source; // manual | scale_sync

  factory WeightLog.fromJson(Map<String, dynamic> j) => WeightLog(
        id: j['id'] as String,
        loggedAt: DateTime.parse(j['logged_at'] as String).toLocal(),
        weightKg: (j['weight_kg'] as num).toDouble(),
        source: (j['source'] as String?) ?? 'manual',
      );
}

/// 투영 결과에 대한 판정. 각 상태마다 UI 가 다른 메시지/CTA 를 보여준다.
enum WeightVerdict {
  /// 프로필에 키/활동량/성별/생년월일 중 하나라도 없음 → TDEE 계산 불가.
  missingProfile,

  /// 목표 체중이 없음 → 투영 불가.
  missingGoal,

  /// 기한이 없음 → verdict 는 내지 못하지만, 예측 선 자체는 보여줄 수 있음.
  missingDeadline,

  /// 섭취 기록이 3일 미만 → 평균이 너무 흔들려서 투영 안 함.
  notEnoughIntake,

  /// 현재 체중이 목표 체중 근처(±0.3kg) — 이미 달성.
  atGoal,

  /// 기한이 이미 지남 — 새 기한 설정 유도.
  pastDeadline,

  /// 🎯 이대로 가면 기한 안에 도달.
  onTrack,

  /// ⚠️ 아슬아슬 — 예측이 목표에서 ±0.5kg 안.
  tight,

  /// 🔴 어려움 — 현재 추이로는 목표 기한에 도달하지 못함.
  offTrack,
}

/// "감량" 이냐 "증량" 이냐.
enum WeightGoalKind { cut, bulk, maintain }

class WeightProjection {
  const WeightProjection({
    required this.startWeightKg,
    required this.startDate,
    required this.goalWeightKg,
    required this.deadline,
    required this.tdeeKcal,
    required this.avgIntakeKcal,
    required this.intakeSampleDays,
    required this.dailyBalanceKcal,
    required this.dailyChangeKg,
    required this.predictedAtDeadlineKg,
    required this.predictedGapKg,
    required this.verdict,
    required this.kind,
  });

  /// 투영 시작점. 최신 체중 로그 또는 profile.weight_kg.
  final double startWeightKg;
  final DateTime startDate;

  final double? goalWeightKg;
  final DateTime? deadline;

  final int? tdeeKcal;
  final int? avgIntakeKcal;
  final int intakeSampleDays;

  /// 섭취 - TDEE. 음수 = 적자(감량).
  final double? dailyBalanceKcal;

  /// 하루 체중 변화량(kg). 음수 = 감량.
  final double? dailyChangeKg;

  /// 기한 날짜의 예상 체중.
  final double? predictedAtDeadlineKg;

  /// 예상 - 목표 (부호 고려). cut 목표일 때 양수면 "아직 목표 위" = 나쁨.
  final double? predictedGapKg;

  final WeightVerdict verdict;
  final WeightGoalKind kind;

  /// 임의 날짜에서의 예상 체중. dailyChange 가 없으면 startWeight 그대로.
  ///
  /// 수식 (선형 아님 — 실제 체중 감량 곡선 근사):
  ///   1) **초반 water shift** — 적자/흑자 시작 후 τ=10일 동안 지수적으로
  ///      수분·글리코겐 무게가 빠지거나 실린다. 최대 ±1.2kg 까지.
  ///   2) **metabolic adaptation** — TDEE 가 체중에 비례해 줄어드니 장기적으로
  ///      감량률이 둔화. τ=60일, 최종 85% 수준(plateau factor).
  ///   3) **일일 변동** — 염분·음식 부피·수화 상태로 ±0.4kg 내외 흔들림.
  ///      startDate 기준 일수로 결정론적 sin 합 (같은 날 = 같은 값, 흔들림
  ///      이 지도록 보이지만 재계산 안정).
  double predictedWeightAt(DateTime date) {
    final change = dailyChangeKg;
    if (change == null) return startWeightKg;
    final startDay =
        DateTime(startDate.year, startDate.month, startDate.day);
    final targetDay = DateTime(date.year, date.month, date.day);
    final days = targetDay.difference(startDay).inDays;
    return projectWeight(startWeightKg, change, days);
  }

  /// `predictedWeightAt` 의 순수 수치 버전. 테스트/내부에서 재사용.
  @visibleForTesting
  static double projectWeight(
      double startWeightKg, double dailyChangeKg, int days) {
    if (days == 0 || dailyChangeKg == 0) return startWeightKg;
    final d = days.toDouble();
    final dailyAbs = dailyChangeKg.abs();
    final isCut = dailyChangeKg < 0;

    // 초반 water shift — 적자 강도에 비례(아주 약한 적자면 물도 덜 빠짐),
    // 최대 1.2kg 까지만, 10일 τ 로 포화.
    final waterMag = math.min(1.2, dailyAbs * 160.0);
    final waterShift = waterMag * (1 - math.exp(-d / 10.0));

    // plateau — 장기적으로 감량률 85% 로 수렴.
    final plateau = 1.0 - 0.15 * (1 - math.exp(-d / 60.0));
    final coreShift = dailyChangeKg * d * plateau;

    // 일일 변동 — 3-성분 sin 합 (≈ ±0.43kg 폭).
    final osc = 0.22 * math.sin(d * 0.9) +
        0.13 * math.sin(d * 2.3 + 1.7) +
        0.08 * math.cos(d * 5.1 + 0.3);

    final waterContribution = isCut ? -waterShift : waterShift;
    return startWeightKg + coreShift + waterContribution + osc;
  }

  /// 목표 도달까지 필요한 "**추가**" 일일 칼로리 적자(양수 = 더 줄여야).
  /// offTrack/tight 때만 의미 있음.
  int? get requiredExtraDailyDeficitKcal {
    final goal = goalWeightKg;
    final gap = predictedGapKg;
    final dl = deadline;
    if (goal == null || gap == null || dl == null) return null;
    final today = DateTime.now();
    final daysRemaining = DateTime(dl.year, dl.month, dl.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (daysRemaining <= 0) return null;
    // gap > 0 (cut, 예측이 목표보다 높음) → 하루 |gap|*7700/days 더 줄여야.
    // gap < 0 (cut, 예측이 목표보다 낮음) → 이미 도달 중.
    // bulk 의 경우 부호 반대.
    final isCut = kind == WeightGoalKind.cut;
    final needsMore = isCut ? gap > 0 : gap < 0;
    if (!needsMore) return 0;
    return (gap.abs() * kcalPerKgFat / daysRemaining).round();
  }

  /// 지금 추이로 목표 체중에 며칠 후 도달할지. 도달 불가면 null.
  int? get daysToGoalAtCurrentPace {
    final goal = goalWeightKg;
    final change = dailyChangeKg;
    if (goal == null || change == null || change == 0) return null;
    final diff = goal - startWeightKg; // 감량 목표면 음수
    // change 와 diff 의 부호가 일치해야 도달 가능.
    if (diff.sign != change.sign) return null;
    final days = diff / change;
    if (days <= 0 || !days.isFinite) return null;
    return days.round();
  }

  /// 기한을 몇 일 연장하면 도달 가능한지.
  int? get extraDaysToReachGoal {
    final total = daysToGoalAtCurrentPace;
    final dl = deadline;
    if (total == null || dl == null) return null;
    final today = DateTime.now();
    final daysRemaining = DateTime(dl.year, dl.month, dl.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final extra = total - daysRemaining;
    return extra > 0 ? extra : null;
  }
}

// ─── 프로바이더 ───────────────────────────────────────────────────────────

/// 사용자의 체중 로그. 최신순(내림차순) 365개 제한.
final weightLogsProvider = FutureProvider<List<WeightLog>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('weight_logs')
      .select('id, logged_at, weight_kg, source')
      .eq('user_id', user.id)
      .order('logged_at', ascending: false)
      .limit(365);
  return (rows as List)
      .map<WeightLog>(
          (r) => WeightLog.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();
});

/// 오늘 기준 체중 투영. 프로필 + 체중 로그 + 최근 섭취를 합쳐 계산.
///
/// InsightSummary 를 재사용하지 않는다 — 그쪽은 윈도우(7/30) 가 사용자
/// 선택에 따라 변해서 예측이 흔들려. 여기선 고정 14일 윈도우.
final weightProjectionProvider =
    Provider<AsyncValue<WeightProjection>>((ref) {
  final profileAsync = ref.watch(profileProvider);
  final logsAsync = ref.watch(weightLogsProvider);
  final entriesAsync = ref.watch(recentEntriesProvider);

  // 하나라도 로딩이면 로딩.
  if (profileAsync.isLoading ||
      logsAsync.isLoading ||
      entriesAsync.isLoading) {
    return const AsyncValue.loading();
  }
  // 에러 전파.
  if (profileAsync.hasError) {
    return AsyncValue.error(
        profileAsync.error!, profileAsync.stackTrace ?? StackTrace.current);
  }
  if (logsAsync.hasError) {
    return AsyncValue.error(
        logsAsync.error!, logsAsync.stackTrace ?? StackTrace.current);
  }
  if (entriesAsync.hasError) {
    return AsyncValue.error(
        entriesAsync.error!, entriesAsync.stackTrace ?? StackTrace.current);
  }

  final profile = profileAsync.valueOrNull;
  final logs = logsAsync.valueOrNull ?? const <WeightLog>[];
  final entries = entriesAsync.valueOrNull ?? const <Entry>[];

  return AsyncValue.data(_compute(profile, logs, entries));
});

/// 테스트용 공개 엔트리 — `_compute` 는 library-private 이지만
/// 분기 많은 로직이라 외부에서 직접 실행할 수 있어야 회귀 잡기 쉬움.
@visibleForTesting
WeightProjection computeProjectionForTest({
  required AppProfile? profile,
  required List<WeightLog> logs,
  required List<Entry> entries,
  DateTime? now,
}) {
  return _compute(profile, logs, entries, now: now);
}

WeightProjection _compute(
  AppProfile? profile,
  List<WeightLog> logs,
  List<Entry> entries, {
  DateTime? now,
}) {
  // 1) 시작 체중/날짜 — 최신 로그가 우선, 없으면 프로필.
  double? startWeight;
  DateTime startDate;
  if (logs.isNotEmpty) {
    startWeight = logs.first.weightKg;
    final d = logs.first.loggedAt;
    startDate = DateTime(d.year, d.month, d.day);
  } else {
    startWeight = profile?.weightKg;
    final nowLocal = now ?? DateTime.now();
    startDate = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  }

  final goal = profile?.goalWeightKg;
  final deadline = profile?.goalDeadline;

  // kind 결정.
  WeightGoalKind kind = WeightGoalKind.maintain;
  if (startWeight != null && goal != null) {
    final diff = goal - startWeight;
    if (diff.abs() < 0.3) {
      kind = WeightGoalKind.maintain;
    } else if (diff < 0) {
      kind = WeightGoalKind.cut;
    } else {
      kind = WeightGoalKind.bulk;
    }
  }

  // Early exits — 투영 못 하는 상태.
  if (startWeight == null) {
    return WeightProjection(
      startWeightKg: 0,
      startDate: startDate,
      goalWeightKg: goal,
      deadline: deadline,
      tdeeKcal: null,
      avgIntakeKcal: null,
      intakeSampleDays: 0,
      dailyBalanceKcal: null,
      dailyChangeKg: null,
      predictedAtDeadlineKg: null,
      predictedGapKg: null,
      verdict: WeightVerdict.missingProfile,
      kind: kind,
    );
  }

  // 2) TDEE — 원시값 (clamp 없음). 최신 체중 기준.
  final tdee = computeTdee(
    sex: profile?.sex,
    birthDate: profile?.birthDate,
    heightCm: profile?.heightCm,
    weightKg: startWeight,
    activityLevel: profile?.activityLevel,
  );

  // 3) 최근 14일 평균 섭취 (기록 있는 날만).
  //    오늘 포함 14일 창. cutoff = today - 13일 (오늘까지 총 14일).
  final nowDt = now ?? DateTime.now();
  final today = DateTime(nowDt.year, nowDt.month, nowDt.day);
  final cutoff = today.subtract(const Duration(days: 13));
  final byDay = <DateTime, int>{};
  for (final e in entries) {
    if (e.status != 'done') continue;
    final d = DateTime(e.capturedAt.year, e.capturedAt.month, e.capturedAt.day);
    if (d.isBefore(cutoff)) continue;
    byDay[d] = (byDay[d] ?? 0) + (e.kcalPerPerson ?? 0);
  }
  int? avgIntake;
  if (byDay.isNotEmpty) {
    final sum = byDay.values.fold<int>(0, (a, b) => a + b);
    avgIntake = (sum / byDay.length).round();
  }
  final intakeDays = byDay.length;

  // 4) Verdict 결정 + 예측값 계산.
  WeightVerdict verdict;
  double? dailyBalance;
  double? dailyChange;
  double? predictedAtDeadline;
  double? predictedGap;

  if (profile == null || tdee == null) {
    verdict = WeightVerdict.missingProfile;
  } else if (goal == null) {
    verdict = WeightVerdict.missingGoal;
  } else if (kind == WeightGoalKind.maintain) {
    verdict = WeightVerdict.atGoal;
  } else if (intakeDays < 3 || avgIntake == null) {
    verdict = WeightVerdict.notEnoughIntake;
  } else {
    // 모든 조건 갖춤 — 예측 계산.
    dailyBalance = (avgIntake - tdee).toDouble();
    dailyChange = dailyBalance / kcalPerKgFat;

    if (deadline == null) {
      verdict = WeightVerdict.missingDeadline;
    } else if (deadline.isBefore(today)) {
      verdict = WeightVerdict.pastDeadline;
    } else {
      final dl = DateTime(deadline.year, deadline.month, deadline.day);
      final daysToDeadline = dl.difference(startDate).inDays;
      // 새 곡선 모델 기준으로 기한 예측 — 렌더링된 그래프와 verdict 일치 보장.
      predictedAtDeadline = WeightProjection.projectWeight(
          startWeight, dailyChange, daysToDeadline);
      predictedGap = predictedAtDeadline - goal;

      // 판정 — cut 이면 gap <= 0 이 좋음, bulk 면 gap >= 0 이 좋음.
      final isCut = kind == WeightGoalKind.cut;
      final onGoalSide = isCut ? predictedGap <= 0 : predictedGap >= 0;
      final gapAbs = predictedGap.abs();

      if (onGoalSide) {
        verdict = WeightVerdict.onTrack;
      } else if (gapAbs <= 0.5) {
        verdict = WeightVerdict.tight;
      } else {
        verdict = WeightVerdict.offTrack;
      }
    }
  }

  return WeightProjection(
    startWeightKg: startWeight,
    startDate: startDate,
    goalWeightKg: goal,
    deadline: deadline,
    tdeeKcal: tdee,
    avgIntakeKcal: avgIntake,
    intakeSampleDays: intakeDays,
    dailyBalanceKcal: dailyBalance,
    dailyChangeKg: dailyChange,
    predictedAtDeadlineKg: predictedAtDeadline,
    predictedGapKg: predictedGap,
    verdict: verdict,
    kind: kind,
  );
}

// ─── 쓰기 동작 ────────────────────────────────────────────────────────────

/// 현재 체중을 기록. 같은 날짜에 이미 기록이 있으면 덮어씀 (하루 1회 정책).
/// 프로필의 `weight_kg` 도 최신값으로 갱신해서 TDEE 계산에 반영.
///
/// `WidgetRef` 를 받아 UI 콜백에서 바로 호출 가능. Provider 내부 함수에서
/// 호출할 일이 생기면 별도 오버로드를 추가할 것.
Future<void> logWeight({
  required WidgetRef ref,
  required double weightKg,
  DateTime? loggedAt,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) {
    throw StateError('로그인 상태가 아닙니다');
  }
  final client = ref.read(supabaseClientProvider);
  final when = loggedAt ?? DateTime.now();
  final dayStart = DateTime(when.year, when.month, when.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  // 같은 날짜 기존 기록 삭제.
  await client
      .from('weight_logs')
      .delete()
      .eq('user_id', user.id)
      .gte('logged_at', dayStart.toUtc().toIso8601String())
      .lt('logged_at', dayEnd.toUtc().toIso8601String());

  await client.from('weight_logs').insert({
    'user_id': user.id,
    'logged_at': when.toUtc().toIso8601String(),
    'weight_kg': weightKg,
    'source': 'manual',
  });

  // 프로필의 "현재 체중" 을 최신 로그로 갱신 → TDEE 계산에도 반영.
  // 단 기존 기록이 오늘 기록보다 더 최근인 경우는 건드리지 않는다.
  final latestRow = await client
      .from('weight_logs')
      .select('weight_kg, logged_at')
      .eq('user_id', user.id)
      .order('logged_at', ascending: false)
      .limit(1)
      .maybeSingle();
  if (latestRow != null) {
    await client.from('profiles').update({
      'weight_kg': (latestRow['weight_kg'] as num).toDouble(),
    }).eq('user_id', user.id);
  }

  ref.invalidate(weightLogsProvider);
  ref.invalidate(profileProvider);
}

/// 특정 체중 로그 삭제.
Future<void> deleteWeightLog({
  required WidgetRef ref,
  required String id,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final client = ref.read(supabaseClientProvider);
  await client
      .from('weight_logs')
      .delete()
      .eq('id', id)
      .eq('user_id', user.id);
  ref.invalidate(weightLogsProvider);
}
