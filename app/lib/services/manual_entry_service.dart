/// 사진 없는 기록 — 식단 끼니("이대로 먹었어")·뭐 먹지 추천("먹었어") 1탭 기록.
///
/// 사진·분석 없이 `status:'done'` entry 를 바로 만든다. `image_path` 는 NOT NULL 이라
/// 빈 문자열('')로 두고(`Entry.hasPhoto == false`), `source` 로 출처를 남긴다
/// ('meal_plan' | 'suggestion', 0017 의 entries_source_check).
/// 실수 방지는 confirm 대신 실행취소 스낵바 → [ManualEntryService.undo].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../providers/supabase_provider.dart';

/// 현재 시각으로 끼니(meal_slot enum) 추론. 경계 05/11/16/22.
///
/// favorites_provider 의 `_inferMealSlot` 과 같은 규칙이다.
String inferMealSlot(DateTime t) {
  final h = t.toLocal().hour;
  if (h >= 5 && h < 11) return 'breakfast';
  if (h >= 11 && h < 16) return 'lunch';
  if (h >= 16 && h < 22) return 'dinner';
  return 'late_night';
}

/// DB `meal_slot` enum 값. 식단의 'snack' 은 여기 없어서 시각으로 추론한다.
const _mealSlotEnum = {'breakfast', 'lunch', 'dinner', 'late_night'};

/// entries INSERT 행 (순수 함수 — 테스트 대상).
///
/// [planSlot] 이 breakfast/lunch/dinner(/late_night) 면 그대로, snack·null·기타면
/// [now] 로 추론. eating_type 은 snack 이면 'snack', 아니면 'meal'.
Map<String, dynamic> buildManualEntryRow({
  required String id,
  required String userId,
  required DateTime now,
  required String source,
  required String title,
  required int kcal,
  required double carbG,
  required double proteinG,
  required double fatG,
  String? planSlot,
}) {
  final slot =
      _mealSlotEnum.contains(planSlot) ? planSlot! : inferMealSlot(now);
  return {
    'id': id,
    'user_id': userId,
    'captured_at': now.toUtc().toIso8601String(),
    'image_path': '',
    'source': source,
    'status': 'done',
    'title': title.trim().isEmpty ? '푸디 추천 한 끼' : title.trim(),
    'kcal_total': kcal,
    'macros': {
      'carb_g': carbG,
      'protein_g': proteinG,
      'fat_g': fatG,
    },
    'meal_slot': slot,
    'eating_type': planSlot == 'snack' ? 'snack' : 'meal',
    'shared_with_count': 1,
  };
}

class ManualEntryException implements Exception {
  ManualEntryException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

class ManualEntryService {
  ManualEntryService(this._sb);
  final SupabaseClient _sb;

  static const _uuid = Uuid();

  /// 사진 없는 done entry 를 만들고 entryId 를 돌려준다.
  ///
  /// [source] 는 'meal_plan' | 'suggestion'. 이벤트 로깅(plan_logged·
  /// suggest_logged)은 호출하는 화면이 한다.
  Future<String> record({
    required String source,
    required String title,
    required int kcal,
    required double carbG,
    required double proteinG,
    required double fatG,
    String? planSlot,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw ManualEntryException('로그인이 필요해');
    final id = _uuid.v4();
    try {
      await _sb.from('entries').insert(buildManualEntryRow(
            id: id,
            userId: user.id,
            now: DateTime.now(),
            source: source,
            title: title,
            kcal: kcal,
            carbG: carbG,
            proteinG: proteinG,
            fatG: fatG,
            planSlot: planSlot,
          ));
    } catch (e) {
      throw ManualEntryException('기록 못 했어. 잠깐 뒤에 다시 해볼래?', cause: e);
    }
    return id;
  }

  /// 실행취소 — 사진이 없으니 entries 행만 지운다.
  Future<void> undo(String entryId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    await _sb.from('entries').delete().eq('id', entryId).eq('user_id', user.id);
  }
}

final manualEntryServiceProvider = Provider<ManualEntryService>((ref) {
  return ManualEntryService(ref.watch(supabaseClientProvider));
});
