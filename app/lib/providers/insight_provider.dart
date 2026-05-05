/// 인사이트 — 집계 프로바이더.
///
/// `recentEntriesProvider` 의 최근 90일 데이터를 7일/30일 윈도우로 묶어
/// 칼로리 달성률, 끼니 분포, 자주 먹은 음식, 매크로 평균 등을 계산한다.
///
/// 서버 계산이 아니라 클라이언트에서 처리한다 — 개수가 수백개 이하라
/// 메모리·CPU 부담이 없고, Realtime 업데이트 시 즉각 반영된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entries_provider.dart';
import 'profile_provider.dart';

enum InsightWindow { week, month }

extension InsightWindowX on InsightWindow {
  int get days => switch (this) {
        InsightWindow.week => 7,
        InsightWindow.month => 30,
      };
  String get label => switch (this) {
        InsightWindow.week => '지난 7일',
        InsightWindow.month => '지난 30일',
      };
}

/// 인사이트 윈도우 선택 상태 (UI 에서 탭으로 조작).
final insightWindowProvider =
    StateProvider<InsightWindow>((ref) => InsightWindow.week);

/// 하루치 섭취 요약.
class DayBucket {
  const DayBucket({
    required this.date,
    required this.consumedKcal,
    required this.entryCount,
  });
  final DateTime date; // 로컬 자정
  final int consumedKcal;
  final int entryCount;

  bool get hasRecord => entryCount > 0;
}

/// 끼니별 집계.
class MealSlotStat {
  const MealSlotStat({
    required this.slot,
    required this.count,
    required this.kcalTotal,
  });
  final String slot; // breakfast | lunch | dinner | late_night | unknown
  final int count;
  final int kcalTotal;
}

/// 자주 먹은 음식.
class TopFood {
  const TopFood({required this.name, required this.count});
  final String name;
  final int count;
}

class InsightSummary {
  const InsightSummary({
    required this.window,
    required this.targetKcal,
    required this.days,
    required this.avgKcal,
    required this.avgKcalAllDays,
    required this.onGoalDays,
    required this.overDays,
    required this.underDays,
    required this.currentStreak,
    required this.bestStreak,
    required this.mealSlots,
    required this.avgCarbG,
    required this.avgProteinG,
    required this.avgFatG,
    required this.topFoods,
    required this.totalEntries,
    required this.totalDoneEntries,
  });

  final InsightWindow window;
  final int targetKcal;

  /// 윈도우 안 모든 날 (기록 없는 날 포함). 차트 용.
  final List<DayBucket> days;

  /// 윈도우 총 일수 (7 또는 30). UI 에서 "X/W 일" 표기용.
  int get windowDays => days.length;

  /// 기록이 있던 날만 대상으로 한 평균 섭취 (기록 없는 날 제외).
  final int avgKcal;

  /// 윈도우 전체 일수 기준 일일 평균 (기록 없는 날은 0 으로 집계).
  /// 같은 레코드라도 윈도우가 커지면 이 값은 작아진다 — 7일 / 30일 비교 시
  /// 숫자가 실제로 움직이는 지표.
  final int avgKcalAllDays;

  /// 목표 범위(±10%) 안에 들어온 날 수. 0 kcal 인 날은 제외.
  final int onGoalDays;

  /// 목표 +10% 초과한 날 수.
  final int overDays;

  /// 목표 -10% 미만한 날 수.
  final int underDays;

  /// 현재 연속 달성일 (오늘부터 거슬러 올라가며).
  final int currentStreak;

  /// 윈도우 내 최장 연속 달성일.
  final int bestStreak;

  final List<MealSlotStat> mealSlots;
  final double avgCarbG;
  final double avgProteinG;
  final double avgFatG;

  final List<TopFood> topFoods;

  final int totalEntries;
  final int totalDoneEntries;

  /// 기록이 있는 날 수 (차트에서 막대가 뜨는 날).
  int get recordDays => days.where((d) => d.hasRecord).length;

  /// 달성률 = onGoalDays / recordDays.
  double get onGoalRate =>
      recordDays == 0 ? 0 : onGoalDays / recordDays;

  /// 푸디 한줄평 — 숫자만 주어도 가장 중요한 메시지를 판별한다.
  String get coachSummary {
    if (recordDays == 0) {
      return '아직 기록이 없어! 사진 한 장으로 시작해보자 🍓';
    }
    final rate = (onGoalRate * 100).round();
    if (onGoalDays >= recordDays - 1 && recordDays >= 3) {
      return '완벽해! $recordDays일 중 $onGoalDays일 목표 달성. 이대로만 가자 ✨';
    }
    if (overDays > underDays && overDays >= 2) {
      return '최근 칼로리가 살짝 많았어. 내일은 단백질 위주로 가볍게 가보자 🥗';
    }
    if (underDays > overDays && underDays >= 3) {
      return '섭취가 부족한 날이 많아. 에너지 부족은 오히려 요요를 불러. 제대로 챙겨 먹자 🍚';
    }
    if (currentStreak >= 3) {
      return '$currentStreak일 연속 목표 달성 중! 이 흐름 유지해보자 🔥';
    }
    return '$recordDays일 기록, $onGoalDays일 목표 달성 ($rate%). 꾸준함이 답이야 🌱';
  }
}

/// 최근 윈도우의 인사이트 집계. `insightWindowProvider` 가 바뀌거나
/// `recentEntriesProvider` 에 업데이트가 오면 자동 재계산.
final insightSummaryProvider = Provider.autoDispose<AsyncValue<InsightSummary>>(
  (ref) {
    final window = ref.watch(insightWindowProvider);
    final entriesAsync = ref.watch(recentEntriesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final target = profile?.dailyKcalTarget ?? 1800;

    return entriesAsync.when(
      loading: () => const AsyncValue.loading(),
      error: (e, s) => AsyncValue.error(e, s),
      data: (all) => AsyncValue.data(_compute(all, window, target)),
    );
  },
);

InsightSummary _compute(
  List<Entry> all,
  InsightWindow window,
  int target,
) {
  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final start = todayMidnight.subtract(Duration(days: window.days - 1));

  // 윈도우 내 entries 만 필터. captured_at 은 toLocal() 된 상태.
  final inWindow = all.where((e) {
    final d = DateTime(e.capturedAt.year, e.capturedAt.month, e.capturedAt.day);
    return !d.isBefore(start) && !d.isAfter(todayMidnight);
  }).toList();

  // 하루치 버킷 초기화 (기록 없어도 0 으로 채움).
  final buckets = <DateTime, _DayAccum>{};
  for (int i = 0; i < window.days; i++) {
    final d = start.add(Duration(days: i));
    buckets[d] = _DayAccum();
  }

  // 끼니 / 매크로 / 음식명 집계.
  final mealCount = <String, int>{};
  final mealKcal = <String, int>{};
  double carbSum = 0, proteinSum = 0, fatSum = 0;
  int macroSampleDays = 0;
  final macroSeenDays = <DateTime>{};
  final foodFreq = <String, int>{};
  int doneCount = 0;

  for (final e in inWindow) {
    if (e.status != 'done') continue;
    doneCount++;
    final d = DateTime(
        e.capturedAt.year, e.capturedAt.month, e.capturedAt.day);
    final b = buckets[d];
    if (b == null) continue;

    final per = e.kcalPerPerson ?? 0;
    b.kcal += per;
    b.count += 1;

    final slot = e.mealSlot ?? 'unknown';
    mealCount[slot] = (mealCount[slot] ?? 0) + 1;
    mealKcal[slot] = (mealKcal[slot] ?? 0) + per;

    // 매크로 — 1인분 환산.
    final m = e.macros;
    if (m != null) {
      final share = e.sharedWithCount < 1 ? 1 : e.sharedWithCount;
      carbSum += ((m['carb_g'] as num?)?.toDouble() ?? 0) / share;
      proteinSum += ((m['protein_g'] as num?)?.toDouble() ?? 0) / share;
      fatSum += ((m['fat_g'] as num?)?.toDouble() ?? 0) / share;
      macroSeenDays.add(d);
    }

    // 음식 이름 — title 이 있으면 첫 단어만 (공기밥/비빔밥 등 단순 매칭).
    final title = e.title?.trim();
    if (title != null && title.isNotEmpty) {
      final key = _normalizeFoodName(title);
      if (key.isNotEmpty) {
        foodFreq[key] = (foodFreq[key] ?? 0) + 1;
      }
    }
  }
  macroSampleDays = macroSeenDays.length;

  final days = buckets.entries
      .map((e) => DayBucket(
            date: e.key,
            consumedKcal: e.value.kcal,
            entryCount: e.value.count,
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // 목표 달성 계산 — ±10% 밴드.
  final lower = (target * 0.9).round();
  final upper = (target * 1.1).round();
  int onGoal = 0, over = 0, under = 0;
  int kcalSumForAvg = 0;
  int kcalSumDays = 0;
  for (final d in days) {
    if (!d.hasRecord) continue;
    kcalSumForAvg += d.consumedKcal;
    kcalSumDays++;
    if (d.consumedKcal > upper) {
      over++;
    } else if (d.consumedKcal < lower) {
      under++;
    } else {
      onGoal++;
    }
  }
  final avgKcal = kcalSumDays == 0 ? 0 : (kcalSumForAvg / kcalSumDays).round();
  // 윈도우 전체 일수 평균 — 기록 없는 날은 0 으로 포함. 7 일 vs 30 일
  // 전환 시 값이 달라지는 "변동 지표" 로 UI 에 노출한다.
  final avgKcalAllDays =
      days.isEmpty ? 0 : (kcalSumForAvg / days.length).round();

  // 연속 스트릭 — 오늘부터 거슬러 올라가며 onGoal 이 깨지지 않은 일수.
  // 기록 없는 날은 스트릭을 중단시키지 않지만 증가시키지도 않는다.
  int currentStreak = 0;
  for (int i = days.length - 1; i >= 0; i--) {
    final d = days[i];
    if (!d.hasRecord) continue;
    if (d.consumedKcal > upper || d.consumedKcal < lower) {
      break;
    }
    currentStreak++;
  }

  int bestStreak = 0;
  int running = 0;
  for (final d in days) {
    if (!d.hasRecord) continue;
    if (d.consumedKcal > upper || d.consumedKcal < lower) {
      if (running > bestStreak) bestStreak = running;
      running = 0;
    } else {
      running++;
    }
  }
  if (running > bestStreak) bestStreak = running;

  // 끼니 분포 - 고정 순서로 반환.
  const order = ['breakfast', 'lunch', 'dinner', 'late_night'];
  final mealSlots = [
    for (final s in order)
      MealSlotStat(
        slot: s,
        count: mealCount[s] ?? 0,
        kcalTotal: mealKcal[s] ?? 0,
      ),
  ];

  // Top 5 음식.
  final topFoods = (foodFreq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(5)
      .map((e) => TopFood(name: e.key, count: e.value))
      .toList();

  return InsightSummary(
    window: window,
    targetKcal: target,
    days: days,
    avgKcal: avgKcal,
    avgKcalAllDays: avgKcalAllDays,
    onGoalDays: onGoal,
    overDays: over,
    underDays: under,
    currentStreak: currentStreak,
    bestStreak: bestStreak,
    mealSlots: mealSlots,
    avgCarbG:
        macroSampleDays == 0 ? 0 : carbSum / macroSampleDays,
    avgProteinG:
        macroSampleDays == 0 ? 0 : proteinSum / macroSampleDays,
    avgFatG: macroSampleDays == 0 ? 0 : fatSum / macroSampleDays,
    topFoods: topFoods,
    totalEntries: inWindow.length,
    totalDoneEntries: doneCount,
  );
}

/// 음식명 정규화 — "공기밥 (150g)" → "공기밥".
String _normalizeFoodName(String s) {
  var t = s.trim();
  // 괄호 이후 부가정보 제거.
  final paren = t.indexOf(RegExp(r'[(（]'));
  if (paren > 0) t = t.substring(0, paren).trim();
  // 슬래시·쉼표 다중 품목은 첫 항목만.
  for (final sep in const ['/', ',', '·', '+']) {
    final i = t.indexOf(sep);
    if (i > 0) t = t.substring(0, i).trim();
  }
  return t;
}

class _DayAccum {
  int kcal = 0;
  int count = 0;
}
