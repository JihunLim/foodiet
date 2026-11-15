import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/features/home/today_plan_strip.dart';
import 'package:foodiet/services/manual_entry_service.dart';

Map<String, dynamic> _row({
  String? planSlot,
  required DateTime now,
  String source = 'meal_plan',
}) =>
    buildManualEntryRow(
      id: 'e1',
      userId: 'u1',
      now: now,
      source: source,
      title: '닭가슴살 샐러드',
      kcal: 450,
      carbG: 30,
      proteinG: 35,
      fatG: 12.5,
      planSlot: planSlot,
    );

void main() {
  group('buildManualEntryRow', () {
    test('plan slot lunch → meal_slot lunch, eating_type meal', () {
      final r = _row(planSlot: 'lunch', now: DateTime(2026, 11, 16, 9));
      expect(r['meal_slot'], 'lunch');
      expect(r['eating_type'], 'meal');
    });

    test('snack at 15:00 → meal_slot lunch, eating_type snack', () {
      final r = _row(planSlot: 'snack', now: DateTime(2026, 11, 16, 15));
      expect(r['meal_slot'], 'lunch');
      expect(r['eating_type'], 'snack');
    });

    test('snack at 23:00 → late_night', () {
      final r = _row(planSlot: 'snack', now: DateTime(2026, 11, 16, 23));
      expect(r['meal_slot'], 'late_night');
    });

    test('plan slot wins over clock (breakfast logged at 20:00)', () {
      final r = _row(planSlot: 'breakfast', now: DateTime(2026, 11, 16, 20));
      expect(r['meal_slot'], 'breakfast');
      expect(r['eating_type'], 'meal');
    });

    test('null planSlot at 08:00 → breakfast, meal', () {
      final r = _row(now: DateTime(2026, 11, 16, 8));
      expect(r['meal_slot'], 'breakfast');
      expect(r['eating_type'], 'meal');
    });

    test('photo-less done row with source, macros, shared 1', () {
      final now = DateTime(2026, 11, 16, 12, 30);
      final r = _row(planSlot: 'lunch', now: now);
      expect(r['id'], 'e1');
      expect(r['user_id'], 'u1');
      expect(r['image_path'], '');
      expect(r['source'], 'meal_plan');
      expect(r['status'], 'done');
      expect(r['shared_with_count'], 1);
      expect(r['title'], '닭가슴살 샐러드');
      expect(r['kcal_total'], 450);
      expect(r['macros'], {'carb_g': 30.0, 'protein_g': 35.0, 'fat_g': 12.5});
      expect(r['captured_at'], now.toUtc().toIso8601String());
    });

    test('suggestion source passes through', () {
      final r = _row(source: 'suggestion', now: DateTime(2026, 11, 16, 18));
      expect(r['source'], 'suggestion');
      expect(r['meal_slot'], 'dinner');
    });
  });

  group('inferMealSlot', () {
    test('boundaries 05/11/16/22', () {
      expect(inferMealSlot(DateTime(2026, 1, 1, 4, 59)), 'late_night');
      expect(inferMealSlot(DateTime(2026, 1, 1, 5)), 'breakfast');
      expect(inferMealSlot(DateTime(2026, 1, 1, 10, 59)), 'breakfast');
      expect(inferMealSlot(DateTime(2026, 1, 1, 11)), 'lunch');
      expect(inferMealSlot(DateTime(2026, 1, 1, 16)), 'dinner');
      expect(inferMealSlot(DateTime(2026, 1, 1, 22)), 'late_night');
    });
  });

  group('highlightIndexFor', () {
    const slots = ['breakfast', 'lunch', 'snack', 'dinner'];

    test('morning highlights breakfast', () {
      expect(highlightIndexFor(slots, DateTime(2026, 1, 1, 8)), 0);
    });

    test('before 05 still points at breakfast', () {
      expect(highlightIndexFor(slots, DateTime(2026, 1, 1, 3)), 0);
    });

    test('13:00 highlights lunch', () {
      expect(highlightIndexFor(slots, DateTime(2026, 1, 1, 13)), 1);
    });

    test('17:00 highlights dinner (skips snack)', () {
      expect(highlightIndexFor(slots, DateTime(2026, 1, 1, 17)), 3);
    });

    test('after 22:00 nothing highlighted', () {
      expect(highlightIndexFor(slots, DateTime(2026, 1, 1, 22, 30)), isNull);
    });

    test('missing current slot falls to next later meal', () {
      expect(
          highlightIndexFor(
              const ['breakfast', 'dinner'], DateTime(2026, 1, 1, 12)),
          1);
    });
  });
}
