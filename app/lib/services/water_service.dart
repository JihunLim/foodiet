/// 물 마시기 트래킹 서비스 — water_logs CRUD + 권장 컵 수 RPC.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class WaterRecommendation {
  const WaterRecommendation({
    required this.targetCups,
    required this.cupMl,
    required this.dailyMl,
  });
  final int targetCups;
  final int cupMl;
  final int dailyMl;
}

class WaterLog {
  const WaterLog({
    required this.logDate,
    required this.cups,
    required this.targetCups,
    required this.cupMl,
  });

  final DateTime logDate;
  final int cups;
  final int targetCups;
  final int cupMl;

  int get currentMl => cups * cupMl;
  int get targetMl => targetCups * cupMl;
  bool get achieved => cups >= targetCups;
}

class WaterService {
  WaterService(this._client);
  final SupabaseClient _client;

  Future<WaterRecommendation> recommended() async {
    final rows = await _client.rpc('recommended_water_cups');
    if (rows is List && rows.isNotEmpty) {
      final r = Map<String, dynamic>.from(rows.first as Map);
      return WaterRecommendation(
        targetCups: (r['target_cups'] as num?)?.toInt() ?? 8,
        cupMl: (r['cup_ml'] as num?)?.toInt() ?? 150,
        dailyMl: (r['daily_ml'] as num?)?.toInt() ?? 1200,
      );
    }
    return const WaterRecommendation(targetCups: 8, cupMl: 150, dailyMl: 1200);
  }

  /// 오늘 로그. 없으면 권장값으로 0 컵짜리 시드 객체 반환 (DB 에 쓰지는 않음).
  Future<WaterLog> fetchToday() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final row = await _client
        .from('water_logs')
        .select('log_date, cups, target_cups, cup_ml')
        .eq('log_date', dateStr)
        .maybeSingle();

    if (row != null) {
      return WaterLog(
        logDate: DateTime.parse(row['log_date'] as String),
        cups: (row['cups'] as num).toInt(),
        targetCups: (row['target_cups'] as num).toInt(),
        cupMl: (row['cup_ml'] as num).toInt(),
      );
    }

    final reco = await recommended();
    return WaterLog(
      logDate: DateTime(now.year, now.month, now.day),
      cups: 0,
      targetCups: reco.targetCups,
      cupMl: reco.cupMl,
    );
  }

  /// 카운트를 명시적으로 set. (증감 차이가 아니라 절대값)
  Future<void> setCups({
    required int cups,
    required int targetCups,
    required int cupMl,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _client.rpc('upsert_water_log', params: {
      'p_log_date': dateStr,
      'p_cups': cups,
      'p_target_cups': targetCups,
      'p_cup_ml': cupMl,
    });
  }
}
