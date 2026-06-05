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
import 'meal_detail_page.dart';
import 'meal_plan_citations_sheet.dart';
import 'meal_plan_form_sheet.dart';
import 'water_tracker_card.dart';

class MealPlanTab extends ConsumerWidget {
  const MealPlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(thisWeekMealPlanProvider);
    final gen = ref.watch(mealPlanGeneratorProvider);

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
          if (gen.generating)
            const _GeneratingPlan()
          else if (gen.error != null)
            _GenErrorPlan(message: gen.error!)
          else
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
            style: FoodietText.bodySm.copyWith(
                color: FoodietColors.warm500, height: 1.5),
          ),
          const SizedBox(height: FoodietShape.sp16),
          PrimaryButton(
            label: '식단짜기',
            onPressed: () => showMealPlanFormSheet(context),
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

/// 백그라운드 생성 중 — "푸디가 만들고 있어요".
class _GeneratingPlan extends StatelessWidget {
  const _GeneratingPlan();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp24),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        children: [
          const Text('🍳', style: TextStyle(fontSize: 44)),
          const SizedBox(height: FoodietShape.sp12),
          Text('푸디가 열심히 식단을 만들고 있어요',
              textAlign: TextAlign.center,
              style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('30초 정도 걸려. 다 만들어지면 여기에 바로 보여줄게.',
              textAlign: TextAlign.center,
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: FoodietShape.sp16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 6,
              color: FoodietColors.coral500,
              backgroundColor: FoodietColors.cream100,
            ),
          ),
        ],
      ),
    );
  }
}

/// 백그라운드 생성 실패 — 재시도.
class _GenErrorPlan extends ConsumerWidget {
  const _GenErrorPlan({required this.message});
  final String message;
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
          const Center(child: Text('😢', style: TextStyle(fontSize: 40))),
          const SizedBox(height: FoodietShape.sp12),
          Text(message,
              textAlign: TextAlign.center,
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm700, height: 1.5)),
          const SizedBox(height: FoodietShape.sp16),
          PrimaryButton(
            label: '다시 시도',
            onPressed: () {
              ref.read(mealPlanGeneratorProvider.notifier).reset();
              showMealPlanFormSheet(context);
            },
          ),
        ],
      ),
    );
  }
}

class _PlanContent extends ConsumerStatefulWidget {
  const _PlanContent({required this.plan});
  final MealPlan plan;

  @override
  ConsumerState<_PlanContent> createState() => _PlanContentState();
}

class _PlanContentState extends ConsumerState<_PlanContent> {
  // 요일별 상세 카드로 스크롤 이동하기 위한 키. 날짜 수만큼 한 번만 생성.
  late final List<GlobalKey> _dayKeys =
      List.generate(widget.plan.days.length, (_) => GlobalKey());

  void _scrollToDay(int index) {
    final ctx = _dayKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      alignment: 0.02, // 상단에 살짝 여백 두고 정렬.
    );
  }

  // 식단 다시 만들기 — 폼을 열면 백그라운드 생성이 시작되고, 진행/완료 표시는
  // 탭(mealPlanGeneratorProvider)이 처리한다.
  void _regenerate() {
    showMealPlanFormSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final dateFmt = DateFormat('M월 d일');
    final weekStart = plan.weekStartDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 이번 주 식단 헤더 ──
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
                  Material(
                    color: FoodietColors.coral500.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _regenerate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                size: 14, color: FoodietColors.coral500),
                            const SizedBox(width: 3),
                            Text('다시 만들기',
                                style: FoodietText.caption.copyWith(
                                    color: FoodietColors.coral500,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${dateFmt.format(weekStart)} ~ ${dateFmt.format(weekStart.add(const Duration(days: 6)))}',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500),
              ),
              // 주간 요약 — 세부 설명이므로 굵게 하지 않음.
              if (plan.weeklySummary.isNotEmpty) ...[
                const SizedBox(height: FoodietShape.sp12),
                Text(plan.weeklySummary,
                    style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900, height: 1.5)),
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
        const SizedBox(height: FoodietShape.sp12),
        // ── 주간 식단표 — 칸을 탭하면 해당 요일 상세로 스크롤 이동 ──
        _WeekTable(plan: plan, onTapDay: _scrollToDay),
        const SizedBox(height: FoodietShape.sp16),
        // ── 요일별 상세 (월~일) ──
        for (var i = 0; i < plan.days.length; i++)
          _DayCard(
            key: _dayKeys[i],
            plan: plan,
            day: plan.days[i],
          ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({super.key, required this.plan, required this.day});
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
                  style: FoodietText.caption.copyWith(
                      color: FoodietColors.warm500,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${day.totalKcal} kcal',
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.coral500,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: FoodietShape.sp8),
          ...day.meals.map((m) => _MealRow(meal: m, plan: plan)),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.plan});
  final MealPlanMeal meal;
  final MealPlan plan;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MealDetailPage(meal: meal, plan: plan),
        ),
      ),
      borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      child: Padding(
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
                    style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm700,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: FoodietColors.warm500),
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
                                style: FoodietText.caption.copyWith(
                                    color: FoodietColors.warm700)),
                          ))
                      .toList(),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                '탄 ${meal.carbG}g · 단 ${meal.proteinG}g · 지 ${meal.fatG}g',
                style: FoodietText.caption.copyWith(
                    color: FoodietColors.warm500, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 주간 식단표 — 월~일 한눈에. 칸을 탭하면 [onTapDay] 로 해당 요일 상세로 이동.
class _WeekTable extends StatelessWidget {
  const _WeekTable({required this.plan, required this.onTapDay});
  final MealPlan plan;
  final void Function(int index) onTapDay;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FoodietShape.sp16,
                FoodietShape.sp12, FoodietShape.sp16, FoodietShape.sp8),
            child: Row(
              children: [
                const Icon(Icons.calendar_view_week_rounded,
                    size: 16, color: FoodietColors.coral500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('주간 식단표',
                      style: FoodietText.bodySm.copyWith(
                          color: FoodietColors.warm900,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          for (var i = 0; i < plan.days.length; i++) ...[
            const Divider(height: 1, color: FoodietColors.cream100),
            _WeekTableRow(
              plan: plan,
              index: i,
              onTap: () => onTapDay(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekTableRow extends StatelessWidget {
  const _WeekTableRow({
    required this.plan,
    required this.index,
    required this.onTap,
  });
  final MealPlan plan;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final day = plan.days[index];
    final date = plan.weekStartDate.add(Duration(days: day.dateOffset));
    final preview = day.meals.map((m) => m.name).join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: FoodietShape.sp16, vertical: FoodietShape.sp12),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_shortWeekday(date),
                        style: FoodietText.bodySm.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                    Text(DateFormat('M/d').format(date),
                        style: FoodietText.caption.copyWith(
                            color: FoodietColors.warm500, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Text(
                  preview.isEmpty ? '식단 없음' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm700),
                ),
              ),
              const SizedBox(width: 8),
              Text('${day.totalKcal}',
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.coral500,
                      fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: FoodietColors.warm500),
            ],
          ),
        ),
      ),
    );
  }
}

String _shortWeekday(DateTime d) {
  const n = ['월', '화', '수', '목', '금', '토', '일'];
  return n[(d.weekday - 1).clamp(0, 6)];
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
