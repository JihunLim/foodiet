/// Onboarding — 가치 제안 4장 카드.
///
/// 기획안 §5.1 — 첫 실행 사용자에게 앱의 핵심 가치를 카드 형태로 소개.
///
/// 플로우: splash → onboarding/value (여기) → onboarding/permissions → sign-in.
/// 마지막 슬라이드에서 "계속하기" 를 누르면 [FirstLaunchFlags.markIntroCompleted]
/// 를 찍고 권한 페이지로 넘어간다. 이후 로그아웃 → 재로그인 때는 이 페이지를
/// 다시 보지 않는다 (splash 가 분기).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/first_launch_flags.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class OnboardingValuePage extends ConsumerStatefulWidget {
  const OnboardingValuePage({super.key});

  @override
  ConsumerState<OnboardingValuePage> createState() =>
      _OnboardingValuePageState();
}

class _OnboardingValuePageState extends ConsumerState<OnboardingValuePage> {
  final _controller = PageController();
  int _page = 0;

  // 4장 카드. 각 카드는 (배경 틴트, 이모지, 제목, 서브, 본문) 구성.
  // 배경은 브랜드 컬러의 옅은 버전 (coral50 / leaf100 / cream50 / warm200 틴트)
  // 으로 회전시켜서 시각적 리듬을 준다.
  static const _slides = <_Slide>[
    _Slide(
      tint: FoodietColors.coral50,
      accent: FoodietColors.coral500,
      emoji: '📸',
      eyebrow: '한 장의 사진으로 시작',
      title: '사진 한 장이면\n기록 끝',
      body: '메뉴 이름도, 양도, 끼니 구분도\n전부 푸디 AI가 알아서 채워줘.',
    ),
    _Slide(
      tint: FoodietColors.leaf100,
      accent: FoodietColors.leaf700,
      emoji: '🥗',
      eyebrow: 'AI 영양 분석',
      title: '칼로리·탄단지\n한 번에',
      body: '품목별 kcal, 1인분 기준 나눔 계산,\n신뢰도까지 자동으로 분석해.',
    ),
    _Slide(
      tint: FoodietColors.cream50,
      accent: FoodietColors.mealDinner,
      emoji: '💬',
      eyebrow: '매일의 코치 푸디',
      title: '먹은 만큼\n피드백받기',
      body: '목표 칼로리 대비 오늘의 식단을\n푸디가 짧고 따뜻하게 코치해.',
    ),
    _Slide(
      tint: FoodietColors.coral100,
      accent: FoodietColors.coral700,
      emoji: '📤',
      eyebrow: '위젯 + 한 번에 공유',
      title: '친구에게 사진 한 장으로',
      body: '홈 위젯으로 남은 칼로리 확인,\n하루 식단을 카드 한 장으로 공유해.',
    ),
  ];

  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onNext() async {
    if (!_isLast) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }
    // 마지막 → intro 플래그 마킹 후 권한 페이지로.
    final flags = await ref.read(firstLaunchFlagsProvider.future);
    await flags.markIntroCompleted();
    if (!mounted) return;
    context.go('/onboarding/permissions');
  }

  Future<void> _skipAll() async {
    final flags = await ref.read(firstLaunchFlagsProvider.future);
    await flags.markIntroCompleted();
    if (!mounted) return;
    context.go('/onboarding/permissions');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // iPad 대응 — 카드가 너무 벌어지지 않도록 max 520.
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                // Skip 버튼 — 상단 우측.
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _skipAll,
                    child: Text(
                      '건너뛰기',
                      style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm500,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => _slides[i],
                  ),
                ),
                _Dots(active: _page, total: _slides.length),
                const SizedBox(height: FoodietShape.sp24),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: FoodietShape.sp20),
                  child: PrimaryButton(
                    label: _isLast ? '시작하기' : '다음',
                    onPressed: _onNext,
                  ),
                ),
                const SizedBox(height: FoodietShape.sp32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.tint,
    required this.accent,
    required this.emoji,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final Color tint;
  final Color accent;
  final String emoji;
  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: FoodietShape.sp20, vertical: FoodietShape.sp16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 이모지 카드.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: FoodietShape.sp24, vertical: FoodietShape.sp40),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(FoodietShape.radiusXl),
              boxShadow: FoodietShape.shadowCard,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 64)),
                ),
                const SizedBox(height: FoodietShape.sp20),
                Text(
                  eyebrow,
                  style: FoodietText.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FoodietShape.sp32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: FoodietText.h1.copyWith(color: FoodietColors.warm900),
          ),
          const SizedBox(height: FoodietShape.sp12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: FoodietText.body.copyWith(color: FoodietColors.warm500),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.active, required this.total});
  final int active;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: on ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: on ? FoodietColors.coral500 : FoodietColors.warm200,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
