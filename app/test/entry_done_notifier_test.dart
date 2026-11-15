import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/entries_provider.dart';
import 'package:foodiet/providers/entry_done_notifier.dart';

Entry _e(String id, String status, {bool feedback = false}) => Entry.fromJson({
      'id': id,
      'user_id': 'u1',
      'captured_at': '2026-11-16T03:00:00Z',
      'image_path': 'u1/$id.jpg',
      'status': status,
      'shared_with_count': 1,
      'feedback': feedback
          ? {'headline': '좋아', 'good': '좋았어.', 'next': '물 한 잔 더.'}
          : null,
    });

void main() {
  test('pending → done 전환만 감지', () {
    final prev = {'a': 'pending', 'b': 'done', 'c': 'pending'};
    final next = [
      _e('a', 'done', feedback: true),
      _e('b', 'done', feedback: true),
      _e('c', 'pending'),
    ];
    final done = detectDoneTransitions(prev, next);
    expect(done.map((e) => e.id), ['a']);
  });

  test('처음 보는 entry 는 이미 done 이어도 알리지 않는다', () {
    final done = detectDoneTransitions(const {}, [_e('a', 'done')]);
    expect(done, isEmpty);
  });

  test('pending → failed 는 알리지 않는다', () {
    final done =
        detectDoneTransitions(const {'a': 'pending'}, [_e('a', 'failed')]);
    expect(done, isEmpty);
  });

  test('feedback 없는 완료도 전환으로 감지 (문구 선택은 구독자 몫)', () {
    final done =
        detectDoneTransitions(const {'a': 'pending'}, [_e('a', 'done')]);
    expect(done.single.feedback, isNull);
  });
}
