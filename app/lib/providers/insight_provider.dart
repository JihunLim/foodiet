/// 인사이트 — 집계 프로바이더.
///
/// `recentEntriesProvider` 의 최근 90일 데이터를 7일/30일 윈도우로 묶어
/// 칼로리 달성률, 끼니 분포, 자주 먹은 음식, 매크로 평균 등을 계산한다.
///
/// 서버 계산이 아니라 클라이언트에서 처리한다 — 개수가 수백개 이하라
/// 메모리·CPU 부담이 없고, Realtime 업데이트 시 즉각 반영된다.
library;

import 'package:flutter/foundation.dart';
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
  const TopFood({required this.name, required this.count, this.representative});
  final String name;
  final int count;

  /// 즐겨찾기 생성용 대표 entry — kcal 을 가진 가장 최근 기록.
  /// null 이면 매크로를 알 수 없어 즐겨찾기 별표가 비활성화된다.
  final Entry? representative;
}

/// 푸디가 찾은 패턴 한 줄. [key] 는 레슨 선택·측정에서 쓰는 안정 식별자.
///
/// key: late_night | weekend_gap | snack_share | sodium_high | partial_days
class PatternFlag {
  const PatternFlag({required this.key, required this.emoji, required this.text});
  final String key;
  final String emoji;
  final String text;
}

/// 패턴 판정 임계값 — 기록이 이보다 적으면 억지 결론을 내지 않는다.
const int kPatternMinRecordDays = 3;

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
    this.lateNightDays = 0,
    this.weekdayAvgKcal = 0,
    this.weekendAvgKcal = 0,
    this.snackBeverageShare = 0,
    this.avgSodiumMg = 0,
    this.avgSugarG = 0,
    this.partialDays = 0,
    this.patternFlags = const [],
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

  /// 목표 -10% 미만한 날 수. 완료 기록이 2건 이상인 날만 센다 —
  /// 한 끼만 기록한 날은 "덜 먹은 날"이 아니라 "기록 적은 날"([partialDays]).
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

  // ── 패턴 인사이트 ──

  /// 야식(meal_slot = late_night) 완료 기록이 있는 날 수.
  final int lateNightDays;

  /// 평일(월~금) 기록일 평균 섭취 kcal. 기록일이 없으면 0.
  final int weekdayAvgKcal;

  /// 주말(토·일) 기록일 평균 섭취 kcal. 기록일이 없으면 0.
  final int weekendAvgKcal;

  /// 전체 섭취 kcal 중 간식·음료(eating_type snack|beverage) 비중 0~1.
  final double snackBeverageShare;

  /// 기록일 평균 나트륨(mg, 1인분). 나트륨 값이 있는 날만 대상, 없으면 0.
  final int avgSodiumMg;

  /// 기록일 평균 당(g, 1인분). 당 값이 있는 날만 대상, 없으면 0.
  final double avgSugarG;

  /// 완료 기록이 1건 이하인 기록일 수 ("기록 적은 날").
  final int partialDays;

  /// 의미 있는 패턴만. 기록일이 [kPatternMinRecordDays] 미만이면 빈 리스트.
  final List<PatternFlag> patternFlags;

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
      data: (all) =>
          AsyncValue.data(computeInsightSummary(all, window, target)),
    );
  },
);

/// 집계 본체 — 순수 함수. [now] 는 테스트에서 고정하기 위한 것.
@visibleForTesting
InsightSummary computeInsightSummary(
  List<Entry> all,
  InsightWindow window,
  int target, {
  DateTime? now,
}) =>
    _compute(all, window, target, now ?? DateTime.now());

InsightSummary _compute(
  List<Entry> all,
  InsightWindow window,
  int target,
  DateTime now,
) {
  final todayMidnight = DateTime(now.year, now.month, now.day);
  // Duration 덧셈은 DST 전환일에 자정이 어긋나 버킷 키가 엔트리 날짜와
  // 안 맞으므로 달력 연산(day ± n)으로 로컬 자정을 만든다.
  final start = DateTime(now.year, now.month, now.day - (window.days - 1));

  // 윈도우 내 entries 만 필터. captured_at 은 toLocal() 된 상태.
  final inWindow = all.where((e) {
    final d = DateTime(e.capturedAt.year, e.capturedAt.month, e.capturedAt.day);
    return !d.isBefore(start) && !d.isAfter(todayMidnight);
  }).toList();

  // 하루치 버킷 초기화 (기록 없어도 0 으로 채움).
  final buckets = <DateTime, _DayAccum>{};
  for (int i = 0; i < window.days; i++) {
    final d = DateTime(start.year, start.month, start.day + i);
    buckets[d] = _DayAccum();
  }

  // 끼니 / 매크로 / 음식명 집계.
  final mealCount = <String, int>{};
  final mealKcal = <String, int>{};
  double carbSum = 0, proteinSum = 0, fatSum = 0;
  int macroSampleDays = 0;
  final macroSeenDays = <DateTime>{};
  final foodFreq = <String, int>{};
  final foodRep = <String, Entry>{}; // 음식명 → 대표 entry (kcal 보유, 최신).
  int doneCount = 0;
  int snackBevKcal = 0;
  int allKcal = 0;

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
    if (slot == 'late_night') b.lateNight = true;

    allKcal += per;
    if (e.eatingType == 'snack' || e.eatingType == 'beverage') {
      snackBevKcal += per;
    }

    // 매크로 — 1인분 환산.
    final m = e.macros;
    if (m != null) {
      final share = e.sharedWithCount < 1 ? 1 : e.sharedWithCount;
      carbSum += ((m['carb_g'] as num?)?.toDouble() ?? 0) / share;
      proteinSum += ((m['protein_g'] as num?)?.toDouble() ?? 0) / share;
      fatSum += ((m['fat_g'] as num?)?.toDouble() ?? 0) / share;
      macroSeenDays.add(d);
      final sodium = m['sodium_mg'];
      if (sodium is num) {
        b.sodiumMg += sodium.toDouble() / share;
        b.hasSodium = true;
      }
      final sugar = m['sugar_g'];
      if (sugar is num) {
        b.sugarG += sugar.toDouble() / share;
        b.hasSugar = true;
      }
    }

    // 음식 이름 — title 이 있으면 첫 단어만 (공기밥/비빔밥 등 단순 매칭).
    final title = e.title?.trim();
    if (title != null && title.isNotEmpty) {
      final key = normalizeFoodName(title);
      if (key.isNotEmpty) {
        foodFreq[key] = (foodFreq[key] ?? 0) + 1;
        // 대표 entry — inWindow 는 captured_at 내림차순이므로
        // 처음 만난 kcal 보유 entry 가 가장 최근 것이다.
        if (e.kcalTotal != null && !foodRep.containsKey(key)) {
          foodRep[key] = e;
        }
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
  // 완료 기록이 1건뿐인 날이 밴드 아래면 "부족"이 아니라 "기록 적은 날"로
  // 따로 둔다(달성·부족 어디에도 넣지 않고 스트릭도 끊지 않는다).
  final lower = (target * 0.9).round();
  final upper = (target * 1.1).round();
  int onGoal = 0, over = 0, under = 0, partial = 0;
  int kcalSumForAvg = 0;
  int kcalSumDays = 0;
  for (final d in days) {
    if (!d.hasRecord) continue;
    kcalSumForAvg += d.consumedKcal;
    kcalSumDays++;
    if (d.entryCount <= 1) partial++;
    if (d.consumedKcal > upper) {
      over++;
    } else if (d.consumedKcal < lower) {
      if (d.entryCount >= 2) under++;
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
  // 기록 적은 날(1건, 밴드 아래)도 판단 보류라 건너뛴다.
  bool undecided(DayBucket d) =>
      !d.hasRecord || (d.entryCount <= 1 && d.consumedKcal < lower);

  int currentStreak = 0;
  for (int i = days.length - 1; i >= 0; i--) {
    final d = days[i];
    if (undecided(d)) continue;
    if (d.consumedKcal > upper || d.consumedKcal < lower) {
      break;
    }
    currentStreak++;
  }

  int bestStreak = 0;
  int running = 0;
  for (final d in days) {
    if (undecided(d)) continue;
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
      .map((e) =>
          TopFood(name: e.key, count: e.value, representative: foodRep[e.key]))
      .toList();

  // ── 패턴 인사이트 ──
  int lateNightDays = 0;
  int weekdaySum = 0, weekdayN = 0, weekendSum = 0, weekendN = 0;
  // 주말-평일 비교 결론은 완료 기록 2건 이상인 날끼리만 — 한 끼만 기록한
  // 평일이 "주말에 더 먹는다"는 착시를 만들지 않게.
  int weekdayFullSum = 0, weekdayFullN = 0, weekendFullSum = 0, weekendFullN = 0;
  double sodiumSum = 0, sugarSum = 0;
  int sodiumDays = 0, sugarDays = 0;
  for (final day in days) {
    if (!day.hasRecord) continue;
    final acc = buckets[day.date]!;
    if (acc.lateNight) lateNightDays++;
    final weekend = day.date.weekday == DateTime.saturday ||
        day.date.weekday == DateTime.sunday;
    final full = day.entryCount >= 2;
    if (weekend) {
      weekendSum += day.consumedKcal;
      weekendN++;
      if (full) {
        weekendFullSum += day.consumedKcal;
        weekendFullN++;
      }
    } else {
      weekdaySum += day.consumedKcal;
      weekdayN++;
      if (full) {
        weekdayFullSum += day.consumedKcal;
        weekdayFullN++;
      }
    }
    if (acc.hasSodium) {
      sodiumSum += acc.sodiumMg;
      sodiumDays++;
    }
    if (acc.hasSugar) {
      sugarSum += acc.sugarG;
      sugarDays++;
    }
  }
  final weekdayAvg = weekdayN == 0 ? 0 : (weekdaySum / weekdayN).round();
  final weekendAvg = weekendN == 0 ? 0 : (weekendSum / weekendN).round();
  final fullGap = (weekdayFullN == 0 || weekendFullN == 0)
      ? null
      : (weekendFullSum / weekendFullN - weekdayFullSum / weekdayFullN).round();
  final snackShare = allKcal <= 0 ? 0.0 : snackBevKcal / allKcal;
  final avgSodium = sodiumDays == 0 ? 0 : (sodiumSum / sodiumDays).round();
  final avgSugar = sugarDays == 0 ? 0.0 : sugarSum / sugarDays;

  final flags = kcalSumDays < kPatternMinRecordDays
      ? const <PatternFlag>[]
      : buildPatternFlags(
          lateNightDays: lateNightDays,
          weekendGapKcal: fullGap,
          snackBeverageShare: snackShare,
          avgSodiumMg: avgSodium,
          partialDays: partial,
        );

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
    lateNightDays: lateNightDays,
    weekdayAvgKcal: weekdayAvg,
    weekendAvgKcal: weekendAvg,
    snackBeverageShare: snackShare,
    avgSodiumMg: avgSodium,
    avgSugarG: avgSugar,
    partialDays: partial,
    patternFlags: flags,
  );
}

/// 수치 → 패턴 한 줄들. 임계값을 넘은 것만, 고정 순서로.
///
/// 문구 규칙: 푸디 반말, 평가·죄책감 표현 없이 "다음에 해볼 것" 하나만.
/// 효과 보장·굶기 권유 금지. [weekendGapKcal] 이 null 이면 비교 불가.
List<PatternFlag> buildPatternFlags({
  required int lateNightDays,
  required int? weekendGapKcal,
  required double snackBeverageShare,
  required int avgSodiumMg,
  required int partialDays,
}) {
  final flags = <PatternFlag>[];
  if (lateNightDays >= 2) {
    flags.add(PatternFlag(
      key: 'late_night',
      emoji: '🌙',
      text: '밤늦게 먹은 날이 $lateNightDays일 있었어. '
          '저녁을 조금 든든하게 챙기면 밤에 덜 출출할 수 있어.',
    ));
  }
  if (weekendGapKcal != null && weekendGapKcal >= 300) {
    flags.add(PatternFlag(
      key: 'weekend_gap',
      emoji: '📅',
      text: '주말엔 평일보다 하루 $weekendGapKcal kcal쯤 더 먹었어. '
          '주말 한 끼만 미리 정해두면 한결 편해.',
    ));
  }
  if (snackBeverageShare >= 0.25) {
    final pct = (snackBeverageShare * 100).round();
    flags.add(PatternFlag(
      key: 'snack_share',
      emoji: '🧋',
      text: '간식·음료가 전체 칼로리의 $pct%야. '
          '음료 하나를 가벼운 걸로 바꾸는 것부터 해봐도 좋아.',
    ));
  }
  if (avgSodiumMg >= 2000) {
    flags.add(PatternFlag(
      key: 'sodium_high',
      emoji: '🧂',
      text: '하루 나트륨이 평균 ${_comma(avgSodiumMg)}mg 정도야. '
          '국물은 건더기 위주로 먹어보자.',
    ));
  }
  if (partialDays >= 2) {
    flags.add(PatternFlag(
      key: 'partial_days',
      emoji: '📝',
      text: '한 끼만 기록한 날이 $partialDays일 있어. '
          '다른 끼니도 남겨주면 패턴을 더 정확히 볼 수 있어.',
    ));
  }
  return flags;
}

String _comma(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// 음식명 정규화 — "공기밥 (150g)" → "공기밥".
String normalizeFoodName(String s) {
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
  bool lateNight = false;
  double sodiumMg = 0;
  bool hasSodium = false;
  double sugarG = 0;
  bool hasSugar = false;
}
