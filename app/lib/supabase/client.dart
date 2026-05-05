/// Supabase 초기화 싱글턴.
///
/// 기획안 §8.1 / §8.2 — 클라이언트는 publishable 키로 초기화하고,
/// RLS 정책에 따라 `auth.uid()` 기반으로만 데이터 접근이 허용된다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

class FoodietSupabase {
  FoodietSupabase._();

  /// 앱 부팅 시 1회 호출 (main.dart).
  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabasePublishableKey, // publishable 키를 anonKey 자리에 전달
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  static SupabaseStorageClient get storage => client.storage;

  /// 음식 사진 버킷. (§13.3)
  static const String foodPhotosBucket = 'food-photos';
}
