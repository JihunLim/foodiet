/// 홈스크린 위젯 데이터 브리지.
///
/// 기획안 §4.1 / §4.4 / §4.5 — 앱을 열지 않고도
///   - 카메라 빠른 기록 (`quick_log`)
///   - 오늘 남은 칼로리 + 탄·단·지 (`remaining`)
///   - 푸디의 한마디 (`coach_tip`)
/// 위젯 3종을 홈스크린에서 바로 볼 수 있도록 한다.
///
/// iOS: App Group `group.com.jihun.foodiet.widget` 의 UserDefaults 에 기록 →
///       WidgetKit 타임라인 provider 가 읽어 SwiftUI 로 렌더.
/// Android: SharedPreferences(`HomeWidgetPreferences`) 에 기록 → 각 AppWidgetProvider
///           가 RemoteViews 로 렌더.
///
/// 호출자는 `FoodietWidgetService.sync(...)` 만 호출하면 된다. 내부에서 직렬화·
/// 업데이트를 묶어 한 번의 I/O 로 처리한다.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// App Group 식별자 — iOS widget target 과 공유.
/// Xcode 프로젝트의 Signing & Capabilities 에서 동일 이름으로 App Group 을 추가해야 한다.
const _iosAppGroup = 'group.com.jihun.foodiet.widget';

/// Android `AppWidgetProvider` 풀 네임 (manifest 의 receiver 이름과 일치).
const _androidProviderQuickLog =
    'com.jihun.foodiet.widget.QuickLogWidgetProvider';
const _androidProviderRemaining =
    'com.jihun.foodiet.widget.RemainingWidgetProvider';
const _androidProviderCoach =
    'com.jihun.foodiet.widget.CoachTipWidgetProvider';

/// iOS WidgetKit 의 `kind` 문자열.
const _iosKindQuickLog = 'FoodietQuickLogWidget';
const _iosKindRemaining = 'FoodietRemainingWidget';
const _iosKindCoach = 'FoodietCoachTipWidget';

class FoodietWidgetSnapshot {
  const FoodietWidgetSnapshot({
    required this.nickname,
    required this.remainingKcal,
    required this.consumedKcal,
    required this.targetKcal,
    required this.carbG,
    required this.proteinG,
    required this.fatG,
    required this.coachEmoji,
    required this.coachHeadline,
    required this.coachTip,
    required this.entryCount,
    required this.updatedAt,
  });

  final String nickname;
  final int remainingKcal;
  final int consumedKcal;
  final int targetKcal;
  final double carbG;
  final double proteinG;
  final double fatG;
  final String coachEmoji;
  final String coachHeadline;
  final String coachTip;
  final int entryCount;
  final DateTime updatedAt;
}

class FoodietWidgetService {
  FoodietWidgetService._();
  static final FoodietWidgetService instance = FoodietWidgetService._();

  bool _initialized = false;

  /// `main.dart` 의 부팅 단계에서 호출 권장. `setAppGroupId` 는 모든 다른
  /// `HomeWidget.*` 호출 전에 한 번 실행돼야 native 채널이 정상 동작.
  Future<void> ensureInit() => _ensureInit();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      await HomeWidget.setAppGroupId(_iosAppGroup);
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[widget] setAppGroupId failed: $e');
    }
  }

  /// 현재 홈 상태를 위젯 저장소에 반영하고 위젯을 다시 그린다.
  /// 실패해도 앱 본체에는 영향이 없어야 하므로 throw 하지 않는다.
  Future<void> sync(FoodietWidgetSnapshot s) async {
    try {
      await _ensureInit();
      await Future.wait([
        HomeWidget.saveWidgetData<String>('nickname', s.nickname),
        HomeWidget.saveWidgetData<int>('remaining_kcal', s.remainingKcal),
        HomeWidget.saveWidgetData<int>('consumed_kcal', s.consumedKcal),
        HomeWidget.saveWidgetData<int>('target_kcal', s.targetKcal),
        HomeWidget.saveWidgetData<int>('carb_g', s.carbG.round()),
        HomeWidget.saveWidgetData<int>('protein_g', s.proteinG.round()),
        HomeWidget.saveWidgetData<int>('fat_g', s.fatG.round()),
        HomeWidget.saveWidgetData<String>('coach_emoji', s.coachEmoji),
        HomeWidget.saveWidgetData<String>('coach_headline', s.coachHeadline),
        HomeWidget.saveWidgetData<String>('coach_tip', s.coachTip),
        HomeWidget.saveWidgetData<int>('entry_count', s.entryCount),
        HomeWidget.saveWidgetData<String>(
            'updated_at', s.updatedAt.toIso8601String()),
      ]);
      await _updateAll();
    } catch (e) {
      if (kDebugMode) debugPrint('[widget] sync failed: $e');
    }
  }

  /// 로그아웃·계정 전환 시 위젯을 빈 상태로 되돌린다.
  Future<void> clear() async {
    try {
      await _ensureInit();
      await Future.wait([
        HomeWidget.saveWidgetData<String>('nickname', ''),
        HomeWidget.saveWidgetData<int>('remaining_kcal', 0),
        HomeWidget.saveWidgetData<int>('consumed_kcal', 0),
        HomeWidget.saveWidgetData<int>('target_kcal', 0),
        HomeWidget.saveWidgetData<int>('carb_g', 0),
        HomeWidget.saveWidgetData<int>('protein_g', 0),
        HomeWidget.saveWidgetData<int>('fat_g', 0),
        HomeWidget.saveWidgetData<String>('coach_emoji', '🍓'),
        HomeWidget.saveWidgetData<String>('coach_headline', ''),
        HomeWidget.saveWidgetData<String>('coach_tip', ''),
        HomeWidget.saveWidgetData<int>('entry_count', 0),
      ]);
      await _updateAll();
    } catch (e) {
      if (kDebugMode) debugPrint('[widget] clear failed: $e');
    }
  }

  Future<void> _updateAll() async {
    if (Platform.isIOS) {
      await Future.wait([
        HomeWidget.updateWidget(iOSName: _iosKindQuickLog),
        HomeWidget.updateWidget(iOSName: _iosKindRemaining),
        HomeWidget.updateWidget(iOSName: _iosKindCoach),
      ]);
    } else if (Platform.isAndroid) {
      await Future.wait([
        HomeWidget.updateWidget(
            qualifiedAndroidName: _androidProviderQuickLog),
        HomeWidget.updateWidget(
            qualifiedAndroidName: _androidProviderRemaining),
        HomeWidget.updateWidget(qualifiedAndroidName: _androidProviderCoach),
      ]);
    }
  }

  /// 위젯을 탭했을 때 전달되는 딥링크 URI 리스너를 등록한다.
  /// URI 스킴: `foodiet://widget/<target>` — 현재는 `camera` 한 가지.
  ///
  /// `_ensureInit` 을 먼저 await 해서 AppGroupId 가 native 에 set 된 뒤
  /// `widgetClicked` 스트림 / `initiallyLaunchedFromHomeWidget` 호출이
  /// 일어나도록 보장. 그렇지 않으면 iOS 에선
  /// `PlatformException(-7, AppGroupId not set)` 이 떨어진다.
  void registerLaunchHandler(void Function(Uri uri) onUri) {
    () async {
      try {
        await _ensureInit();
        HomeWidget.widgetClicked.listen((uri) {
          if (uri != null) onUri(uri);
        });
        final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
        if (initial != null) onUri(initial);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[widget] registerLaunchHandler failed: $e');
        }
      }
    }();
  }
}
