/// 물 마시기 프로바이더 — 오늘 로그 + 권장 컵 수.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/water_service.dart';
import 'supabase_provider.dart';

final waterServiceProvider = Provider<WaterService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return WaterService(client);
});

final waterRecommendationProvider =
    FutureProvider.autoDispose<WaterRecommendation>((ref) async {
  final svc = ref.watch(waterServiceProvider);
  return svc.recommended();
});

final todayWaterLogProvider =
    FutureProvider.autoDispose<WaterLog>((ref) async {
  final svc = ref.watch(waterServiceProvider);
  return svc.fetchToday();
});
