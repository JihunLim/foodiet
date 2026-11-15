/// 주간 체크인 (spec F4) — 모델·주 계산·프로바이더·저장소.
///
/// * [weekStartFor] / [shouldShowCheckinPrompt] — 순수 함수 (test/weekly_checkin_test.dart).
/// * [weeklyCheckinProvider] — `weekly-checkin` Edge Function 호출. 이번 체크인 주의
///   리포트가 없으면 서버가 이때 만든다(LLM 1회). **체크인 화면에서만** watch 한다.
/// * [checkinPromptVisibleProvider] — 홈 슬롯용. LLM 을 부르지 않고 DB 만 본다
///   (안 여는 사용자에게 LLM 비용이 나가지 않도록 — spec "온디맨드").
/// * [WeeklyCheckinRepo.complete] — 실험 선택 저장 (RLS own UPDATE).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_events.dart';
import 'auth_provider.dart';
import 'supabase_provider.dart';

// ── 주 계산 (로컬 기준) ───────────────────────────────────────────────

/// 체크인이 다루는 주의 월요일(로컬, 시각 0시).
/// 일요일 17시 이후면 이번 주 월요일, 그 외(월~일 17시 전)면 지난 주 월요일.
/// 서버 `weekly-checkin/schema.ts` 의 `weekStartFor` 와 같은 규칙.
DateTime weekStartFor(DateTime localNow) {
  final sinceMonday = localNow.weekday - DateTime.monday; // 0(월) ~ 6(일)
  final back = localNow.weekday == DateTime.sunday && localNow.hour >= 17
      ? sinceMonday
      : sinceMonday + 7;
  // DateTime(y, m, d - n) 은 월/연 경계와 DST 를 알아서 처리한다.
  return DateTime(localNow.year, localNow.month, localNow.day - back);
}

/// 홈에 "이번 주 돌아보기" 를 띄우는 창: 일요일 17:00 ~ 수요일 23:59.
bool inCheckinWindow(DateTime localNow) {
  switch (localNow.weekday) {
    case DateTime.sunday:
      return localNow.hour >= 17;
    case DateTime.monday:
    case DateTime.tuesday:
    case DateTime.wednesday:
      return true;
    default:
      return false;
  }
}

/// 창 안이고, 이번 체크인 주를 아직 완료하지 않았으면 true.
/// [existing] 이 다른 주의 것이면 없는 것으로 본다. 기록 부족(insufficient)이면
/// 억지로 띄우지 않는다.
bool shouldShowCheckinPrompt(DateTime localNow, WeeklyCheckin? existing) {
  if (!inCheckinWindow(localNow)) return false;
  final ws = weekStartFor(localNow);
  if (existing == null || !_sameDay(existing.weekStart, ws)) return true;
  if (existing.insufficient) return false;
  return !existing.isCompleted;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseYmd(Object? v) {
  if (v is! String || v.length < 10) return null;
  final p = DateTime.tryParse(v.substring(0, 10));
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

// ── 모델 ──────────────────────────────────────────────────────────────

class CheckinExperiment {
  const CheckinExperiment({required this.ifThen, required this.why});
  final String ifThen;
  final String why;
}

class CheckinReport {
  const CheckinReport({
    required this.emoji,
    required this.headline,
    required this.wins,
    required this.pattern,
    required this.experiments,
    required this.note,
    this.daysLogged,
  });

  final String emoji;
  final String headline;
  final List<String> wins;
  final String pattern;
  final List<CheckinExperiment> experiments;
  final String note;
  final int? daysLogged;

  /// 잘못된 모양이면 null (예외 없음).
  static CheckinReport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final headline = raw['headline'];
    final exps = raw['experiments'];
    if (headline is! String || exps is! List) return null;
    final experiments = <CheckinExperiment>[];
    for (final x in exps) {
      if (x is! Map) continue;
      final it = x['if_then'];
      if (it is! String || it.trim().isEmpty) continue;
      final why = x['why'];
      experiments.add(CheckinExperiment(
          ifThen: it.trim(), why: why is String ? why.trim() : ''));
    }
    if (experiments.isEmpty) return null;
    final wins = raw['wins'];
    final emoji = raw['emoji'];
    final pattern = raw['pattern'];
    final note = raw['note'];
    final days = raw['days_logged'];
    return CheckinReport(
      emoji: emoji is String && emoji.trim().isNotEmpty ? emoji.trim() : '🌿',
      headline: headline.trim(),
      wins: wins is List
          ? wins.whereType<String>().map((w) => w.trim()).where((w) => w.isNotEmpty).toList()
          : const [],
      pattern: pattern is String ? pattern.trim() : '',
      experiments: experiments,
      note: note is String ? note.trim() : '',
      daysLogged: days is num ? days.toInt() : null,
    );
  }
}

class WeeklyCheckin {
  const WeeklyCheckin({
    required this.weekStart,
    this.report,
    this.chosenExperiment,
    this.completedAt,
    this.insufficient = false,
    this.headline,
    this.daysLogged,
  });

  /// 돌아보는 주의 월요일 (로컬 0시).
  final DateTime weekStart;
  final CheckinReport? report;
  final String? chosenExperiment;
  final DateTime? completedAt;

  /// 기록 2일 미만 — 서버가 LLM 없이 돌려준 결정적 응답 (저장 안 됨).
  final bool insufficient;

  /// insufficient 일 때의 고정 문구.
  final String? headline;
  final int? daysLogged;

  bool get isCompleted => completedAt != null;

  /// 함수 응답(`report`) 과 DB 행(`report_json`) 둘 다 읽는다.
  factory WeeklyCheckin.fromJson(Map<String, dynamic> j) {
    final report = CheckinReport.fromJson(j['report'] ?? j['report_json']);
    final completed = j['completed_at'];
    final chosen = j['chosen_experiment'];
    final days = j['days_logged'];
    final headline = j['headline'];
    return WeeklyCheckin(
      weekStart: _parseYmd(j['week_start']) ?? weekStartFor(DateTime.now()),
      report: report,
      chosenExperiment:
          chosen is String && chosen.trim().isNotEmpty ? chosen.trim() : null,
      completedAt:
          completed is String ? DateTime.tryParse(completed)?.toLocal() : null,
      insufficient: j['insufficient'] == true,
      headline: headline is String ? headline : null,
      daysLogged: days is num ? days.toInt() : report?.daysLogged,
    );
  }
}

class WeeklyCheckinException implements Exception {
  const WeeklyCheckinException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => 'WeeklyCheckinException($status: $message)';
}

// ── 프로바이더 ────────────────────────────────────────────────────────

/// 체크인 화면용 — 함수 호출(필요하면 서버가 리포트 생성).
final AutoDisposeFutureProvider<WeeklyCheckin> weeklyCheckinProvider =
    FutureProvider.autoDispose<WeeklyCheckin>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw const WeeklyCheckinException('not signed in');
  final client = ref.watch(supabaseClientProvider);

  final FunctionResponse resp;
  try {
    final session = client.auth.currentSession;
    resp = await client.functions.invoke(
      'weekly-checkin',
      headers: {
        if (session?.accessToken != null)
          'Authorization': 'Bearer ${session!.accessToken}',
      },
      body: {'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes},
    );
  } on FunctionException catch (e) {
    if (kDebugMode) {
      debugPrint('[weekly-checkin] status=${e.status} details=${e.details}');
    }
    throw WeeklyCheckinException('${e.details}', status: e.status);
  }

  final data = resp.data;
  Map<String, dynamic>? map;
  if (data is Map) {
    map = Map<String, dynamic>.from(data);
  } else if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map) map = Map<String, dynamic>.from(decoded);
  }
  if (map == null || map['error'] != null) {
    throw WeeklyCheckinException('bad response: $data');
  }
  final c = WeeklyCheckin.fromJson(map);
  if (!c.insufficient && c.report == null) {
    throw const WeeklyCheckinException('report missing');
  }
  return c;
});

/// 홈 슬롯용 — "이번 주 돌아보기" 를 띄울지. LLM 호출 없음.
///   창 밖 → false (쿼리도 안 함)
///   이번 주 행 있음 → 미완료면 true
///   행 없음 → 그 주 완료 기록일이 2일 이상이면 true (서버 MIN_DAYS 와 같음)
/// 오류는 false (조용히 숨김).
final AutoDisposeFutureProvider<bool> checkinPromptVisibleProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final now = DateTime.now();
  if (!inCheckinWindow(now)) return false;
  final ws = weekStartFor(now);
  final client = ref.watch(supabaseClientProvider);
  try {
    final row = await client
        .from('weekly_checkins')
        .select('week_start, completed_at, chosen_experiment')
        .eq('user_id', user.id)
        .eq('week_start', _ymd(ws))
        .maybeSingle();
    if (row != null) {
      return shouldShowCheckinPrompt(now, WeeklyCheckin.fromJson(row));
    }
    final rows = await client
        .from('entries')
        .select('captured_at')
        .eq('user_id', user.id)
        .eq('status', 'done')
        .gte('captured_at', ws.toUtc().toIso8601String())
        .lt('captured_at',
            DateTime(ws.year, ws.month, ws.day + 7).toUtc().toIso8601String());
    final days = <String>{};
    for (final r in rows) {
      final t = DateTime.tryParse(r['captured_at'] as String? ?? '');
      if (t != null) days.add(_ymd(t.toLocal()));
    }
    return days.length >= 2;
  } catch (e) {
    if (kDebugMode) debugPrint('[weekly-checkin] prompt check failed: $e');
    return false;
  }
});

// ── 저장 ──────────────────────────────────────────────────────────────

class WeeklyCheckinRepo {
  WeeklyCheckinRepo(this._ref);
  final Ref _ref;

  /// 실험 선택 → weekly_checkins UPDATE(chosen_experiment, completed_at).
  /// 행이 없으면(서버 저장 실패 등) [WeeklyCheckinException].
  Future<void> complete(DateTime weekStart, String experiment) async {
    final text = experiment.trim();
    if (text.isEmpty) {
      throw const WeeklyCheckinException('empty experiment');
    }
    final client = _ref.read(supabaseClientProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw const WeeklyCheckinException('not signed in');
    final updated = await client
        .from('weekly_checkins')
        .update({
          'chosen_experiment': text,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', uid)
        .eq('week_start', _ymd(weekStart))
        .select('week_start');
    if (updated.isEmpty) {
      throw const WeeklyCheckinException('checkin row missing');
    }
    AppEvents.log('checkin_completed', {'week_start': _ymd(weekStart)});
    _ref.invalidate(weeklyCheckinProvider);
    _ref.invalidate(checkinPromptVisibleProvider);
  }
}

final weeklyCheckinRepoProvider =
    Provider<WeeklyCheckinRepo>((ref) => WeeklyCheckinRepo(ref));
