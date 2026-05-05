/// 홈 화면 AI 가이드 카드 프로바이더.
///
/// `home-coach` Edge Function 을 호출해서 현재 시각·오늘 섭취 현황에 맞춘
/// 식단 조언을 받아온다. 완료(`status=='done'`)된 엔트리 수 또는 누적 kcal
/// 이 바뀔 때만 재호출 (pending 중간상태로는 호출하지 않음).
///
/// LLM 비용은 서버에서 통제한다: `coach_messages` 에 결과를 캐시하고 하루 5회
/// 호출을 넘으면 최신 캐시를 그대로 돌려준다. 따라서 클라이언트 쪽에는
/// 수동 새로고침 수단을 두지 않는다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'entries_provider.dart';
import 'supabase_provider.dart';

class HomeCoachAdvice {
  const HomeCoachAdvice({
    required this.emoji,
    required this.headline,
    required this.review,
    required this.nextTip,
    required this.focus,
  });

  final String emoji;
  final String headline;
  final String review;
  final String nextTip;
  final String focus;

  factory HomeCoachAdvice.fromJson(Map<String, dynamic> j) => HomeCoachAdvice(
        emoji: (j['emoji'] as String?)?.trim().isNotEmpty == true
            ? j['emoji'] as String
            : '🍓',
        headline: ((j['headline'] as String?) ?? '').trim(),
        review: ((j['review'] as String?) ?? '').trim(),
        nextTip: ((j['next_tip'] as String?) ?? '').trim(),
        focus: ((j['focus'] as String?) ?? '').trim(),
      );
}

/// 완료된 엔트리 시그니처. `done` 상태 엔트리 수 + 1인분 환산 kcal 합.
/// 이 값이 바뀔 때만 코치 프로바이더가 재실행된다.
class _DoneSignature {
  const _DoneSignature(this.doneCount, this.kcalSum);
  final int doneCount;
  final int kcalSum;

  @override
  bool operator ==(Object other) =>
      other is _DoneSignature &&
      other.doneCount == doneCount &&
      other.kcalSum == kcalSum;

  @override
  int get hashCode => Object.hash(doneCount, kcalSum);
}

final AutoDisposeFutureProvider<HomeCoachAdvice> homeCoachProvider =
    FutureProvider.autoDispose<HomeCoachAdvice>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw StateError('not signed in');
  }

  // `select` 로 done 시그니처만 구독 — pending 상태 변화로는 재호출 안 됨.
  ref.watch(todayEntriesProvider.select((async) {
    final list = async.valueOrNull ?? const <Entry>[];
    final done = list.where((e) => e.status == 'done');
    final kcal =
        done.fold<int>(0, (acc, e) => acc + (e.kcalPerPerson ?? 0));
    return _DoneSignature(done.length, kcal);
  }));

  final client = ref.watch(supabaseClientProvider);
  final FunctionResponse resp;
  try {
    // 최신 세션의 access_token 을 명시적으로 Authorization 헤더에 실어
    // 보낸다 (SDK 가 publishable key 를 대신 보내는 케이스 방어).
    final session = client.auth.currentSession;
    final headers = <String, String>{};
    if (session?.accessToken != null) {
      headers['Authorization'] = 'Bearer ${session!.accessToken}';
    }
    // 디바이스의 로컬 타임존 offset (분) 을 함께 전달. 서버는 이 값을 검증해서
    // '오늘' 경계와 저녁(18시) 게이트를 사용자 현지 시각 기준으로 계산한다.
    // 전달이 없거나 유효하지 않으면 서버가 한국(+540) 으로 폴백.
    resp = await client.functions.invoke(
      'home-coach',
      headers: headers,
      body: {
        'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
      },
    );
  } on FunctionException catch (e) {
    if (kDebugMode) {
      debugPrint('[home-coach] status=${e.status} details=${e.details}');
    }
    throw StateError('coach unavailable (${e.status}): ${e.details}');
  }

  final data = resp.data;
  Map<String, dynamic>? map;
  if (data is Map) {
    map = Map<String, dynamic>.from(data);
  } else if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map) {
      map = Map<String, dynamic>.from(decoded);
    }
  }
  if (map == null || map['error'] != null) {
    if (kDebugMode) {
      debugPrint('[home-coach] error body: $data');
    }
    throw StateError('coach unavailable: $data');
  }
  return HomeCoachAdvice.fromJson(map);
});
