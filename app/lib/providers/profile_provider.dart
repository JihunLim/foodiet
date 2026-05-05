/// 현재 사용자의 프로필 프로바이더.
///
/// 로그인 안 됨 또는 profiles row 없음 → null.
/// null 이면 라우터가 onboarding survey 로 보냄.
///
/// Phase F (MVP 완성도 개선):
///   - 편집 화면이 쓰는 전체 필드를 포함하도록 확장.
///     (height_cm, weight_kg, goal_deadline, activity_level, diet_restrictions,
///      birth_date, sex)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kcal_calc.dart';
import 'auth_provider.dart';
import 'supabase_provider.dart';

class AppProfile {
  const AppProfile({
    required this.userId,
    required this.nickname,
    required this.locale,
    required this.unitEnergy,
    required this.unitMass,
    this.dailyKcalTarget,
    this.goalWeightKg,
    this.heightCm,
    this.weightKg,
    this.goalDeadline,
    this.activityLevel,
    this.dietRestrictions = const [],
    this.birthDate,
    this.sex,
  });

  final String userId;
  final String nickname;
  final String locale;
  final String unitEnergy; // 'kcal' | 'kJ'
  final String unitMass;   // 'kg' | 'lb'
  final int? dailyKcalTarget;
  final double? goalWeightKg;
  final double? heightCm;
  final double? weightKg;
  final DateTime? goalDeadline;
  final int? activityLevel; // 1~5
  final List<String> dietRestrictions;
  final DateTime? birthDate;
  final Sex? sex;

  factory AppProfile.fromJson(Map<String, dynamic> j) => AppProfile(
        userId: j['user_id'] as String,
        nickname: j['nickname'] as String,
        locale: (j['locale'] as String?) ?? 'ko',
        unitEnergy: (j['unit_energy'] as String?) ?? 'kcal',
        unitMass: (j['unit_mass'] as String?) ?? 'kg',
        dailyKcalTarget: j['daily_kcal_target'] as int?,
        goalWeightKg: (j['goal_weight_kg'] as num?)?.toDouble(),
        heightCm: (j['height_cm'] as num?)?.toDouble(),
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        goalDeadline: j['goal_deadline'] == null
            ? null
            : DateTime.tryParse(j['goal_deadline'] as String),
        activityLevel: (j['activity_level'] as num?)?.toInt(),
        dietRestrictions: (j['diet_restrictions'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        birthDate: j['birth_date'] == null
            ? null
            : DateTime.tryParse(j['birth_date'] as String),
        sex: _parseSex(j['sex'] as String?),
      );

  static Sex? _parseSex(String? v) {
    if (v == null) return null;
    switch (v) {
      case 'male':
        return Sex.male;
      case 'female':
        return Sex.female;
      default:
        return null;
    }
  }
}

final profileProvider = FutureProvider<AppProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final client = ref.watch(supabaseClientProvider);
  final row = await client
      .from('profiles')
      .select(
        'user_id, nickname, locale, unit_energy, unit_mass, '
        'daily_kcal_target, goal_weight_kg, height_cm, weight_kg, '
        'goal_deadline, activity_level, diet_restrictions, '
        'birth_date, sex',
      )
      .eq('user_id', user.id)
      .maybeSingle();
  if (row == null) return null;
  return AppProfile.fromJson(row);
});
