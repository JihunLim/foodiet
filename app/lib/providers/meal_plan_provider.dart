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

/// 백그라운드 식단 생성 상태. 폼은 바로 닫고, 식단추천 탭이 generating 동안
/// "푸디가 만들고 있어요" 를 보여준 뒤 완료되면 plan 을 표시한다.
class MealPlanGenState {
  const MealPlanGenState({this.generating = false, this.error});
  final bool generating;
  final String? error;
}

/// 생성을 폼/시트와 분리해 돌린다. autoDispose 아님 — 시트를 닫거나 탭이
/// 리빌드돼도 생성이 계속 살아 있어야 함.
class MealPlanGenerator extends Notifier<MealPlanGenState> {
  @override
  MealPlanGenState build() => const MealPlanGenState();

  Future<void> start({
    required List<String> allergies,
    required String allergyNotes,
    required List<String> ingredients,
    required String ingredientNotes,
    required List<String> cuisineStyles,
    required List<String> mealSlots,
  }) async {
    if (state.generating) return;
    state = const MealPlanGenState(generating: true);
    final svc = ref.read(mealPlanServiceProvider);
    try {
      await svc.generate(
        allergies: allergies,
        allergyNotes: allergyNotes,
        ingredients: ingredients,
        ingredientNotes: ingredientNotes,
        cuisineStyles: cuisineStyles,
        mealSlots: mealSlots,
      );
      ref.invalidate(thisWeekMealPlanProvider);
      state = const MealPlanGenState();
    } catch (_) {
      // 클라 요청이 타임아웃돼도 서버는 계속 생성 중일 수 있다(7일치 상세 생성은
      // ~80s, 최악 ~150s). edge 한도(150s)를 덮도록 폴링해 plan 이 들어오면 성공
      // 처리, 끝내 없으면 에러. (성공 경로에선 위 await 가 끝나 폴링은 안 탄다.)
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        try {
          final plan = await svc.fetchThisWeek();
          if (plan != null) {
            ref.invalidate(thisWeekMealPlanProvider);
            state = const MealPlanGenState();
            return;
          }
        } catch (_) {/* keep polling */}
      }
      state = const MealPlanGenState(
          error: '식단을 만드는 데 실패했어. 잠시 후 다시 시도해줘.');
    }
  }

  void reset() => state = const MealPlanGenState();
}

final mealPlanGeneratorProvider =
    NotifierProvider<MealPlanGenerator, MealPlanGenState>(
        MealPlanGenerator.new);
