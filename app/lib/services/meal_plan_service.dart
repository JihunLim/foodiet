/// 식단 추천 서비스 — `generate-meal-plan` Edge Function 호출 + meal_plans 조회.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class MealPlanMeal {
  const MealPlanMeal({
    required this.slot,
    required this.name,
    required this.kcal,
    required this.carbG,
    required this.proteinG,
    required this.fatG,
    required this.ingredients,
    required this.recipeBrief,
  });

  final String slot; // breakfast | lunch | dinner | snack
  final String name;
  final int kcal;
  final int carbG;
  final int proteinG;
  final int fatG;
  final List<String> ingredients;
  final String recipeBrief;

  factory MealPlanMeal.fromJson(Map<String, dynamic> j) => MealPlanMeal(
        slot: (j['slot'] as String?) ?? 'breakfast',
        name: (j['name'] as String?) ?? '',
        kcal: (j['kcal'] as num?)?.toInt() ?? 0,
        carbG: (j['carb_g'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toInt() ?? 0,
        fatG: (j['fat_g'] as num?)?.toInt() ?? 0,
        ingredients: (j['ingredients'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        recipeBrief: (j['recipe_brief'] as String?) ?? '',
      );
}

class MealPlanDay {
  const MealPlanDay({
    required this.dateOffset,
    required this.label,
    required this.totalKcal,
    required this.meals,
  });

  final int dateOffset; // 0=Mon, 6=Sun
  final String label;
  final int totalKcal;
  final List<MealPlanMeal> meals;

  factory MealPlanDay.fromJson(Map<String, dynamic> j) => MealPlanDay(
        dateOffset: (j['date_offset'] as num?)?.toInt() ?? 0,
        label: (j['label'] as String?) ?? '',
        totalKcal: (j['total_kcal'] as num?)?.toInt() ?? 0,
        meals: (j['meals'] as List?)
                ?.map((m) => MealPlanMeal.fromJson(
                    Map<String, dynamic>.from(m as Map)))
                .toList() ??
            const [],
      );
}

class MealPlan {
  const MealPlan({
    required this.id,
    required this.weekStartDate,
    required this.createdAt,
    required this.sourceModel,
    required this.weeklySummary,
    required this.caveats,
    required this.days,
    required this.allergies,
    required this.allergyNotes,
    required this.ingredients,
    required this.ingredientNotes,
    required this.cuisineStyles,
    required this.mealSlots,
    required this.goalWeightKg,
    required this.currentWeightKg,
    required this.dailyKcalTarget,
    required this.activityLevel,
  });

  final String id;
  final DateTime weekStartDate; // 로컬 자정 기준
  final DateTime createdAt;
  final String sourceModel;
  final String weeklySummary;
  final List<String> caveats;
  final List<MealPlanDay> days;

  final List<String> allergies;
  final String? allergyNotes;
  final List<String> ingredients;
  final String? ingredientNotes;
  final List<String> cuisineStyles;
  final List<String> mealSlots;

  final double? goalWeightKg;
  final double? currentWeightKg;
  final int? dailyKcalTarget;
  final int? activityLevel;

  factory MealPlan.fromRow(Map<String, dynamic> row) {
    final plan = (row['plan_json'] as Map?) ?? const {};
    return MealPlan(
      id: row['id'] as String,
      weekStartDate: DateTime.parse(row['week_start_date'] as String),
      createdAt:
          DateTime.parse(row['created_at'] as String).toLocal(),
      sourceModel: (row['source_model'] as String?) ?? 'gpt',
      weeklySummary: (plan['weekly_summary'] as String?) ?? '',
      caveats: (plan['caveats'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      days: (plan['days'] as List?)
              ?.map((d) =>
                  MealPlanDay.fromJson(Map<String, dynamic>.from(d as Map)))
              .toList() ??
          const [],
      allergies:
          (row['allergies'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      allergyNotes: row['allergy_notes'] as String?,
      ingredients:
          (row['ingredients'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      ingredientNotes: row['ingredient_notes'] as String?,
      cuisineStyles: (row['cuisine_styles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      mealSlots: (row['meal_slots'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      goalWeightKg: (row['goal_weight_kg'] as num?)?.toDouble(),
      currentWeightKg: (row['current_weight_kg'] as num?)?.toDouble(),
      dailyKcalTarget: (row['daily_kcal_target'] as num?)?.toInt(),
      activityLevel: (row['activity_level'] as num?)?.toInt(),
    );
  }
}

class MealPlanAlreadyExistsException implements Exception {
  MealPlanAlreadyExistsException(this.message);
  final String message;
}

class MealPlanService {
  MealPlanService(this._client);
  final SupabaseClient _client;

  static const _select =
      'id, week_start_date, created_at, source_model, plan_json, '
      'allergies, allergy_notes, ingredients, ingredient_notes, '
      'cuisine_styles, meal_slots, goal_weight_kg, current_weight_kg, '
      'daily_kcal_target, activity_level';

  /// 이번 주 (KST 월요일) plan 1개. 없으면 null.
  Future<MealPlan?> fetchThisWeek() async {
    final now = DateTime.now();
    final mondayLocal = now.subtract(Duration(days: (now.weekday + 6) % 7));
    final dateStr =
        '${mondayLocal.year.toString().padLeft(4, '0')}-${mondayLocal.month.toString().padLeft(2, '0')}-${mondayLocal.day.toString().padLeft(2, '0')}';
    final row = await _client
        .from('meal_plans')
        .select(_select)
        .eq('week_start_date', dateStr)
        .maybeSingle();
    if (row == null) return null;
    return MealPlan.fromRow(Map<String, dynamic>.from(row));
  }

  /// Edge Function 호출로 새 plan 생성. 이번 주 이미 있으면
  /// [MealPlanAlreadyExistsException] throw.
  Future<MealPlan> generate({
    required List<String> allergies,
    required String allergyNotes,
    required List<String> ingredients,
    required String ingredientNotes,
    required List<String> cuisineStyles,
    required List<String> mealSlots,
  }) async {
    final session = _client.auth.currentSession;
    final headers = <String, String>{};
    if (session?.accessToken != null) {
      headers['Authorization'] = 'Bearer ${session!.accessToken}';
    }
    final FunctionResponse resp;
    try {
      resp = await _client.functions.invoke(
        'generate-meal-plan',
        headers: headers,
        body: {
          'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
          'allergies': allergies,
          'allergy_notes': allergyNotes,
          'ingredients': ingredients,
          'ingredient_notes': ingredientNotes,
          'cuisine_styles': cuisineStyles,
          'meal_slots': mealSlots,
        },
      );
    } on FunctionException catch (e) {
      if (e.status == 409) {
        throw MealPlanAlreadyExistsException(
            '이번 주 식단은 이미 만들었어. 다음 주에 새로 짤 수 있어.');
      }
      throw StateError('meal plan unavailable (${e.status}): ${e.details}');
    }
    final data = resp.data;
    if (data is! Map) {
      throw StateError('unexpected meal-plan response');
    }
    final id = data['id'] as String?;
    if (id == null) throw StateError('meal-plan response missing id');

    // Edge 응답은 plan_json 만 포함하므로 표준 조회로 풀 row 다시 가져옴.
    final row = await _client
        .from('meal_plans')
        .select(_select)
        .eq('id', id)
        .single();
    return MealPlan.fromRow(Map<String, dynamic>.from(row));
  }
}
