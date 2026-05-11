/// 닉네임 검증 / 변경 / 랜덤 부여 서비스.
///
/// 기획서 §2.4 — 전체 서비스에서 unique. 2~12자 한글/영문/숫자/언더스코어.
/// DB 마이그레이션 0007 의 `check_nickname_available`, `update_nickname`,
/// `assign_random_nickname` RPC 와 1:1 매핑.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/supabase_provider.dart';

/// 닉네임 형식 규칙. 서버 RPC 와 동일해야 함.
final RegExp _nicknameRegex = RegExp(r'^[가-힣a-zA-Z0-9_]{2,12}$');

class NicknameValidation {
  const NicknameValidation._({
    required this.code,
    this.message,
  });

  final NicknameValidationCode code;
  final String? message;

  static const valid = NicknameValidation._(code: NicknameValidationCode.valid);

  bool get isValid => code == NicknameValidationCode.valid;
}

enum NicknameValidationCode {
  valid,
  empty,
  tooShort,
  tooLong,
  invalidChars,
}

class NicknameUpdateResult {
  const NicknameUpdateResult._(this.error);
  final NicknameUpdateError? error;
  static const success = NicknameUpdateResult._(null);
  bool get ok => error == null;
}

enum NicknameUpdateError {
  taken,
  cooldown,
  invalidFormat,
  authRequired,
  network,
  unknown,
}

class NicknameService {
  NicknameService(this._client);

  final SupabaseClient _client;

  /// 클라이언트 측 형식 검증 (서버 호출 전 즉시 피드백).
  NicknameValidation validateFormat(String input) {
    final s = input.trim();
    if (s.isEmpty) {
      return const NicknameValidation._(
        code: NicknameValidationCode.empty,
        message: '닉네임을 입력해주세요.',
      );
    }
    if (s.length < 2) {
      return const NicknameValidation._(
        code: NicknameValidationCode.tooShort,
        message: '2자 이상 입력해주세요.',
      );
    }
    if (s.length > 12) {
      return const NicknameValidation._(
        code: NicknameValidationCode.tooLong,
        message: '12자 이하로 입력해주세요.',
      );
    }
    if (!_nicknameRegex.hasMatch(s)) {
      return const NicknameValidation._(
        code: NicknameValidationCode.invalidChars,
        message: '한글, 영문, 숫자, 언더스코어(_)만 사용할 수 있어요.',
      );
    }
    return NicknameValidation.valid;
  }

  /// 서버 RPC 로 중복 확인.
  Future<bool> isAvailable(String nickname) async {
    final result = await _client.rpc<dynamic>(
      'check_nickname_available',
      params: {'target_nickname': nickname.trim()},
    );
    return result == true;
  }

  /// 닉네임 변경. 서버에서 모든 검증 (형식 / cooldown / 중복) 수행.
  Future<NicknameUpdateResult> updateNickname(String nickname) async {
    try {
      await _client.rpc<dynamic>(
        'update_nickname',
        params: {'new_nickname': nickname.trim()},
      );
      return NicknameUpdateResult.success;
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      final msg = e.message;
      if (code == '23505' || msg.contains('nickname_taken')) {
        return const NicknameUpdateResult._(NicknameUpdateError.taken);
      }
      if (code == 'P0001' && msg.contains('cooldown')) {
        return const NicknameUpdateResult._(NicknameUpdateError.cooldown);
      }
      if (code == '22023' || msg.contains('nickname_invalid_format')) {
        return const NicknameUpdateResult._(NicknameUpdateError.invalidFormat);
      }
      if (code == '28000' || msg.contains('auth_required')) {
        return const NicknameUpdateResult._(NicknameUpdateError.authRequired);
      }
      return const NicknameUpdateResult._(NicknameUpdateError.unknown);
    } catch (_) {
      return const NicknameUpdateResult._(NicknameUpdateError.network);
    }
  }

  /// 가입 직후 — 서버에서 랜덤 닉네임을 자동 생성·할당. 결과 닉네임을 반환.
  /// `nickname_changed_at` 은 건드리지 않으므로 사용자의 첫 수동 변경은 free.
  Future<String> assignRandomNickname() async {
    final result = await _client.rpc<dynamic>('assign_random_nickname');
    if (result is String) return result;
    throw Exception('assign_random_nickname returned non-string: $result');
  }
}

final nicknameServiceProvider = Provider<NicknameService>((ref) {
  return NicknameService(ref.watch(supabaseClientProvider));
});
