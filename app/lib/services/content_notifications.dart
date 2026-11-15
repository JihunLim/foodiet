/// 콘텐츠 로컬 알림 — 주간 체크인(ID 200) · GLP-1 투약일(ID 201).
///
/// 끼니 리마인더(ID 100~102, [MealReminderService])와 같은 플러그인을 쓰되 ID 대역을
/// 나눠 서로의 cancel 이 겹치지 않게 한다. 알림 payload 는 `route:/path` 형식이며
/// 탭하면 [onRoute] 로 전달된다(main.dart 가 라우터 push 로 연결).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ContentNotifications {
  ContentNotifications._();
  static final ContentNotifications instance = ContentNotifications._();

  static const int weeklyCheckinId = 200;
  static const int medicationId = 201;
  static const String _kWeeklyEnabled = 'content.weeklyCheckin.enabled';

  /// 알림 탭 → 라우트 전달. main.dart 에서 라우터와 연결한다.
  static void Function(String route)? onRoute;

  /// 앱이 알림 탭으로 콜드 스타트된 경우의 라우트 (라우터 준비 후 1회 소비).
  static String? launchRoute;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static String? routeFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('route:')) return null;
    final r = payload.substring('route:'.length);
    return r.startsWith('/') ? r : null;
  }

  Future<void> ensureInit() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(iOS: ios, android: android),
        onDidReceiveNotificationResponse: (resp) {
          final r = routeFromPayload(resp.payload);
          if (r != null) onRoute?.call(r);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchRoute = routeFromPayload(launch!.notificationResponse?.payload);
      }
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[content-notif] init failed: $e');
    }
  }

  // ── 주간 체크인 ────────────────────────────────────────────────────

  Future<bool> weeklyCheckinEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kWeeklyEnabled) ?? true;
  }

  Future<void> setWeeklyCheckinEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWeeklyEnabled, enabled);
    await scheduleWeeklyCheckin(enabled: enabled);
  }

  /// 매주 일요일 20:00 (Asia/Seoul) "이번 주 돌아볼까?".
  Future<void> scheduleWeeklyCheckin({required bool enabled}) async {
    if (!_initialized) await ensureInit();
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: weeklyCheckinId);
      if (!enabled) return;
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
      final daysToSunday = (DateTime.sunday - now.weekday) % 7;
      at = at.add(Duration(days: daysToSunday));
      if (!at.isAfter(now)) at = at.add(const Duration(days: 7));
      await _plugin.zonedSchedule(
        id: weeklyCheckinId,
        title: '🌿 이번 주 돌아볼까?',
        body: '잘한 거 하나, 다음 주에 해볼 거 하나. 푸디랑 2분이면 돼.',
        scheduledDate: at,
        notificationDetails: _details('weekly_checkin', '주간 체크인'),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'route:/weekly-checkin',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[content-notif] weekly failed: $e');
    }
  }

  // ── 투약 ───────────────────────────────────────────────────────────

  /// 다음 투약 예정 시각(로컬)에 1회. null 이거나 이미 지났으면 취소만.
  Future<void> scheduleMedication(DateTime? dueAtLocal) async {
    if (!_initialized) await ensureInit();
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: medicationId);
      if (dueAtLocal == null) return;
      final at = tz.TZDateTime(tz.local, dueAtLocal.year, dueAtLocal.month,
          dueAtLocal.day, dueAtLocal.hour, dueAtLocal.minute);
      if (!at.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        id: medicationId,
        title: '💉 오늘은 투약 예정일이야',
        body: '맞았으면 기록해두자. 일정 관리는 푸디가 도와줄게.',
        scheduledDate: at,
        notificationDetails: _details('medication', '투약 알림'),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'route:/medication',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[content-notif] medication failed: $e');
    }
  }

  /// 로그아웃 / 계정 삭제 시.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: weeklyCheckinId);
      await _plugin.cancel(id: medicationId);
    } catch (_) {/* ignore */}
  }

  NotificationDetails _details(String channelId, String channelName) =>
      NotificationDetails(
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
}
