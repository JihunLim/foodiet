/// 인사이트 > 식단추천 탭.
///
/// - 상단: 물 마시기 트래커 (체중·성별·활동도 기반 동적 목표).
/// - 본문: 이번 주(월~일) AI 식단 카드. 없으면 큰 "식단짜기" 버튼.
/// - 하단: 의학적 조언 아님 + 산출 근거 보기 링크.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../providers/meal_plan_provider.dart';
import '../../services/meal_plan_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';
import 'meal_plan_citations_sheet.dart';
import 'meal_plan_form_sheet.dart';
import 'water_tracker_card.dart';

class MealPlanTab extends ConsumerWidget {
  const MealPlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(thisWeekMealPlanProvider);

    return RefreshIndicator(
      color: FoodietColors.coral500,
      onRefresh: () async {
        ref.invalidate(thisWeekMealPlanProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp20,
          FoodietShape.sp8,
          FoodietShape.sp20,
          FoodietShape.sp40,
        ),
        children: [
          const WaterTrackerCard(),
          const SizedBox(height: FoodietShape.sp16),
          planAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                    color: FoodietColors.coral500),
              ),
            ),
            error: (e, _) => _ErrorPlan(error: e),
            data: (plan) => plan == null
                ? const _EmptyPlan()
                : _PlanContent(plan: plan),
          ),
          const SizedBox(height: FoodietShape.sp24),
          // 의학적 조언 아님 + 산출 근거 — App Store 1.4.1 대응.
          Center(
            child: MealPlanCitationsLink(
              plan: planAsync.valueOrNull,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlan extends ConsumerWidget {
  const _EmptyPlan();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp24),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text('🥗', style: TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: FoodietShape.sp12),
          Text(
            '이번 주 식단을 짜볼까?',
            textAlign: TextAlign.center,
            style: FoodietText.title.copyWith(
                color: FoodietColors.warm900,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '목표 칼로리·알레르기·냉장고 재료를 알려주면\nAI 가 7일치 식단을 만들어줄게.',
            textAlign: TextAlign.center,
            style: FoodietText.bodySm
                .copyWith(color: FoodietColors.warm500, height: 1.5),
          ),
          const SizedBox(height: FoodietShape.sp16),
          PrimaryButton(
            label: '식단짜기',
            onPressed: () async {
              final plan = await showMealPlanFormSheet(context);
              if (plan != null) {
                ref.invalidate(thisWeekMealPlanProvider);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ErrorPlan extends StatelessWidget {
  const _ErrorPlan({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Text('식단을 불러오지 못했어: $error',
          style: FoodietText.bodySm.copyWith(color: FoodietColors.warm900)),
    );
  }
}

class _PlanContent extends StatelessWidget {
  const _PlanContent({required this.plan});
  final MealPlan plan;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('M월 d일');
    final weekStart = plan.weekStartDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(FoodietShape.sp16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [FoodietColors.coral100, FoodietColors.cream50],
            ),
            borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            boxShadow: FoodietShape.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🍱', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('이번 주 식단',
                        style: FoodietText.title.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${dateFmt.format(weekStart)} ~ ${dateFmt.format(weekStart.add(const Duration(days: 6)))}',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500),
              ),
              if (plan.weeklySummary.isNotEmpty) ...[
                const SizedBox(height: FoodietShape.sp12),
                Text(plan.weeklySummary,
                    style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w600,
                        height: 1.5)),
              ],
              if (plan.dailyKcalTarget != null) ...[
                const SizedBox(height: 6),
                Text(
                  '목표 ${plan.dailyKcalTarget} kcal/일 · ${plan.mealSlots.map(_slotLabel).join(' · ')}',
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm700),
                ),
              ],
              if (plan.caveats.isNotEmpty) ...[
                const SizedBox(height: FoodietShape.sp12),
                ...plan.caveats.map((c) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_rounded,
                              size: 14, color: FoodietColors.coral500),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(c,
                                style: FoodietText.caption.copyWith(
                                    color: FoodietColors.warm700)),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
        const SizedBox(height: FoodietShape.sp16),
        ...plan.days.map((d) => _DayCard(plan: plan, day: d)),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.plan, required this.day});
  final MealPlan plan;
  final MealPlanDay day;

  @override
  Widget build(BuildContext context) {
    final date = plan.weekStartDate.add(Duration(days: day.dateOffset));
    return Container(
      margin: const EdgeInsets.only(bottom: FoodietShape.sp12),
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(day.label.isEmpty ? _weekdayLabel(date) : day.label,
                  style: FoodietText.title.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text(DateFormat('M/d').format(date),
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500)),
              const Spacer(),
              Text('${day.totalKcal} kcal',
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.coral500,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: FoodietShape.sp8),
          ...day.meals.map((m) => _MealRow(meal: m)),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal});
  final MealPlanMeal meal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _slotColor(meal.slot).withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(FoodietShape.radiusXs),
                ),
                child: Text(_slotLabel(meal.slot),
                    style: FoodietText.caption.copyWith(
                        color: _slotColor(meal.slot),
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(meal.name,
                    style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700)),
              ),
              Text('${meal.kcal}kcal',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm700)),
            ],
          ),
          if (meal.recipeBrief.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(meal.recipeBrief,
                  style: FoodietText.caption.copyWith(
                      color: FoodietColors.warm700, height: 1.5)),
            ),
          ],
          if (meal.ingredients.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: meal.ingredients
                    .map((g) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FoodietColors.cream100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(g,
                              style: FoodietText.caption
                                  .copyWith(color: FoodietColors.warm700)),
                        ))
                    .toList(),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              '탄 ${meal.carbG}g · 단 ${meal.proteinG}g · 지 ${meal.fatG}g',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

String _slotLabel(String slot) {
  switch (slot) {
    case 'breakfast':
      return '아침';
    case 'lunch':
      return '점심';
    case 'dinner':
      return '저녁';
    case 'snack':
      return '간식';
    default:
      return slot;
  }
}

Color _slotColor(String slot) {
  switch (slot) {
    case 'breakfast':
      return FoodietColors.mealBreakfast;
    case 'lunch':
      return FoodietColors.mealLunch;
    case 'dinner':
      return FoodietColors.mealDinner;
    case 'snack':
      return FoodietColors.warm700;
    default:
      return FoodietColors.warm500;
  }
}

String _weekdayLabel(DateTime d) {
  const names = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  return names[(d.weekday - 1).clamp(0, 6)];
}
