/// 한 끼 피드백의 1탭 보정 — "밥은 얼마나 먹었어?" 같은 질문에 답하면
/// entry 의 kcal·영양소와 각 entry_items 를 비율로 조정한다.
///
/// 스펙 F1. 한 번만 적용된다(재탭 불가, 그 뒤 수정은 기존 수정 시트).
///
/// 저장 순서: entries(조건부: 아직 answered 없을 때만) → entry_items →
/// corrections → app_events. entry_items 저장이 끊기면 entries·이미 바꾼
/// items 를 원래 값으로 되돌린다(best-effort).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/entries_provider.dart';
import '../providers/supabase_provider.dart';
import 'app_events.dart';

/// kcalFactor 로 스케일하는 g 단위 키 (소수 1자리).
const _gramKeys = ['carb_g', 'protein_g', 'fat_g', 'sugar_g'];

/// [applyCheckAnswer] 결과 — 저장할 새 값.
class ScaledMeal {
  const ScaledMeal({
    required this.kcalTotal,
    required this.macros,
    required this.items,
    required this.isNoop,
  });

  final int? kcalTotal;
  final Map<String, dynamic>? macros;

  /// 입력 items 의 복사본 (id·name 등 유지, kcal/g/sodium 만 스케일).
  final List<Map<String, dynamic>> items;

  /// 두 factor 가 모두 1.0 — 값은 그대로, answered 만 표시하면 된다.
  final bool isNoop;
}

double _round1(double v) => (v * 10).round() / 10;

Object? _scaleInt(Object? v, double f) => v is num ? (v * f).round() : v;
Object? _scaleG(Object? v, double f) =>
    v is num ? _round1(v.toDouble() * f) : v;

Map<String, dynamic> _scaleNutrients(
    Map<String, dynamic> src, double kcalF, double sodiumF,
    {bool withKcal = false}) {
  final out = Map<String, dynamic>.from(src);
  if (withKcal && out.containsKey('kcal')) {
    out['kcal'] = _scaleInt(out['kcal'], kcalF);
  }
  for (final k in _gramKeys) {
    if (out.containsKey(k)) out[k] = _scaleG(out[k], kcalF);
  }
  if (out.containsKey('sodium_mg')) {
    out['sodium_mg'] = _scaleInt(out['sodium_mg'], sodiumF);
  }
  return out;
}

/// 보정 답 → 새 값. 이미 답한 질문이면 null (두 번째 탭 무시).
///
/// kcal·carb/protein/fat/sugar 는 [CheckOption.kcalFactor], sodium 은
/// [CheckOption.sodiumFactor]. kcal·sodium_mg 는 정수 반올림, g 는 소수 1자리.
/// null 값과 숫자가 아닌 키는 그대로 둔다. qty_g 는 스펙 범위 밖이라 그대로.
ScaledMeal? applyCheckAnswer({
  required Map<String, dynamic>? macros,
  required int? kcalTotal,
  required List<Map<String, dynamic>> items,
  required FeedbackCheck check,
  required CheckOption option,
}) {
  if (check.answered != null) return null;
  final kf = option.kcalFactor;
  final sf = option.sodiumFactor;
  return ScaledMeal(
    kcalTotal: kcalTotal == null ? null : (kcalTotal * kf).round(),
    macros: macros == null ? null : _scaleNutrients(macros, kf, sf),
    items: [
      for (final it in items) _scaleNutrients(it, kf, sf, withKcal: true),
    ],
    isNoop: kf == 1.0 && sf == 1.0,
  );
}

/// feedback JSON 에 `check.answered = option.label` 을 더한 사본.
Map<String, dynamic> answeredFeedbackJson(
    MealFeedback feedback, CheckOption option) {
  final j = feedback.toJson();
  final check = Map<String, dynamic>.from(j['check'] as Map);
  check['answered'] = option.label;
  j['check'] = check;
  return j;
}

/// 1탭 보정 저장 결과.
enum CheckAnswerResult {
  /// 반영됨.
  applied,

  /// 이미 다른 탭/기기에서 답해 있음 — 아무것도 바꾸지 않았다.
  alreadyAnswered,
}

final mealFeedbackServiceProvider = Provider<MealFeedbackService>(
    (ref) => MealFeedbackService(ref.watch(supabaseClientProvider)));

class MealFeedbackService {
  MealFeedbackService(this._client);
  final SupabaseClient _client;

  /// 같은 entry 에 대한 동시 요청(빠른 두 번 탭) 차단.
  static final Set<String> _inFlight = {};

  /// 보정 답 저장. 네트워크 문제 등은 예외로 올린다(호출부가 스낵바).
  Future<CheckAnswerResult> answer(Entry entry, CheckOption option) async {
    final feedback = entry.feedback;
    final check = feedback?.check;
    if (feedback == null || check == null || check.answered != null) {
      return CheckAnswerResult.alreadyAnswered;
    }
    if (!_inFlight.add(entry.id)) return CheckAnswerResult.alreadyAnswered;
    try {
      return await _answer(entry, feedback, check, option);
    } finally {
      _inFlight.remove(entry.id);
    }
  }

  /// 서버 RPC `apply_check_answer` 가 entries·entry_items 스케일과 corrections
  /// 기록을 한 트랜잭션으로 처리한다(0017). factor 도 서버에 저장된 선택지 값을
  /// 쓰므로 클라이언트는 고른 label 만 보낸다. 이미 답했으면 false.
  Future<CheckAnswerResult> _answer(Entry entry, MealFeedback feedback,
      FeedbackCheck check, CheckOption option) async {
    final applied = await _client.rpc('apply_check_answer', params: {
      'p_entry_id': entry.id,
      'p_label': option.label,
    });
    if (applied != true) return CheckAnswerResult.alreadyAnswered;

    await AppEvents.log('check_answered', {
      'kind': check.kind,
      'label': option.label,
      'kcal_factor': option.kcalFactor,
    });
    return CheckAnswerResult.applied;
  }
}
