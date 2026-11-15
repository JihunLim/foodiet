/// "뭐 먹지?" — `meal-suggest` Edge Function 호출 + 응답 파싱.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

enum SuggestSituation { home, convenience, delivery, eatingOut, hoesik }

extension SuggestSituationX on SuggestSituation {
  String get key => switch (this) {
        SuggestSituation.home => 'home',
        SuggestSituation.convenience => 'convenience',
        SuggestSituation.delivery => 'delivery',
        SuggestSituation.eatingOut => 'eating_out',
        SuggestSituation.hoesik => 'hoesik',
      };
  String get label => switch (this) {
        SuggestSituation.home => '🏠 집밥',
        SuggestSituation.convenience => '🏪 편의점',
        SuggestSituation.delivery => '🛵 배달',
        SuggestSituation.eatingOut => '🍜 외식',
        SuggestSituation.hoesik => '🍻 회식',
      };
}

class SuggestOption {
  const SuggestOption({
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.why,
    required this.tip,
  });
  final String name;
  final int kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
  final String why;
  final String tip;

  static SuggestOption? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    double d(Object? v) => v is num ? v.toDouble() : 0;
    return SuggestOption(
      name: name.trim(),
      kcal: (raw['kcal'] is num) ? (raw['kcal'] as num).round() : 0,
      proteinG: d(raw['protein_g']),
      carbG: d(raw['carb_g']),
      fatG: d(raw['fat_g']),
      why: (raw['why'] as String?)?.trim() ?? '',
      tip: (raw['tip'] as String?)?.trim() ?? '',
    );
  }
}

/// 일반 상황 → [options] 채움. 회식 → [hoesik] 채움.
class SuggestResult {
  const SuggestResult({
    required this.intro,
    this.remainingKcal,
    this.options = const [],
    this.hoesik,
  });
  final String intro;
  final int? remainingKcal;
  final List<SuggestOption> options;
  final HoesikGuide? hoesik;

  bool get isHoesik => hoesik != null;

  static SuggestResult? fromJson(Map<String, dynamic> j) {
    final intro = (j['intro'] as String?)?.trim() ?? '';
    if (j['kind'] == 'hoesik') {
      List<String> list(Object? v) => v is List
          ? v.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
          : const [];
      return SuggestResult(
        intro: intro,
        hoesik: HoesikGuide(
          before: list(j['before']),
          orderTips: list(j['order_tips']),
          drinkTips: list(j['drink_tips']),
          nextDay: list(j['next_day']),
        ),
      );
    }
    final opts = (j['options'] as List? ?? const [])
        .map(SuggestOption.fromJson)
        .whereType<SuggestOption>()
        .toList();
    if (opts.isEmpty && intro.isEmpty) return null;
    return SuggestResult(
      intro: intro,
      remainingKcal: (j['remaining_kcal'] as num?)?.round(),
      options: opts,
    );
  }
}

class HoesikGuide {
  const HoesikGuide({
    required this.before,
    required this.orderTips,
    required this.drinkTips,
    required this.nextDay,
  });
  final List<String> before;
  final List<String> orderTips;
  final List<String> drinkTips;
  final List<String> nextDay;
}

class SuggestRateLimited implements Exception {
  const SuggestRateLimited();
}

class MealSuggestService {
  MealSuggestService(this._client);
  final SupabaseClient _client;

  Future<SuggestResult> suggest(SuggestSituation situation) async {
    final session = _client.auth.currentSession;
    final headers = <String, String>{};
    if (session?.accessToken != null) {
      headers['Authorization'] = 'Bearer ${session!.accessToken}';
    }
    final FunctionResponse resp;
    try {
      resp = await _client.functions.invoke(
        'meal-suggest',
        headers: headers,
        body: {
          'situation': situation.key,
          'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
        },
      );
    } on FunctionException catch (e) {
      if (e.status == 429) throw const SuggestRateLimited();
      rethrow;
    }
    Object? data = resp.data;
    if (data is String) data = jsonDecode(data);
    if (data is! Map) throw StateError('meal-suggest: bad response');
    final map = Map<String, dynamic>.from(data);
    if (map['error'] == 'rate_limited') throw const SuggestRateLimited();
    final parsed = SuggestResult.fromJson(map);
    if (parsed == null) throw StateError('meal-suggest: empty');
    return parsed;
  }
}
