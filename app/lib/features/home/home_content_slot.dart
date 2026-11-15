/// 홈 콘텐츠 슬롯 — AI 코치 카드 아래 **한 장만** 보여준다.
///
/// 홈을 다시 카드로 비대하게 만들지 않기 위해(6be390d 에서 의도적으로 정리)
/// 상황에 맞는 콘텐츠 1개만 고른다. 우선순위:
///   1. 오늘이 투약 예정일 (GLP-1 투약 관리를 켠 사용자)
///   2. 주간 체크인 대기 (일 17시 ~ 수, 아직 완료 전)
///   3. 오늘의 추천 식단 — 아직 남은 끼니가 있을 때
///   4. 오늘의 2분 읽기 — 코치 focus·패턴에 맞는 안 읽은 레슨
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/home_coach_provider.dart';
import '../../providers/insight_provider.dart';
import '../../providers/lessons_provider.dart';
import '../../providers/meal_plan_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/weekly_checkin_provider.dart';
import '../../services/meal_plan_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../lessons/lesson_card.dart';
import 'today_plan_strip.dart';

enum HomeSlotKind { medicationToday, checkin, plan, lesson, none }

/// 순수 우선순위 결정 (테스트용).
HomeSlotKind pickHomeSlot({
  required bool medicationToday,
  required bool checkinPending,
  required bool planHasNextMeal,
  required bool hasLesson,
}) {
  if (medicationToday) return HomeSlotKind.medicationToday;
  if (checkinPending) return HomeSlotKind.checkin;
  if (planHasNextMeal) return HomeSlotKind.plan;
  if (hasLesson) return HomeSlotKind.lesson;
  return HomeSlotKind.none;
}

class HomeContentSlot extends ConsumerWidget {
  const HomeContentSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final due = ref.watch(medicationDueProvider);
    final checkinPending =
        ref.watch(checkinPromptVisibleProvider).valueOrNull ?? false;

    final plan = ref.watch(thisWeekMealPlanProvider).valueOrNull;
    final todayMeals =
        plan == null ? const <MealPlanMeal>[] : todayPlanMeals(plan, now);
    final planHasNextMeal = todayMeals.isNotEmpty &&
        highlightIndexFor(todayMeals.map((m) => m.slot).toList(), now) != null;

    final focus = ref.watch(homeCoachProvider).valueOrNull?.focus;
    final patternKeys = ref
            .watch(insightSummaryProvider)
            .valueOrNull
            ?.patternFlags
            .map((f) => f.key)
            .toList() ??
        const <String>[];
    final lesson = ref.watch(suggestedLessonProvider(
        LessonPickArgs(coachFocus: focus, patternKeys: patternKeys)));

    final kind = pickHomeSlot(
      medicationToday: due?.isToday ?? false,
      checkinPending: checkinPending,
      planHasNextMeal: planHasNextMeal,
      hasLesson: lesson != null,
    );

    final Widget child = switch (kind) {
      HomeSlotKind.medicationToday => _PromptCard(
          emoji: '💉',
          title: '오늘은 투약 예정일이야',
          body: '맞았으면 기록해두자. 다음 일정은 푸디가 챙길게.',
          action: '기록하러 가기',
          onTap: () => context.push('/medication'),
        ),
      HomeSlotKind.checkin => _PromptCard(
          emoji: '🌿',
          title: '이번 주 돌아볼까?',
          body: '잘한 거 하나, 다음 주에 해볼 거 하나. 2분이면 돼.',
          action: '돌아보기',
          onTap: () => context.push('/weekly-checkin'),
        ),
      HomeSlotKind.plan => const TodayPlanStrip(),
      HomeSlotKind.lesson => LessonCard(lesson: lesson!),
      HomeSlotKind.none => const SizedBox.shrink(),
    };
    if (kind == HomeSlotKind.none) return child;
    return Padding(
      padding: const EdgeInsets.only(top: FoodietShape.sp16),
      child: child,
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.emoji,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(FoodietShape.sp16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            border: Border.all(color: FoodietColors.coral100),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: FoodietText.title
                            .copyWith(color: FoodietColors.warm900)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm500)),
                  ],
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Text(action,
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.coral500,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
