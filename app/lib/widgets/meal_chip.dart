/// meal_slot / eating_type 를 한 축씩 표현하는 칩.
///
/// 기획안 §7.3 · §13.5 — **두 축 혼동 방지**.
/// - `MealSlotChip` : breakfast|lunch|dinner|late_night
/// - `EatingTypeChip` : meal|snack|beverage
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/foodiet_tokens.dart';

/// 시간대 축 — 상단 배지 용도.
class MealSlotChip extends StatelessWidget {
  const MealSlotChip({super.key, required this.slot, this.capturedAt});

  /// breakfast | lunch | dinner | late_night
  final String slot;
  final DateTime? capturedAt;

  @override
  Widget build(BuildContext context) {
    final color = FoodietSemantic.mealSlotColor(slot);
    final label = _labelFor(slot);
    final timeStr = capturedAt == null
        ? null
        : DateFormat('HH:mm').format(capturedAt!.toLocal());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$label${timeStr == null ? '' : ' · $timeStr'}',
              style: FoodietText.bodySm.copyWith(
                color: FoodietColors.warm900,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  String _labelFor(String slot) {
    switch (slot) {
      case 'breakfast':  return '아침';
      case 'lunch':      return '점심';
      case 'dinner':     return '저녁';
      case 'late_night': return '야식';
      default:           return slot;
    }
  }
}

/// 식사 종류 축 — 우측 보조 칩 용도.
class EatingTypeChip extends StatelessWidget {
  const EatingTypeChip({super.key, required this.type});

  /// meal | snack | beverage
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = FoodietSemantic.eatingTypeColor(type);
    final label = _labelFor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: FoodietText.caption.copyWith(
            color: FoodietColors.warm700,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  String _labelFor(String t) {
    switch (t) {
      case 'meal':     return '식사';
      case 'snack':    return '간식';
      case 'beverage': return '음료';
      default:         return t;
    }
  }
}
