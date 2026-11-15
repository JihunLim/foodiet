import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/services/meal_suggest_service.dart';

void main() {
  test('일반 상황 옵션 파싱 — 이름 없는 항목은 버린다', () {
    final r = SuggestResult.fromJson({
      'kind': 'options',
      'intro': '남은 700kcal 안에서 골라봐',
      'remaining_kcal': 700,
      'options': [
        {'name': '삼각김밥+삶은달걀', 'kcal': 380.4, 'protein_g': 18, 'carb_g': 50, 'fat_g': 9, 'why': '단백질', 'tip': '컵라면은 빼자'},
        {'name': '', 'kcal': 100},
        'oops',
      ],
    })!;
    expect(r.isHoesik, isFalse);
    expect(r.remainingKcal, 700);
    expect(r.options.length, 1);
    expect(r.options.first.kcal, 380);
    expect(r.options.first.proteinG, 18.0);
  });

  test('회식 가이드 파싱', () {
    final r = SuggestResult.fromJson({
      'kind': 'hoesik',
      'intro': '오늘 회식이구나',
      'before': ['점심은 단백질 위주로'],
      'order_tips': ['구이류 먼저'],
      'drink_tips': ['물 한 잔씩 번갈아'],
      'next_day': ['굶지 말고 평소처럼'],
    })!;
    expect(r.isHoesik, isTrue);
    expect(r.hoesik!.nextDay, ['굶지 말고 평소처럼']);
    expect(r.options, isEmpty);
  });

  test('빈 응답은 null', () {
    expect(SuggestResult.fromJson({'kind': 'options', 'options': []}), isNull);
  });
}
