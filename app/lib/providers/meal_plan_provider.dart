/// 식단 추천 프로바이더.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/meal_plan_service.dart';
import 'supabase_provider.dart';

final mealPlanServiceProvider = Provider<MealPlanService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MealPlanService(client);
});

/// 이번 주 plan. 없으면 null.
final thisWeekMealPlanProvider =
    FutureProvider.autoDispose<MealPlan?>((ref) async {
  final svc = ref.watch(mealPlanServiceProvider);
  return svc.fetchThisWeek();
});
