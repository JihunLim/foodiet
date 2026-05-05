/// FCM (Firebase Cloud Messaging) 클라이언트 통합.
///
/// 기획안 §12 / §18.1 #11.
///
/// 책임:
///   1. 알림 권한 요청 (iOS 첫 실행 시 1회).
///   2. FCM 토큰 획득 + Supabase `device_tokens` 테이블에 upsert.
///   3. 토큰 refresh 구독 — SDK 가 주기적으로 토큰을 갱신.
///   4. foreground 메시지 수신 시 앱 안에서 가벼운 배너 표시.
///   5. 알림 탭 (앱이 닫힌 상태 / 백그라운드) → 해당 스크린으로 딥링크.
///
/// 백그라운드 handler 는 top-level 함수여야 해서 `main.dart` 에서 선언.
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  FcmService(this._client, {required this.packageVersion});

  final SupabaseClient _client;
  final String packageVersion;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// 루트 Navigator 의 GlobalKey — 알림 탭 라우팅 + 포그라운드 배너 표시용.
  /// main.dart 에서 주입.
  GoRouter? router;
  GlobalKey<ScaffoldMessengerState>? messengerKey;

  /// 앱 부팅 후 한 번 호출. 로그인 전에도 안전 (토큰 업로드는 skip).
  /// 로그인된 뒤에는 [refreshAfterSignIn] 을 불러 DB 에 토큰을 기록.
  Future<void> init({
    required GoRouter router,
    required GlobalKey<ScaffoldMessengerState> messengerKey,
  }) async {
    this.router = router;
    this.messengerKey = messengerKey;
    try {
      final messaging = FirebaseMessaging.instance;

      // 권한 요청은 여기서 하지 않는다 — 앱 부팅 즉시 시스템 다이얼로그가
      // 떠서 온보딩 흐름이 깨지기 때문. 온보딩 권한 화면의 "알림" 카드가
      // permission_handler 로 요청하면 그때 iOS 가 동일 대상(UNUserNotificationCenter)
      // 에 대해 한 번만 다이얼로그를 띄운다.
      //
      // 포그라운드 중에도 iOS 가 시스템 배너를 띄우도록. 권한 여부와 무관하게
      // 안전하게 호출 가능.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // 앱이 푸시 탭으로 콜드 스타트된 경우.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

      // 토큰 refresh — SDK 가 바꿀 때마다 DB 에 재업로드.
      _tokenRefreshSub =
          messaging.onTokenRefresh.listen((t) => _upsertToken(t));
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] init failed: $e');
    }
  }

  /// 로그인 직후 호출. 현재 기기의 FCM 토큰을 `device_tokens` 에 upsert.
  Future<void> refreshAfterSignIn() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      // APNs token 이 set 되기를 짧게 기다린 뒤 FCM token 을 받는다.
      // iOS 에서 getToken() 이 APNs binding 없는 채로 반환되면 FCM 은 200
      // OK 응답을 주지만 실제 APNs deliver 가 silent drop 된다.
      String? apns;
      for (int i = 0; i < 8 && apns == null; i++) {
        apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _upsertToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] refreshAfterSignIn failed: $e');
    }
  }

  /// 로그아웃 전에 호출. 이 기기의 토큰을 삭제해 이전 사용자 앞으로 푸시가
  /// 더 이상 가지 않도록 한다.
  Future<void> clearOnSignOut() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _client.from('device_tokens').delete().eq('token', token);
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] clearOnSignOut failed: $e');
    }
  }

  // ─── 내부 ────────────────────────────────────────────────────────────

  Future<void> _upsertToken(String token) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'web';
    await _client.from('device_tokens').upsert(
      {
        'token': token,
        'user_id': user.id,
        'platform': platform,
        'app_version': packageVersion,
        'locale': WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'token',
    );
  }

  void _handleForeground(RemoteMessage msg) {
    // 시스템 배너는 iOS 에선 위의 presentation option 으로, Android 에선 채널
    // 설정으로 알아서 뜬다. 여기선 in-app 스낵바로 보조 피드백만.
    final messenger = messengerKey?.currentState;
    final notif = msg.notification;
    if (messenger == null || notif == null) return;
    final title = notif.title ?? '';
    final body = notif.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty)
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        action: _routeFromData(msg.data) == null
            ? null
            : SnackBarAction(
                label: '열기',
                onPressed: () => _handleTap(msg),
              ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _handleTap(RemoteMessage msg) {
    final path = _routeFromData(msg.data);
    if (path == null) return;
    try {
      router?.go(path);
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] navigate failed: $e');
    }
  }

  /// 알림 payload 의 `route` 또는 `kind` 에서 앱 내 경로를 결정.
  /// 예시 payload:
  ///   { "route": "/home" }
  ///   { "kind": "coach_daily" }   → /home
  ///   { "kind": "entry_done", "entry_id": "abc" }  → /entry/abc
  String? _routeFromData(Map<String, dynamic> data) {
    final explicit = data['route'] as String?;
    if (explicit != null && explicit.startsWith('/')) return explicit;

    final kind = data['kind'] as String?;
    switch (kind) {
      case 'coach_daily':
      case 'coach_weekly':
      case 'meal_reminder':
        return '/home';
      case 'entry_done':
      case 'entry_failed':
        final id = data['entry_id'] as String?;
        return (id != null && id.isNotEmpty) ? '/entry/$id' : '/home';
      case 'insight_weekly':
        return '/insight';
    }
    return null;
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
