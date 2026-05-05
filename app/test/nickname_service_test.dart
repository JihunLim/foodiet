/// 닉네임 형식 검증 단위 테스트.
///
/// `validateFormat` 은 클라이언트 측 즉시 피드백 — 서버 RPC 와 동일한 정규식을
/// 적용해야 한다. (마이그레이션 0007 의 `^[가-힣a-zA-Z0-9_]{2,12}$`)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/services/nickname_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // 빈 클라이언트라도 validateFormat 은 네트워크를 안 타므로 OK.
  // 단, SupabaseClient 인스턴스는 초기화하지 않고 더미 url/key 로 만든다.
  final svc = NicknameService(
    SupabaseClient('http://localhost', 'anon'),
  );

  group('validateFormat — 길이 규칙', () {
    test('빈 문자열은 empty', () {
      final r = svc.validateFormat('');
      expect(r.isValid, false);
      expect(r.code, NicknameValidationCode.empty);
    });

    test('1자는 tooShort', () {
      final r = svc.validateFormat('a');
      expect(r.isValid, false);
      expect(r.code, NicknameValidationCode.tooShort);
    });

    test('13자는 tooLong', () {
      final r = svc.validateFormat('1234567890123');
      expect(r.isValid, false);
      expect(r.code, NicknameValidationCode.tooLong);
    });

    test('정확히 2자는 유효', () {
      final r = svc.validateFormat('ab');
      expect(r.isValid, true);
    });

    test('정확히 12자는 유효', () {
      final r = svc.validateFormat('abcdefghij12');
      expect(r.isValid, true);
    });
  });

  group('validateFormat — 문자 규칙', () {
    test('한글 OK', () {
      expect(svc.validateFormat('푸디').isValid, true);
      expect(svc.validateFormat('활발한_딸기_042').isValid, true);
    });

    test('영문 + 숫자 OK', () {
      expect(svc.validateFormat('foodie01').isValid, true);
    });

    test('언더스코어 OK', () {
      expect(svc.validateFormat('a_b').isValid, true);
    });

    test('공백 거부', () {
      final r = svc.validateFormat('a b');
      expect(r.isValid, false);
      expect(r.code, NicknameValidationCode.invalidChars);
    });

    test('이모지 거부', () {
      final r = svc.validateFormat('푸디🍓');
      expect(r.isValid, false);
      expect(r.code, NicknameValidationCode.invalidChars);
    });

    test('하이픈/마침표 거부', () {
      expect(svc.validateFormat('foo-bar').isValid, false);
      expect(svc.validateFormat('foo.bar').isValid, false);
    });

    test('한자 거부 (가-힣 외 한글 블록)', () {
      // 한자는 가-힣 범위 밖.
      expect(svc.validateFormat('漢字').isValid, false);
    });

    test('앞뒤 공백 trim 후 검사', () {
      // 공백은 비허용 문자라 자동 trim 후 평가.
      expect(svc.validateFormat('  abc  ').isValid, true);
    });
  });
}
