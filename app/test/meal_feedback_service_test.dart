import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/entries_provider.dart';
import 'package:foodiet/services/meal_feedback_service.dart';

const _half = CheckOption(label: '반 공기', kcalFactor: 0.5, sodiumFactor: 0.3);
const _all = CheckOption(label: '다 먹었어', kcalFactor: 1.0, sodiumFactor: 1.0);

FeedbackCheck _check({String? answered}) => FeedbackCheck(
      kind: 'rice',
      question: '밥은 얼마나 먹었어?',
      options: const [_all, _half],
      answered: answered,
    );

void main() {
  test('factor 0.5 → kcal·탄단지·당은 kcalFactor, 나트륨은 sodiumFactor', () {
    final r = applyCheckAnswer(
      macros: {
        'carb_g': 80.0,
        'protein_g': 20,
        'fat_g': 15.5,
        'sodium_mg': 1000,
        'sugar_g': 7.4,
      },
      kcalTotal: 600,
      items: const [],
      check: _check(),
      option: _half,
    )!;
    expect(r.kcalTotal, 300);
    expect(r.macros!['protein_g'], 10.0);
    expect(r.macros!['carb_g'], 40.0);
    expect(r.macros!['fat_g'], 7.8); // 7.75 → 소수 1자리
    expect(r.macros!['sugar_g'], 3.7);
    expect(r.macros!['sodium_mg'], 300);
    expect(r.macros!['sodium_mg'], isA<int>());
  });

  test('이미 answered 면 null (두 번째 탭 무시)', () {
    final r = applyCheckAnswer(
      macros: {'protein_g': 20},
      kcalTotal: 600,
      items: const [],
      check: _check(answered: '다 먹었어'),
      option: _half,
    );
    expect(r, isNull);
  });

  test('items 각각 스케일 — id·이름 유지, null 은 null', () {
    final r = applyCheckAnswer(
      macros: null,
      kcalTotal: 700,
      items: [
        {
          'id': 'i1',
          'name': '밥',
          'kcal': 300,
          'carb_g': 65.0,
          'protein_g': 6.0,
          'fat_g': 0.6,
          'sodium_mg': 5,
          'sugar_g': null,
          'qty_g': 210.0,
        },
        {
          'id': 'i2',
          'name': '제육볶음',
          'kcal': 401,
          'carb_g': 12.0,
          'protein_g': 30.0,
          'fat_g': 25.0,
          'sodium_mg': 1200,
          'sugar_g': 9.0,
        },
      ],
      check: _check(),
      option: _half,
    )!;
    expect(r.macros, isNull);
    expect(r.kcalTotal, 350);
    expect(r.items, hasLength(2));
    final a = r.items[0];
    expect(a['id'], 'i1');
    expect(a['name'], '밥');
    expect(a['kcal'], 150);
    expect(a['carb_g'], 32.5);
    expect(a['fat_g'], 0.3);
    expect(a['sodium_mg'], 2); // 5*0.3=1.5 → 2
    expect(a['sugar_g'], isNull);
    expect(a['qty_g'], 210.0); // 양(g)은 스펙 범위 밖 — 그대로
    final b = r.items[1];
    expect(b['kcal'], 201); // 200.5 → 201
    expect(b['protein_g'], 15.0);
    expect(b['sodium_mg'], 360);
    expect(b['sugar_g'], 4.5);
  });

  test('kcalTotal null 이면 null 유지, 숫자 아닌 macros 키는 보존', () {
    final r = applyCheckAnswer(
      macros: {'protein_g': 10, 'note': 'x'},
      kcalTotal: null,
      items: const [],
      check: _check(),
      option: _half,
    )!;
    expect(r.kcalTotal, isNull);
    expect(r.macros!['protein_g'], 5.0);
    expect(r.macros!['note'], 'x');
  });

  test('factor 1.0 이면 값 변화 없음 (isNoop)', () {
    final r = applyCheckAnswer(
      macros: {'protein_g': 10},
      kcalTotal: 500,
      items: const [
        {'id': 'i1', 'kcal': 500}
      ],
      check: _check(),
      option: _all,
    )!;
    expect(r.isNoop, isTrue);
    expect(r.kcalTotal, 500);
    expect(r.items.single['kcal'], 500);
  });

  test('answeredFeedbackJson 은 check.answered 만 더한다', () {
    final f = MealFeedback(
      headline: '단백질 좋아',
      good: '닭가슴살이 들어갔네.',
      next: '다음엔 채소 한 줌 더해보자.',
      check: _check(),
    );
    final j = answeredFeedbackJson(f, _half);
    final check = j['check'] as Map<String, dynamic>;
    expect(check['answered'], '반 공기');
    expect(check['kind'], 'rice');
    expect((check['options'] as List), hasLength(2));
    expect(j['headline'], '단백질 좋아');
    // 원본은 그대로.
    expect(f.check!.answered, isNull);
  });
}
