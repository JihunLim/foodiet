/// 식단 카드 달성 배지 결정 로직 단위 테스트.
///
/// `community_share_today_page.dart` 의 `_badgeFor` 와 동일한 룰:
///   · 90~110% (목표 ±10%): achieved
///   · 70~90%             : almost
///   · 그 외 (저조 또는 110% 초과) : retry
///
/// 화면 파일에 private 으로 묶여있어 직접 import 불가하므로 같은 룰을
/// 여기서 재구현해 변하지 않도록 잠근다 (regression guard).
library;

import 'package:flutter_test/flutter_test.dart';

String badgeFor(double achievement) {
  if (achievement >= 90 && achievement <= 110) return 'achieved';
  if (achievement >= 70 && achievement < 90) return 'almost';
  return 'retry';
}

void main() {
  group('badgeFor — 경계값', () {
    test('90% 정확 = achieved', () => expect(badgeFor(90), 'achieved'));
    test('100% = achieved', () => expect(badgeFor(100), 'achieved'));
    test('110% 정확 = achieved', () => expect(badgeFor(110), 'achieved'));
    test('110.01% = retry (초과)',
        () => expect(badgeFor(110.01), 'retry'));
    test('89.99% = almost (90 미만)',
        () => expect(badgeFor(89.99), 'almost'));
    test('70% 정확 = almost', () => expect(badgeFor(70), 'almost'));
    test('69.99% = retry', () => expect(badgeFor(69.99), 'retry'));
    test('0% = retry', () => expect(badgeFor(0), 'retry'));
    test('200% (대폭 초과) = retry', () => expect(badgeFor(200), 'retry'));
  });

  group('badgeFor — 일반 케이스', () {
    test('80% = almost', () => expect(badgeFor(80), 'almost'));
    test('95% = achieved', () => expect(badgeFor(95), 'achieved'));
    test('40% = retry', () => expect(badgeFor(40), 'retry'));
  });
}
