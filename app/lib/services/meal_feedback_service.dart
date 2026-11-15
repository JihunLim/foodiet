/// 한 끼 피드백의 1탭 보정 — "밥은 얼마나 먹었어?" 같은 질문에 답하면
/// entry 의 kcal·영양소와 각 entry_items 를 비율로 조정한다.
///
/// 스펙 F1. 한 번만 적용된다(재탭 불가, 그 뒤 수정은 기존 수정 시트).
///
/// 저장 순서: entries(조건부: 아직 answered 없을 때만) → entry_items →
/// corrections → app_events. entry_items 저장이 끊기면 entries·이미 바꾼
/// items 를 원래 값으로 되돌린다(best-effort).
library;

import 'package:flutter/foundation.dart';
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

/// entry_items 에서 보정 대상 컬럼.
const _itemCols = 'id, kcal, carb_g, protein_g, fat_g, sodium_mg, sugar_g';
const _itemWritable = ['kcal', 'carb_g', 'protein_g', 'fat_g', 'sodium_mg', 'sugar_g'];

Map<String, dynamic> _writable(Map<String, dynamic> row) => {
      for (final k in _itemWritable)
        if (row.containsKey(k)) k: row[k],
    };

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

  Future<CheckAnswerResult> _answer(Entry entry, MealFeedback feedback,
      FeedbackCheck check, CheckOption option) async {
    // EntryItem 모델엔 sodium/sugar 가 없어서 원본 행을 직접 읽는다.
    final rawItems = (await _client
            .from('entry_items')
            .select(_itemCols)
            .eq('entry_id', entry.id) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    final scaled = applyCheckAnswer(
      macros: entry.macros,
      kcalTotal: entry.kcalTotal,
      items: rawItems,
      check: check,
      option: option,
    );
    if (scaled == null) return CheckAnswerResult.alreadyAnswered;

    // 1) entries — 아직 answered 가 없을 때만 (서버 측 중복 방지).
    final updated = await _client
        .from('entries')
        .update({
          if (!scaled.isNoop) 'kcal_total': scaled.kcalTotal,
          if (!scaled.isNoop) 'macros': scaled.macros,
          'feedback': answeredFeedbackJson(feedback, option),
        })
        .eq('id', entry.id)
        .isFilter('feedback->check->>answered', null)
        .select('id');
    if ((updated as List).isEmpty) return CheckAnswerResult.alreadyAnswered;

    // 2) entry_items — 하나라도 끊기면 전부 되돌린다.
    if (!scaled.isNoop) {
      final done = <Map<String, dynamic>>[];
      try {
        for (var i = 0; i < scaled.items.length; i++) {
          final id = scaled.items[i]['id'];
          await _client
              .from('entry_items')
              .update(_writable(scaled.items[i]))
              .eq('id', id as Object);
          done.add(rawItems[i]);
        }
      } catch (e) {
        await _rollback(entry, feedback, done);
        rethrow;
      }
    }

    // 3) corrections — 학습 데이터. 실패해도 보정 자체는 유지.
    try {
      await _client.from('corrections').insert({
        'entry_id': entry.id,
        'user_id': entry.userId,
        'field': 'check:${check.kind}',
        'before_val': {
          'kcal_total': entry.kcalTotal,
          'macros': entry.macros,
        },
        'after_val': {
          'kcal_total': scaled.kcalTotal,
          'macros': scaled.macros,
          'answer': option.label,
          'kcal_factor': option.kcalFactor,
          'sodium_factor': option.sodiumFactor,
        },
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[meal-feedback] corrections insert: $e');
    }

    await AppEvents.log('check_answered', {
      'kind': check.kind,
      'label': option.label,
      'kcal_factor': option.kcalFactor,
    });
    return CheckAnswerResult.applied;
  }

  /// best-effort 원복. 여기서 또 끊기면 값이 반쯤 바뀐 채 남을 수 있다.
  Future<void> _rollback(Entry entry, MealFeedback feedback,
      List<Map<String, dynamic>> itemsDone) async {
    try {
      for (final orig in itemsDone) {
        await _client
            .from('entry_items')
            .update(_writable(orig))
            .eq('id', orig['id'] as Object);
      }
      await _client.from('entries').update({
        'kcal_total': entry.kcalTotal,
        'macros': entry.macros,
        'feedback': feedback.toJson(),
      }).eq('id', entry.id);
    } catch (e) {
      if (kDebugMode) debugPrint('[meal-feedback] rollback: $e');
    }
  }
}
