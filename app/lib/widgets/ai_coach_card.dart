/// 홈 상단 AI 가이드 카드.
///
/// `homeCoachProvider` 를 구독해서 현재 시각·오늘 섭취 현황에 맞춘 식단 조언을
/// 부드러운 카드 형태로 렌더한다. 로딩/에러는 자체 스켈레톤·톤다운 문구로 처리.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/home_coach_provider.dart';
import '../theme/foodiet_tokens.dart';
import 'science_citations_sheet.dart';

class AiCoachCard extends ConsumerWidget {
  const AiCoachCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeCoachProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp16, FoodietShape.sp16, FoodietShape.sp16, FoodietShape.sp8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FoodietColors.coral50, FoodietColors.cream50],
        ),
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.coral100),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          async.when(
            data: (advice) => _CoachBody(advice: advice),
            loading: () => const _CoachLoading(),
            error: (_, __) => const _CoachError(),
          ),
          // 의료 면책 + 출처 링크 (App Store guideline 1.4.1).
          // 푸디의 오늘 가이드는 일반적인 영양·칼로리 가이드라인 기반의 권고이고,
          // 의학적 조언이 아니라는 사실 + 산출 근거 출처를 사용자가 곧바로 확인 가능.
          const SizedBox(height: FoodietShape.sp8),
          const Divider(height: 1, color: FoodietColors.coral100),
          InkWell(
            onTap: () => showScienceCitationsSheet(context),
            borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu_book_rounded,
                      size: 14, color: FoodietColors.warm500),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '의학적 조언이 아니야 · 산출 근거 보기',
                      style: FoodietText.caption.copyWith(
                        color: FoodietColors.warm500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachHeader extends StatelessWidget {
  const _CoachHeader({this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: FoodietColors.coral500,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text('🍓', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Text(
          '푸디의 오늘 가이드',
          style: FoodietText.caption.copyWith(
            color: FoodietColors.coral600,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

class _CoachBody extends StatelessWidget {
  const _CoachBody({required this.advice});
  final HomeCoachAdvice advice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CoachHeader(),
        const SizedBox(height: FoodietShape.sp12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(advice.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                advice.headline.isEmpty
                    ? '오늘도 같이 가보자 💪'
                    : advice.headline,
                style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        if (advice.review.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp8),
          Text(
            advice.review,
            style: FoodietText.bodySm.copyWith(
              color: FoodietColors.warm700,
              height: 1.45,
            ),
          ),
        ],
        if (advice.nextTip.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp12),
          Container(
            padding: const EdgeInsets.all(FoodietShape.sp12),
            decoration: BoxDecoration(
              color: FoodietColors.cream00.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🧭', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      '다음 가이드',
                      style: FoodietText.caption.copyWith(
                        color: FoodietColors.warm500,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  advice.nextTip,
                  style: FoodietText.bodySm.copyWith(
                    color: FoodietColors.warm900,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (advice.focus.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: FoodietColors.leaf500.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🌿', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    '오늘 집중: ${advice.focus}',
                    style: FoodietText.caption.copyWith(
                      color: FoodietColors.leaf500,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CoachLoading extends StatelessWidget {
  const _CoachLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CoachHeader(
          trailing: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: FoodietColors.coral500,
            ),
          ),
        ),
        SizedBox(height: FoodietShape.sp12),
        _SkeletonBar(width: double.infinity, height: 18),
        SizedBox(height: 10),
        _SkeletonBar(width: double.infinity, height: 12),
        SizedBox(height: 6),
        _SkeletonBar(width: 220, height: 12),
        SizedBox(height: 14),
        _SkeletonBar(width: 160, height: 12),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FoodietColors.cream100,
        borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      ),
    );
  }
}

class _CoachError extends StatelessWidget {
  const _CoachError();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CoachHeader(),
        const SizedBox(height: FoodietShape.sp12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '아직 분석할 식사 정보가 부족해',
                style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FoodietShape.sp8),
        Text(
          '지금 먹은 기록으로 살펴보고 있지만, 한두 끼 더 추가되면 오늘 영양 '
          '균형에 맞춘 조언을 바로 정리해서 들려줄게!',
          style: FoodietText.bodySm.copyWith(
            color: FoodietColors.warm700,
            height: 1.45,
          ),
        ),
        const SizedBox(height: FoodietShape.sp12),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: FoodietColors.coral500.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📸', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                '다음 식사 한 장만 더!',
                style: FoodietText.caption.copyWith(
                  color: FoodietColors.coral600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
