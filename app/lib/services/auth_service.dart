/// OAuth 로그인 서비스.
///
/// 기획안 §5.1 / §18.1 #10.
/// 각 provider 의 네이티브 SDK 가 id_token 을 돌려주면 Supabase 의
/// `signInWithIdToken()` 으로 세션을 만든다. 브라우저 리다이렉트 없음.
///
/// 이 파일은 네이티브 config 가 들어오지 않은 상태에서도 컴파일되어야 해서
/// 모든 호출부를 try/catch 로 감싸고, 실패 시 [AuthFailure] 를 던진다.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AuthFailure($message)';
}

class AuthService {
  AuthService(this._sb);

  final SupabaseClient _sb;

  // ── Apple ─────────────────────────────────────────────────────────
  Future<AuthResponse> signInWithApple() async {
    try {
      final raw = _randomNonce();
      final hashed = _sha256(raw);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashed,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw AuthFailure('Apple 자격증명에 identityToken 이 없어');
      }

      return _sb.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: raw,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      throw AuthFailure('Apple 로그인 취소 또는 실패: ${e.message}', cause: e);
    } catch (e) {
      throw AuthFailure('Apple 로그인 실패', cause: e);
    }
  }

  // ── Google ────────────────────────────────────────────────────────
  Future<AuthResponse> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        // serverClientId 는 Android 에서 idToken 을 받기 위해 필요.
        // iOS 는 GoogleService-Info.plist 의 CLIENT_ID 를 자동 사용.
        // .env 의 GOOGLE_WEB_CLIENT_ID 가 비어 있으면 null 로 전달되어
        // iOS 는 그대로 동작, Android 는 idToken 이 null 로 떨어진다.
        serverClientId: Env.googleWebClientId,
        scopes: const ['email', 'profile', 'openid'],
      );

      final account = await googleSignIn.signIn();
      if (account == null) {
        throw AuthFailure('Google 로그인 취소됨');
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if (idToken == null) {
        throw AuthFailure('Google idToken 이 null — serverClientId 설정 확인');
      }

      return _sb.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('Google 로그인 실패', cause: e);
    }
  }

  // ── Kakao ─────────────────────────────────────────────────────────
  Future<AuthResponse> signInWithKakao() async {
    try {
      // 카카오톡 설치돼 있으면 앱으로, 없으면 카카오계정 로그인(웹뷰).
      final installed = await kakao.isKakaoTalkInstalled();
      final token = installed
          ? await _loginWithKakaoTalkOrAccount()
          : await kakao.UserApi.instance.loginWithKakaoAccount();

      final idToken = token.idToken;
      if (idToken == null) {
        throw AuthFailure(
          'Kakao id_token 이 null — 콘솔에서 OpenID Connect 활성화 필요',
        );
      }

      return _sb.auth.signInWithIdToken(
        provider: OAuthProvider.kakao,
        idToken: idToken,
        accessToken: token.accessToken,
      );
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('Kakao 로그인 실패', cause: e);
    }
  }

  Future<kakao.OAuthToken> _loginWithKakaoTalkOrAccount() async {
    try {
      return await kakao.UserApi.instance.loginWithKakaoTalk();
    } catch (e) {
      // 카톡 있어도 사용자가 취소·오류나면 계정 로그인으로 폴백.
      if (kDebugMode) debugPrint('[auth] kakaoTalk failed, fallback: $e');
      return kakao.UserApi.instance.loginWithKakaoAccount();
    }
  }

  // ── 공용 유틸 ──────────────────────────────────────────────────────
  static String _randomNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    return crypto.sha256.convert(bytes).toString();
  }
}
