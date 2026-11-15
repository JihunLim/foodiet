import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/entries_provider.dart';

Map<String, dynamic> _row({String imagePath = 'u/e.jpg', Object? feedback}) => {
      'id': 'e1',
      'user_id': 'u1',
      'captured_at': '2026-11-16T03:00:00Z',
      'image_path': imagePath,
      'status': 'done',
      'shared_with_count': 1,
      'kcal_total': 600,
      'feedback': feedback,
    };

void main() {
  test('사진 없는 기록은 hasPhoto=false', () {
    expect(Entry.fromJson(_row(imagePath: '')).hasPhoto, isFalse);
    expect(Entry.fromJson(_row()).hasPhoto, isTrue);
  });

  test('feedback null 이면 null', () {
    expect(Entry.fromJson(_row()).feedback, isNull);
  });

  test('정상 feedback 파싱', () {
    final e = Entry.fromJson(_row(feedback: {
      'headline': '단백질 좋아',
      'good': '닭가슴살이 들어갔네.',
      'next': '다음엔 채소 한 줌 더해보자.',
      'check': {
        'kind': 'rice',
        'question': '밥은 얼마나 먹었어?',
        'options': [
          {'label': '다 먹었어', 'kcal_factor': 1.0, 'sodium_factor': 1.0},
          {'label': '반 공기', 'kcal_factor': 0.5, 'sodium_factor': 1},
        ],
      },
    }));
    final f = e.feedback!;
    expect(f.headline, '단백질 좋아');
    expect(f.good, '닭가슴살이 들어갔네.');
    expect(f.next, '다음엔 채소 한 줌 더해보자.');
    expect(f.check!.options.length, 2);
    expect(f.check!.options[1].kcalFactor, 0.5);
    expect(f.check!.options[1].sodiumFactor, 1.0);
    expect(f.check!.answered, isNull);
  });

  test('잘못된 타입이면 예외 없이 null', () {
    expect(Entry.fromJson(_row(feedback: {'headline': 3})).feedback, isNull);
    expect(Entry.fromJson(_row(feedback: 'oops')).feedback, isNull);
  });

  test("check.kind 'none' 이면 check null", () {
    final e = Entry.fromJson(_row(feedback: {
      'headline': 'h',
      'good': 'g',
      'next': 'n',
      'check': {'kind': 'none', 'question': '', 'options': []},
    }));
    expect(e.feedback, isNotNull);
    expect(e.feedback!.check, isNull);
  });
}
