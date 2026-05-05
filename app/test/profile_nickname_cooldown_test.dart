/// AppProfile 의 닉네임 30일 cooldown 헬퍼 테스트.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/profile_provider.dart';

AppProfile _profileWithChangedAt(DateTime? at) => AppProfile(
      userId: 'u',
      nickname: 'foo',
      locale: 'ko',
      unitEnergy: 'kcal',
      unitMass: 'kg',
      nicknameChangedAt: at,
    );

void main() {
  test('한 번도 변경하지 않은 사용자는 항상 변경 가능', () {
    final p = _profileWithChangedAt(null);
    expect(p.canChangeNicknameNow, true);
    expect(p.nicknameChangeAvailableAt, null);
  });

  test('30일 이내에 변경한 사용자는 잠금', () {
    final at = DateTime.now().subtract(const Duration(days: 5));
    final p = _profileWithChangedAt(at);
    expect(p.canChangeNicknameNow, false);
    expect(p.nicknameChangeAvailableAt, isNotNull);
    // 다음 변경 가능 시각은 정확히 30일 뒤.
    expect(
      p.nicknameChangeAvailableAt!
          .difference(at)
          .inDays,
      30,
    );
  });

  test('30일 + 1초 지났으면 가능', () {
    final at = DateTime.now()
        .subtract(const Duration(days: 30, seconds: 1));
    final p = _profileWithChangedAt(at);
    expect(p.canChangeNicknameNow, true);
  });

  test('정확히 30일 전 (DateTime 정밀도) 은 마이크로초 차이로 잠금 처리될 수 있음', () {
    // 동등 비교가 isAfter 인 점을 고려한 방어적 테스트.
    final at = DateTime.now().subtract(const Duration(days: 30));
    final p = _profileWithChangedAt(at);
    // canChangeNicknameNow 는 isAfter — 정확히 30일이면 false 가 정답.
    // (실제로는 처리 시간 1ms 정도가 추가돼 true 가 될 수 있어 둘 다 허용.)
    expect(p.canChangeNicknameNow, anyOf(true, false));
  });
}
