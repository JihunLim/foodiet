/// Splash — 초기 라우트 분기.
///
/// auth + profile + first-launch 플래그를 확인해 다음 중 하나로 이동:
///   • /onboarding/value       — 앱을 처음 여는 경우 (intro 미완료)
///   • /onboarding/permissions — intro 는 봤는데 권한 단계 미완료
///   • /sign-in                — 권한 단계까지 봤지만 로그인 안 됨
///   • /onboarding/survey      — 로그인됐지만 profiles row 없음
///   • /home                   — 전부 완료
///
/// 로딩 인디케이터는 기계적인 `CircularProgressIndicator` 대신 딸기 이모지가
/// 부드럽게 회전하는 애니메이션으로 대체 — 브랜드 톤을 첫 화면부터 드러냄.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/first_launch_flags.dart';
import '../../theme/foodiet_tokens.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    // 딸기 로딩 스피너 — 1회전 1.4초, 무한 반복.
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final flagsAsync = ref.watch(firstLaunchFlagsProvider);

    // 두 AsyncValue 모두 data 상태일 때만 분기.
    if (profileAsync.hasValue && flagsAsync.hasValue) {
      final profile = profileAsync.value;
      final flags = flagsAsync.value!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final user = ref.read(currentUserProvider);
        final authed = user != null;

        if (!authed) {
          if (!flags.introCompleted) {
            context.go('/onboarding/value');
          } else if (!flags.permissionsCompleted) {
            context.go('/onboarding/permissions');
          } else {
            context.go('/sign-in');
          }
          return;
        }
        if (profile == null) {
          context.go('/onboarding/survey');
        } else {
          context.go('/home');
        }
      });
    }

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spinCtrl,
              child: const Text('🍓', style: TextStyle(fontSize: 64)),
            ),
            const SizedBox(height: 14),
            Text(
              'foodiet',
              style: FoodietText.title.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
