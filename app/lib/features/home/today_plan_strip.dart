/// 홈 "오늘의 추천 식단" 칩 행 (F2).
///
/// 이번 주 식단 중 오늘(date_offset = weekday-1, 월=0) 끼니를 가로 칩으로 보여주고,
/// 지금 시각 기준 다음 끼니를 강조한다. 탭하면 식단 탭과 같은 방식으로
/// [MealDetailPage] 를 push — 거기서 "이대로 먹었어"로 1탭 기록.
/// 식단이 없거나(로딩·에러 포함) 오늘 끼니가 없으면 아무것도 그리지 않는다.
/// 홈 삽입(HomeContentSlot)은 Task 12 몫.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/meal_plan_provider.dart';
import '../../services/meal_plan_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../insight/meal_detail_page.dart';

/// 강조할 끼니 인덱스 (순수 함수 — 테스트 대상).
///
/// 간식(snack)은 강조 대상이 아니다. 지금 시각의 끼니(05 전은 아침으로 봄,
/// 11/16/22 경계)부터 그 이후 끼니 중 첫 번째. 22시 이후면 null.
int? highlightIndexFor(List<String> slots, DateTime now) {
  const order = {'breakfast': 0, 'lunch': 1, 'dinner': 2};
  final h = now.hour;
  final int current;
  if (h < 11) {
    current = 0;
  } else if (h < 16) {
    current = 1;
  } else if (h < 22) {
    current = 2;
  } else {
    return null;
  }
  for (var i = 0; i < slots.length; i++) {
    final o = order[slots[i]];
    if (o != null && o >= current) return i;
  }
  return null;
}

class TodayPlanStrip extends ConsumerWidget {
  const TodayPlanStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(thisWeekMealPlanProvider).valueOrNull;
    if (plan == null) return const SizedBox.shrink();

    final now = DateTime.now();
    // plan.weekStartDate(로컬 월요일) 기준 오늘의 offset. 홈이 일→월 자정을 넘겨
    // 지난주 plan 을 들고 있으면 7 이 돼 매칭이 없고 아무것도 안 그린다.
    final ws = plan.weekStartDate;
    final todayOffset = (DateTime(now.year, now.month, now.day)
                .difference(DateTime(ws.year, ws.month, ws.day))
                .inHours /
            24)
        .round();
    MealPlanDay? today;
    for (final d in plan.days) {
      if (d.dateOffset == todayOffset) {
        today = d;
        break;
      }
    }
    final meals = today?.meals ?? const <MealPlanMeal>[];
    if (meals.isEmpty) return const SizedBox.shrink();

    final highlight = highlightIndexFor(meals.map((m) => m.slot).toList(), now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.restaurant_menu_rounded,
                size: 16, color: FoodietColors.coral500),
            const SizedBox(width: 4),
            Text('오늘의 추천 식단',
                style:
                    FoodietText.title.copyWith(color: FoodietColors.warm700)),
            const Spacer(),
            if (today != null && today.totalKcal > 0)
              Text('${today.totalKcal} kcal',
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500)),
          ],
        ),
        const SizedBox(height: FoodietShape.sp12),
        // 고정 높이 대신 내용 높이 — 큰 글꼴(textScale)에서도 칩이 잘리지 않게.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < meals.length; i++) ...[
                if (i > 0) const SizedBox(width: FoodietShape.sp8),
                _PlanMealChip(
                  meal: meals[i],
                  highlighted: i == highlight,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MealDetailPage(meal: meals[i], plan: plan),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanMealChip extends StatelessWidget {
  const _PlanMealChip({
    required this.meal,
    required this.highlighted,
    required this.onTap,
  });
  final MealPlanMeal meal;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? Colors.white : FoodietColors.warm900;
    final sub = highlighted
        ? Colors.white.withValues(alpha: 0.85)
        : FoodietColors.warm500;
    return Material(
      color: highlighted ? FoodietColors.coral500 : FoodietColors.coral50,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_slotEmoji(meal.slot), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                  highlighted
                      ? '다음 · ${_slotLabel(meal.slot)}'
                      : _slotLabel(meal.slot),
                  style: FoodietText.caption
                      .copyWith(color: sub, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  meal.name.isEmpty ? '추천 메뉴' : meal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoodietText.bodySm
                      .copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
              ),
              if (meal.kcal > 0) ...[
                const SizedBox(width: 6),
                Text('${meal.kcal}',
                    style: FoodietText.caption.copyWith(
                        color: highlighted
                            ? Colors.white
                            : FoodietColors.coral500)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _slotEmoji(String slot) => switch (slot) {
      'breakfast' => '🍳',
      'lunch' => '🍱',
      'dinner' => '🍽️',
      'snack' => '🍎',
      _ => '🍽️',
    };

String _slotLabel(String slot) => switch (slot) {
      'breakfast' => '아침',
      'lunch' => '점심',
      'dinner' => '저녁',
      'snack' => '간식',
      _ => slot,
    };
