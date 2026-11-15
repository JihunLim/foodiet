import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/features/home/home_content_slot.dart';

void main() {
  HomeSlotKind pick({bool med = false, bool checkin = false, bool plan = false, bool lesson = false}) =>
      pickHomeSlot(
        medicationToday: med,
        checkinPending: checkin,
        planHasNextMeal: plan,
        hasLesson: lesson,
      );

  test('투약 당일이 가장 우선', () {
    expect(pick(med: true, checkin: true, plan: true, lesson: true),
        HomeSlotKind.medicationToday);
  });
  test('체크인 > 식단 > 레슨', () {
    expect(pick(checkin: true, plan: true, lesson: true), HomeSlotKind.checkin);
    expect(pick(plan: true, lesson: true), HomeSlotKind.plan);
    expect(pick(lesson: true), HomeSlotKind.lesson);
  });
  test('아무것도 없으면 none', () {
    expect(pick(), HomeSlotKind.none);
  });
}
