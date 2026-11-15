/// GLP-1 투약 계획·기록 (`medication_plans` / `medication_logs`, 0017).
///
/// - [medicationPlanProvider]  : 내 투약 계획(없으면 null). 기본 꺼짐.
/// - [medicationLogsProvider]  : 최근 투약 기록(최신순).
/// - [medicationDueProvider]   : 활성 계획의 다음 투약일·D-day (홈 칩·슬롯용).
/// - [MedicationRepo]          : 저장/기록/삭제/끄기 + 로컬 알림(ID 201) 재예약.
///
/// 투약 기록·용량은 LLM 에 보내지 않는다. 서버(home-coach 등)는 plan 의
/// `active && coach_context` 만 보고 "GLP-1 사용 중" 여부만 쓴다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../services/app_events.dart';
import '../services/content_notifications.dart';
import '../services/medication_schedule.dart' hide drugLabel;
import '../services/medication_schedule.dart' as schedule show drugLabel;
import 'auth_provider.dart';
import 'supabase_provider.dart';

// ─── 모델 ─────────────────────────────────────────────────────────────────

double _num(Object? v, double fallback) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class MedicationPlan {
  const MedicationPlan({
    required this.drug,
    this.drugLabel,
    required this.currentDoseMg,
    this.intervalDays = 7,
    this.startDate,
    this.reminderEnabled = true,
    this.reminderHour = 9,
    this.active = true,
    this.coachContext = true,
  });

  /// 'wegovy' | 'mounjaro' | 'other'
  final String drug;

  /// drug == 'other' 일 때 사용자가 입력한 이름.
  final String? drugLabel;
  final double currentDoseMg;
  final int intervalDays;

  /// 로컬 날짜(00:00). 기록이 없을 때 첫 예정일.
  final DateTime? startDate;
  final bool reminderEnabled;
  final int reminderHour;
  final bool active;

  /// 푸디 조언(LLM)에 'GLP-1 사용 중' 여부만 반영할지.
  final bool coachContext;

  String get displayName => schedule.drugLabel(drug, custom: drugLabel);

  factory MedicationPlan.fromJson(Map<String, dynamic> j) {
    final drug = (j['drug'] as String?) ?? 'other';
    final start = j['start_date'];
    return MedicationPlan(
      drug: kMedicationDrugs.contains(drug) ? drug : 'other',
      drugLabel: j['drug_label'] as String?,
      currentDoseMg: _num(j['current_dose_mg'], 0),
      intervalDays: _num(j['interval_days'], 7).round().clamp(1, 60),
      startDate: start is String ? DateTime.tryParse(start) : null,
      reminderEnabled: (j['reminder_enabled'] as bool?) ?? true,
      reminderHour: _num(j['reminder_hour'], 9).round().clamp(0, 23),
      active: (j['active'] as bool?) ?? true,
      coachContext: (j['coach_context'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'drug': drug,
        'drug_label': drug == 'other' ? drugLabel?.trim() : null,
        'current_dose_mg': currentDoseMg,
        'interval_days': intervalDays,
        'start_date': startDate == null ? null : _ymd(startDate!),
        'reminder_enabled': reminderEnabled,
        'reminder_hour': reminderHour,
        'active': active,
        'coach_context': coachContext,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  MedicationPlan copyWith({bool? active}) => MedicationPlan(
        drug: drug,
        drugLabel: drugLabel,
        currentDoseMg: currentDoseMg,
        intervalDays: intervalDays,
        startDate: startDate,
        reminderEnabled: reminderEnabled,
        reminderHour: reminderHour,
        active: active ?? this.active,
        coachContext: coachContext,
      );
}

class MedicationLog {
  const MedicationLog({
    required this.id,
    required this.drug,
    this.drugLabel,
    required this.doseMg,
    required this.takenAt,
    this.site,
    this.note,
  });
  final String id;
  final String drug;
  final String? drugLabel;
  final double doseMg;

  /// 로컬 시각.
  final DateTime takenAt;

  /// 'abdomen' | 'thigh' | 'arm' | null
  final String? site;
  final String? note;

  String get displayName => schedule.drugLabel(drug, custom: drugLabel);

  factory MedicationLog.fromJson(Map<String, dynamic> j) => MedicationLog(
        id: j['id'] as String,
        drug: (j['drug'] as String?) ?? 'other',
        drugLabel: j['drug_label'] as String?,
        doseMg: _num(j['dose_mg'], 0),
        takenAt: DateTime.parse(j['taken_at'] as String).toLocal(),
        site: j['site'] as String?,
        note: j['note'] as String?,
      );
}

/// 다음 투약일 + D-day.
class MedicationDue {
  const MedicationDue({required this.due, required this.days});
  final DateTime? due;
  final int? days;
  String get label => dueLabel(days);
  bool get isToday => days == 0;
}

/// 계획 + 마지막 기록 → 다음 투약일. (순수 — 홈/화면/알림이 같은 계산을 쓴다.)
MedicationDue computeMedicationDue(
  MedicationPlan plan,
  DateTime? lastTakenLocal,
  DateTime nowLocal,
) {
  final due = nextDueDate(
    lastTakenLocal: lastTakenLocal,
    intervalDays: plan.intervalDays,
    startDateLocal: plan.startDate,
  );
  return MedicationDue(due: due, days: dueInDays(due, nowLocal));
}

// ─── 프로바이더 ───────────────────────────────────────────────────────────

/// 0017 미적용 DB(테이블 없음)인지. 이 경우만 '미설정'으로 보고, 네트워크 오류 등은
/// 에러로 올려 "기록 없음"/"미설정"으로 잘못 보이지 않게 한다.
bool _isMissingTable(Object e) =>
    e is PostgrestException && (e.code == '42P01' || e.code == 'PGRST205');

/// 내 투약 계획. 미설정이거나 0017 미적용 DB 면 null. 그 밖의 조회 실패는 에러.
final medicationPlanProvider = FutureProvider<MedicationPlan?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final client = ref.watch(supabaseClientProvider);
  try {
    final row = await client
        .from('medication_plans')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return MedicationPlan.fromJson(Map<String, dynamic>.from(row));
  } catch (e) {
    if (kDebugMode) debugPrint('[medication] plan load failed: $e');
    if (_isMissingTable(e)) return null;
    rethrow;
  }
});

/// 최근 투약 기록 (최신순, 최대 100). 조회 실패는 에러(빈 목록으로 숨기지 않는다).
final medicationLogsProvider =
    FutureProvider<List<MedicationLog>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('medication_logs')
        .select('id, drug, drug_label, dose_mg, taken_at, site, note')
        .eq('user_id', user.id)
        .order('taken_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map<MedicationLog>((r) =>
            MedicationLog.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  } catch (e) {
    if (kDebugMode) debugPrint('[medication] logs load failed: $e');
    if (_isMissingTable(e)) return const [];
    rethrow;
  }
});

/// 활성 계획의 다음 투약일. 계획이 없거나 꺼져 있거나 로딩/조회 실패면 null (홈 칩 숨김).
/// 앱이 켜진 채 자정을 넘기면 스스로 다시 계산한다(D-1 → 오늘).
final medicationDueProvider = Provider<MedicationDue?>((ref) {
  final plan = ref.watch(medicationPlanProvider).valueOrNull;
  if (plan == null || !plan.active) return null;
  final logs = ref.watch(medicationLogsProvider).valueOrNull;
  if (logs == null) return null;
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(
    nextMidnight.difference(now) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  final last = logs.isEmpty ? null : logs.first.takenAt;
  final due = computeMedicationDue(plan, last, now);
  return due.due == null ? null : due;
});

final medicationRepoProvider =
    Provider<MedicationRepo>((ref) => MedicationRepo(ref));

class MedicationException implements Exception {
  const MedicationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MedicationRepo {
  MedicationRepo(this._ref);
  final Ref _ref;

  String _uid() {
    final user = _ref.read(currentUserProvider);
    if (user == null) throw const MedicationException('로그인이 필요해.');
    return user.id;
  }

  void _invalidate() {
    _ref.invalidate(medicationPlanProvider);
    _ref.invalidate(medicationLogsProvider);
  }

  /// 계획 저장(upsert) 후 알림 재예약.
  Future<void> savePlan(MedicationPlan plan) async {
    final uid = _uid();
    final client = _ref.read(supabaseClientProvider);
    await client
        .from('medication_plans')
        .upsert(plan.toRow(uid), onConflict: 'user_id');
    _invalidate();
    await syncReminder();
  }

  /// 투약 기록 추가 후 알림 재예약.
  Future<void> logDose({
    required MedicationPlan plan,
    required double doseMg,
    required DateTime takenAtLocal,
    String? site,
    String? note,
  }) async {
    final uid = _uid();
    final client = _ref.read(supabaseClientProvider);
    final trimmed = note?.trim();
    await client.from('medication_logs').insert({
      'user_id': uid,
      'drug': plan.drug,
      'drug_label': plan.drug == 'other' ? plan.drugLabel?.trim() : null,
      'dose_mg': doseMg,
      'taken_at': takenAtLocal.toUtc().toIso8601String(),
      'site': kInjectionSites.containsKey(site) ? site : null,
      'note': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    });
    _invalidate();
    await syncReminder();
    AppEvents.log('med_logged');
  }

  Future<void> deleteLog(String id) async {
    final uid = _uid();
    final client = _ref.read(supabaseClientProvider);
    await client
        .from('medication_logs')
        .delete()
        .eq('id', id)
        .eq('user_id', uid);
    _invalidate();
    await syncReminder();
  }

  /// 투약 관리 켜기/끄기. 끄면 알림도 취소(기록은 남긴다).
  Future<void> setActive(bool active) async {
    final uid = _uid();
    final client = _ref.read(supabaseClientProvider);
    await client.from('medication_plans').update({
      'active': active,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid);
    _invalidate();
    await syncReminder();
  }

  /// DB 의 최신 계획·기록으로 다음 투약일 알림(ID 201)을 다시 건다.
  /// 계획이 없거나 꺼져 있거나 알림 off 면 취소만. 실패는 조용히 무시.
  Future<void> syncReminder() async {
    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) {
        await ContentNotifications.instance.scheduleMedication(null);
        return;
      }
      final client = _ref.read(supabaseClientProvider);
      final row = await client
          .from('medication_plans')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      final plan = row == null
          ? null
          : MedicationPlan.fromJson(Map<String, dynamic>.from(row));
      if (plan == null || !plan.active || !plan.reminderEnabled) {
        await ContentNotifications.instance.scheduleMedication(null);
        return;
      }
      final last = await client
          .from('medication_logs')
          .select('taken_at')
          .eq('user_id', user.id)
          .order('taken_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final lastAt = last == null
          ? null
          : DateTime.parse(last['taken_at'] as String).toLocal();
      final due = computeMedicationDue(plan, lastAt, DateTime.now());
      await ContentNotifications.instance
          .scheduleMedication(reminderAt(due.due, plan.reminderHour));
    } catch (e) {
      if (kDebugMode) debugPrint('[medication] reminder sync failed: $e');
    }
  }
}
