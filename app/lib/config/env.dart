/// 환경변수 로드 래퍼.
///
/// - `.env` 는 `flutter_dotenv` 로 런타임에 읽어들인다.
/// - 클라이언트에 담겨도 안전한 값만 포함한다 (publishable 키까지).
///   service_role 키·LLM API 키·FCM 서버 키는 Edge Function 환경변수로만 주입.
///
/// 기획안 §8.1 참고.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static Future<void> load() async {
    // .env 우선, 없으면 .env.example 을 fallback 으로 로드.
    // (개발 편의상 첫 실행에도 scaffold 가 뜨도록. 실제 값은 .env 로 덮어씀.)
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      await dotenv.load(fileName: '.env.example');
    }
  }

  static String get supabaseUrl =>
      _require('SUPABASE_URL', 'https://example.supabase.co');

  static String get supabasePublishableKey => _require(
        'SUPABASE_PUBLISHABLE_KEY',
        'sb_publishable_Lcz1dUKdgrFRPvfp3A-Ttw_U3EFm3bb',
      );

  static String get defaultLocale =>
      dotenv.maybeGet('DEFAULT_LOCALE') ?? 'ko';
  static String get defaultEnergyUnit =>
      dotenv.maybeGet('DEFAULT_UNIT_ENERGY') ?? 'kcal';
  static String get defaultMassUnit =>
      dotenv.maybeGet('DEFAULT_UNIT_MASS') ?? 'kg';

  /// Google Sign-In 의 Web Client ID.
  /// - iOS 는 GoogleService-Info.plist 의 CLIENT_ID 를 자동 사용하므로 없어도 됨.
  /// - Android 는 idToken 을 받으려면 이 값(= Firebase Auth 가 자동 생성한
  ///   "Web application" OAuth Client) 이 `serverClientId` 로 필요.
  /// placeholder 면 null 반환 → Google 버튼은 보이지만 Android 에서만 실패.
  static String? get googleWebClientId {
    final v = dotenv.maybeGet('GOOGLE_WEB_CLIENT_ID');
    if (v == null || v.isEmpty || v.startsWith('your_')) return null;
    return v;
  }

  /// Kakao Native 앱 키. 미설정(placeholder) 이면 Kakao 로그인 버튼을 숨긴다.
  static String? get kakaoNativeAppKey {
    final v = dotenv.maybeGet('KAKAO_NATIVE_APP_KEY');
    if (v == null || v.isEmpty || v.startsWith('your_')) return null;
    return v;
  }

  static String? get kakaoJsAppKey {
    final v = dotenv.maybeGet('KAKAO_JS_APP_KEY');
    if (v == null || v.isEmpty || v.startsWith('your_')) return null;
    return v;
  }

  static String _require(String key, String fallback) {
    final v = dotenv.maybeGet(key);
    if (v == null || v.isEmpty) {
      // 개발 중 .env 누락 시에도 크래시 없이 fallback으로 진행.
      // 프로덕션 빌드에서는 CI에서 반드시 .env 를 생성하도록 강제.
      return fallback;
    }
    return v;
  }
}
