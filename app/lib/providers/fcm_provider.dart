/// FCM 토큰 라이프사이클을 auth 상태에 연결.
///
/// - signedIn → `refreshAfterSignIn` 으로 토큰을 Supabase 에 upsert.
/// - signedOut → `clearOnSignOut` 으로 이 기기의 토큰을 지움.
/// - userUpdated / tokenRefreshed 시에는 스킵 (과도한 쓰기 방지).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fcm_service.dart';
import 'auth_provider.dart';

/// `main.dart` 가 FcmService 인스턴스를 초기화한 뒤 이 프로바이더에 override
/// 로 주입한다. 테스트에서는 더미로 교체 가능.
final fcmServiceProvider = Provider<FcmService>((ref) {
  throw UnimplementedError(
      'fcmServiceProvider must be overridden in ProviderScope');
});

/// auth 상태 스트림을 구독해 토큰을 동기화.
/// 앱 전체 수명 동안 1개만 존재해야 하므로 autoDispose 아님.
final fcmLifecycleProvider = Provider<void>((ref) {
  final fcm = ref.watch(fcmServiceProvider);

  ref.listen(authStateProvider, (prev, next) {
    final event = next.valueOrNull?.event;
    switch (event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.initialSession:
        // 로그인된 초기 세션에도 토큰 업로드 (앱 재시작 후 자동 로그인 케이스).
        fcm.refreshAfterSignIn();
        break;
      case AuthChangeEvent.signedOut:
        fcm.clearOnSignOut();
        break;
      default:
        break;
    }
  }, fireImmediately: true);
});
