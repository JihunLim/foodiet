/// 끼니 리마인더 — 디바이스 로컬 알림으로 매일 지정한 시각에 발화.
///
/// 서버 측 `daily-reminder` Edge Function (KST 20:00 catch-all) 과 별개로,
/// 사용자가 설정 화면에서 끼니별로 "ON + 시간" 을 정하면 이 서비스가
/// `flutter_local_notifications` 의 daily repeating schedule 을 등록한다.
///
/// 책임:
///   - SharedPreferences 에 prefs 영속화 (master + breakfast/lunch/dinner)
///   - Riverpod 없이도 호출 가능한 plain class — settings sheet, app boot 어디서든.
///   - prefs 가 변경되거나 앱 부팅 시 `apply()` 한 번 호출하면 OS 스케줄과
///     동기화 (cancel-all → enabled 인 슬롯만 재등록).
///   - iOS / Android 양쪽 권한은 FCM permission 흐름과 통합돼 있어 별도 요청
///     필요 없음 (이미 받아둔 알림 권한을 그대로 사용).
///
/// 의도적으로 빼둔 것:
///   - "이미 그 끼니를 기록했으면 오늘 알림 취소" — v1 에선 무조건 발화.
///     문구를 부드럽게 ("점심은 어땠어?") 만들어서 이미 기록한 사용자에게도
///     거슬리지 않도록.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

enum MealSlot { breakfast, lunch, dinner }

extension MealSlotKey on MealSlot {
  String get key {
    switch (this) {
      case MealSlot.breakfast:
        return 'breakfast';
      case MealSlot.lunch:
        return 'lunch';
      case MealSlot.dinner:
        return 'dinner';
    }
  }

  /// 사용자에게 보이는 한국어 라벨.
  String get label {
    switch (this) {
      case MealSlot.breakfast:
        return '아침';
      case MealSlot.lunch:
        return '점심';
      case MealSlot.dinner:
        return '저녁';
    }
  }

  /// notification ID — 시스템에서 같은 슬롯의 이전 스케줄을 덮어쓸 때 사용.
  /// 100 / 101 / 102 — 다른 시스템 알림 ID 와 안 겹치도록 100 대 사용.
  int get notificationId {
    switch (this) {
      case MealSlot.breakfast:
        return 100;
      case MealSlot.lunch:
        return 101;
      case MealSlot.dinner:
        return 102;
    }
  }
}

/// 한 슬롯의 ON/OFF + 시간(시·분).
class MealSlotPref {
  const MealSlotPref({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;

  MealSlotPref copyWith({bool? enabled, int? hour, int? minute}) =>
      MealSlotPref(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  Duration get timeOfDay => Duration(hours: hour, minutes: minute);

  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// 전체 끼니 리마인더 prefs.
class MealReminderPrefs {
  const MealReminderPrefs({
    required this.masterEnabled,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
  });

  final bool masterEnabled;
  final MealSlotPref breakfast;
  final MealSlotPref lunch;
  final MealSlotPref dinner;

  MealSlotPref forSlot(MealSlot s) {
    switch (s) {
      case MealSlot.breakfast:
        return breakfast;
      case MealSlot.lunch:
        return lunch;
      case MealSlot.dinner:
        return dinner;
    }
  }

  MealReminderPrefs withSlot(MealSlot s, MealSlotPref next) {
    switch (s) {
      case MealSlot.breakfast:
        return copyWith(breakfast: next);
      case MealSlot.lunch:
        return copyWith(lunch: next);
      case MealSlot.dinner:
        return copyWith(dinner: next);
    }
  }

  MealReminderPrefs copyWith({
    bool? masterEnabled,
    MealSlotPref? breakfast,
    MealSlotPref? lunch,
    MealSlotPref? dinner,
  }) =>
      MealReminderPrefs(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        breakfast: breakfast ?? this.breakfast,
        lunch: lunch ?? this.lunch,
        dinner: dinner ?? this.dinner,
      );

  /// 첫 실행 / 마이그레이션 기본값.
  static const defaults = MealReminderPrefs(
    masterEnabled: true,
    breakfast: MealSlotPref(enabled: true, hour: 8, minute: 0),
    lunch: MealSlotPref(enabled: true, hour: 12, minute: 30),
    dinner: MealSlotPref(enabled: true, hour: 19, minute: 0),
  );
}

class MealReminderService {
  MealReminderService._();
  static final MealReminderService instance = MealReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// SharedPreferences 키.
  /// 단일 master 키 + 3 슬롯 × { enabled, hour, minute }.
  static const _kMaster = 'mealReminder.master';
  static String _kSlotEnabled(MealSlot s) => 'mealReminder.${s.key}.enabled';
  static String _kSlotHour(MealSlot s) => 'mealReminder.${s.key}.hour';
  static String _kSlotMinute(MealSlot s) => 'mealReminder.${s.key}.minute';

  /// 부팅 직후 한 번 호출. 알림 채널/타임존 셋업.
  Future<void> ensureInit() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      // foodiet 은 한국 시장 우선 — 디바이스 TZ 자동 인식이 안 돼서 KST 로 고정.
      // 해외 사용자가 늘어나면 `flutter_native_timezone` 으로 디바이스 TZ 를 읽어
      // 동적으로 set 하도록 교체.
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

      const ios = DarwinInitializationSettings(
        // 권한 요청은 FCM 흐름이 이미 처리. 여기선 false 로 해서 중복 다이얼로그
        // 안 뜨게 함. 실제 발화는 같은 UNUserNotificationCenter 권한을 사용.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(iOS: ios, android: android),
      );
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[meal-reminder] init failed: $e');
    }
  }

  /// 저장된 prefs 를 읽음. 없으면 [MealReminderPrefs.defaults].
  Future<MealReminderPrefs> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    MealSlotPref readSlot(MealSlot s, MealSlotPref dflt) {
      return MealSlotPref(
        enabled: p.getBool(_kSlotEnabled(s)) ?? dflt.enabled,
        hour: p.getInt(_kSlotHour(s)) ?? dflt.hour,
        minute: p.getInt(_kSlotMinute(s)) ?? dflt.minute,
      );
    }

    return MealReminderPrefs(
      masterEnabled:
          p.getBool(_kMaster) ?? MealReminderPrefs.defaults.masterEnabled,
      breakfast:
          readSlot(MealSlot.breakfast, MealReminderPrefs.defaults.breakfast),
      lunch: readSlot(MealSlot.lunch, MealReminderPrefs.defaults.lunch),
      dinner: readSlot(MealSlot.dinner, MealReminderPrefs.defaults.dinner),
    );
  }

  /// prefs 영속화 + 시스템 스케줄 동기화.
  Future<void> savePrefs(MealReminderPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMaster, prefs.masterEnabled);
    for (final s in MealSlot.values) {
      final sp = prefs.forSlot(s);
      await p.setBool(_kSlotEnabled(s), sp.enabled);
      await p.setInt(_kSlotHour(s), sp.hour);
      await p.setInt(_kSlotMinute(s), sp.minute);
    }
    await apply(prefs);
  }

  /// OS 스케줄 동기화. cancel-all → enabled 인 슬롯만 재등록.
  Future<void> apply(MealReminderPrefs prefs) async {
    if (!_initialized) await ensureInit();
    if (!_initialized) return; // init 이 실패한 경우 (시뮬 등) 조용히 noop.

    try {
      // 모든 끼니 슬롯 ID 만 명시적으로 cancel — 다른 시스템 알림 (FCM 등)
      // 은 그대로.
      for (final s in MealSlot.values) {
        await _plugin.cancel(id: s.notificationId);
      }

      if (!prefs.masterEnabled) return;
      for (final s in MealSlot.values) {
        final sp = prefs.forSlot(s);
        if (!sp.enabled) continue;
        await _scheduleSlot(s, sp);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[meal-reminder] apply failed: $e');
    }
  }

  Future<void> _scheduleSlot(MealSlot slot, MealSlotPref sp) async {
    final next = _nextInstanceOfTime(sp.hour, sp.minute);
    final (title, body) = _copyFor(slot);

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      android: AndroidNotificationDetails(
        'meal_reminder',
        '끼니 리마인더',
        channelDescription: '아침/점심/저녁 기록 리마인더',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id: slot.notificationId,
      title: title,
      body: body,
      scheduledDate: next,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // 매일 같은 시각에 반복.
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'meal_reminder.${slot.key}',
    );
  }

  /// 오늘의 hh:mm 이 이미 지나갔으면 내일로.
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// 끼니별 문구. "이미 기록했어도 거슬리지 않게" — 부드럽게.
  (String, String) _copyFor(MealSlot s) {
    switch (s) {
      case MealSlot.breakfast:
        return ('🍳 아침은 어땠어?', '한 컷이면 오늘 첫 끼 기록 완료.');
      case MealSlot.lunch:
        return ('🍱 점심 시간이네', '뭘 먹었어? 사진 한 장이면 푸디가 분석해줄게.');
      case MealSlot.dinner:
        return ('🥗 저녁은?', '오늘 마지막 끼, 잊지 말고 한 컷 남겨두자.');
    }
  }

  /// 로그아웃 / 계정 삭제 시 모든 끼니 알림 제거.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      for (final s in MealSlot.values) {
        await _plugin.cancel(id: s.notificationId);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[meal-reminder] cancelAll failed: $e');
    }
  }

  /// iOS / Android 디버깅용 — pending 한 알림 listing.
  Future<List<PendingNotificationRequest>> debugPending() async {
    if (!_initialized) return const [];
    return _plugin.pendingNotificationRequests();
  }

  /// Android 13+ POST_NOTIFICATIONS, iOS local-notif permission 은
  /// FCM 권한 흐름이 이미 받음. 별도 함수 제공 안 함.
  bool get isIos => Platform.isIOS;
}
