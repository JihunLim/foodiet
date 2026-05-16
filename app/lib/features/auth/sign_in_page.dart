/// Sign-in — Apple / Google / Kakao.
///
/// 기획안 §5.1 / §18.1 #10.
/// 각 버튼은 `AuthService` 의 네이티브 OAuth 플로우를 띄우고, 받은 id_token 을
/// Supabase 에 넘긴다. 성공 시 authStateProvider 가 갱신되어 router 가 자동 라우팅.
/// - Apple 은 iOS 에서만 노출 (Android 는 native 미지원, web OAuth 셋업 별도 필요).
/// - 로케일이 ko 가 아니거나 KAKAO_NATIVE_APP_KEY 가 없으면 Kakao 버튼 숨김.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/foodiet_tokens.dart';

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
      // 성공 시 라우터가 authStateProvider 를 받아 자동으로 /home 또는
      // /onboarding/survey 로 보낸다. 여기서는 명시 라우팅 안 함.
    } on AuthFailure catch (e) {
      if (mounted) _snack('$label — ${e.message}');
    } catch (e) {
      if (mounted) _snack('$label 로그인 중 오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: FoodietColors.warm700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final showKakao = locale == 'ko' && Env.kakaoNativeAppKey != null;
    // Apple Sign-In 은 iOS native 만 지원. Android 에서 web OAuth 활성화는
    // Apple Developer 콘솔의 Service ID 발급 등 별도 셋업이 필요해 우선 숨김.
    final showApple = Platform.isIOS;
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: FoodietShape.sp20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: FoodietShape.sp40),
                  const Center(
                    child: Text('🍓', style: TextStyle(fontSize: 64)),
                  ),
                  const SizedBox(height: FoodietShape.sp24),
                  Text('안녕, 나는 푸디야',
                      textAlign: TextAlign.center,
                      style: FoodietText.h2
                          .copyWith(color: FoodietColors.warm900)),
                  const SizedBox(height: FoodietShape.sp8),
                  Text('식단 기록, 사진 한 장이면 돼.',
                      textAlign: TextAlign.center,
                      style: FoodietText.body
                          .copyWith(color: FoodietColors.warm500)),
                  const Spacer(),
                  if (showApple) ...[
                    _ProviderButton(
                      label: 'Apple로 계속하기',
                      bg: const Color(0xFF000000),
                      fg: Colors.white,
                      icon: Icons.apple,
                      onPressed: _busy
                          ? null
                          : () => _run(auth.signInWithApple, 'Apple'),
                    ),
                    const SizedBox(height: FoodietShape.sp12),
                  ],
                  _ProviderButton(
                    label: 'Google로 계속하기',
                    bg: Colors.white,
                    fg: const Color(0xFF1F1F1F),
                    icon: Icons.g_mobiledata_rounded,
                    border: FoodietColors.cream100,
                    onPressed: _busy
                        ? null
                        : () => _run(auth.signInWithGoogle, 'Google'),
                  ),
                  if (showKakao) ...[
                    const SizedBox(height: FoodietShape.sp12),
                    _ProviderButton(
                      label: '카카오로 계속하기',
                      bg: const Color(0xFFFEE500),
                      fg: const Color(0xFF1F1F1F),
                      icon: Icons.chat_bubble_rounded,
                      onPressed: _busy
                          ? null
                          : () => _run(auth.signInWithKakao, 'Kakao'),
                    ),
                  ],
                  const SizedBox(height: FoodietShape.sp40),
                ],
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: FoodietColors.coral500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
    required this.onPressed,
    this.border,
  });
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: border == null ? null : Border.all(color: border!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Text(label,
                  style: FoodietText.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
