/// 홈스크린 위젯 자동 동기화 프로바이더.
///
/// `todayEntriesProvider` + `profileProvider` + `homeCoachProvider` 가 바뀔 때마다
/// `FoodietWidgetService.sync(...)` 로 iOS/Android 위젯 데이터를 갱신한다.
/// 홈 탭이 떠 있는 동안만 active (autoDispose) — 백그라운드 배터리 부담 없음.
///
/// `home_coach` Edge Function 호출은 하루 상한이 있으므로, coach 데이터는
/// `valueOrNull` 로만 받아 있으면 반영하고 없으면 기존 값을 유지한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/home_widget_service.dart';
import 'entries_provider.dart';
import 'home_coach_provider.dart';
import 'profile_provider.dart';

final homeWidgetSyncProvider = Provider.autoDispose<void>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final entries = ref.watch(todayEntriesProvider).valueOrNull ?? const <Entry>[];
  final coach = ref.watch(homeCoachProvider).valueOrNull;

  if (profile == null) return;

  final target = profile.dailyKcalTarget ?? 1800;
  final consumed = entries.fold<int>(
      0, (acc, e) => acc + (e.kcalPerPerson ?? 0));
  final remaining = (target - consumed).clamp(0, target).toInt();

  double carb = 0, protein = 0, fat = 0;
  for (final e in entries) {
    if (e.status != 'done') continue;
    final m = e.macros;
    if (m == null) continue;
    final share = e.sharedWithCount < 1 ? 1 : e.sharedWithCount;
    carb += ((m['carb_g'] as num?)?.toDouble() ?? 0) / share;
    protein += ((m['protein_g'] as num?)?.toDouble() ?? 0) / share;
    fat += ((m['fat_g'] as num?)?.toDouble() ?? 0) / share;
  }

  final snapshot = FoodietWidgetSnapshot(
    nickname: profile.nickname,
    remainingKcal: remaining,
    consumedKcal: consumed,
    targetKcal: target,
    carbG: carb,
    proteinG: protein,
    fatG: fat,
    coachEmoji: coach?.emoji ?? '🍓',
    coachHeadline: coach?.headline ?? '오늘도 한 장씩 기록해볼까?',
    coachTip: coach?.nextTip ?? (entries.isEmpty
        ? '첫 사진 한 장으로 푸디의 조언을 받아봐.'
        : '다음 끼니엔 단백질을 챙겨보자.'),
    entryCount: entries.length,
    updatedAt: DateTime.now(),
  );

  // fire-and-forget — 위젯 실패로 UI 가 멈추면 안 됨.
  FoodietWidgetService.instance.sync(snapshot);
});
