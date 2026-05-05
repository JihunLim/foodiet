/// Supabase 인증 상태 프로바이더.
///
/// - `authStateProvider` : AuthState 스트림
/// - `currentUserProvider` : 현재 세션의 User? (없으면 null)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/home_widget_service.dart';
import 'supabase_provider.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  final stream = ref.watch(supabaseClientProvider).auth.onAuthStateChange;
  // 로그아웃/세션 만료 시 홈스크린 위젯을 빈 상태로 리셋.
  return stream.map((state) {
    if (state.event == AuthChangeEvent.signedOut) {
      FoodietWidgetService.instance.clear();
    }
    return state;
  });
});

final currentUserProvider = Provider<User?>((ref) {
  // 스트림 변경 시 이 Provider 도 재빌드되도록 watch.
  ref.watch(authStateProvider);
  return ref.read(supabaseClientProvider).auth.currentUser;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});
