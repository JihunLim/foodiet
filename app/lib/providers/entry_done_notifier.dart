/// 오늘 기록의 분석 완료(pending → done) 감지.
///
/// 스펙 F1 — 앱 사용 중 분석이 끝나면 인앱 스낵바("푸디 한마디 도착 ✨ [보기]")
/// 를 띄우기 위한 신호. 서버 푸시는 쓰지 않는다.
///
/// 사용법 (home_shell 등 앱 사용 내내 살아 있는 위젯):
/// ```dart
/// ref.listen<AsyncValue<Entry>>(entryDoneNotifierProvider, (_, next) {
///   next.whenData((entry) { ... /entry/${entry.id} ... });
/// });
/// ```
/// autoDispose 라 `ref.listen`/`ref.watch` 로 구독하고 있어야 감지가 유지된다
/// (`ref.read(...)` 만으로는 즉시 해제됨). 구독하는 동안 todayEntriesProvider
/// (Realtime) 와 pendingEntriesPollProvider(3초 폴백) 도 함께 살아 있다.
///
/// 피드백이 없는 완료(구서버·피드백 생성 실패)도 이벤트로 온다 →
/// "푸디 한마디" 문구는 `entry.feedback != null` 일 때만 쓰는 게 맞다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'entries_provider.dart';

/// [prevStatus] (entry id → 직전 status) 대비 [next] 에서 pending → done 으로
/// 바뀐 entry 들. 처음 보는 entry 는 이미 done 이어도 제외한다
/// (앱 시작 직후·사진 없는 1탭 기록이 알림을 띄우지 않도록).
List<Entry> detectDoneTransitions(
    Map<String, String> prevStatus, List<Entry> next) {
  return [
    for (final e in next)
      if (prevStatus[e.id] == 'pending' && e.status == 'done') e,
  ];
}

final AutoDisposeStreamProvider<Entry> entryDoneNotifierProvider =
    StreamProvider.autoDispose<Entry>((ref) {
  // 사용자 바뀌면 provider 가 다시 만들어져 상태 맵도 초기화된다.
  ref.watch(currentUserProvider);

  final controller = StreamController<Entry>();
  var lastStatus = <String, String>{};

  // Realtime 이벤트가 안 와도 pending 동안 3초 폴링이 돌도록 붙잡아 둔다.
  ref.listen<void>(pendingEntriesPollProvider, (_, __) {});

  ref.listen<AsyncValue<List<Entry>>>(
    todayEntriesProvider,
    (_, next) {
      final list = next.valueOrNull;
      if (list == null) return;
      for (final e in detectDoneTransitions(lastStatus, list)) {
        if (!controller.isClosed) controller.add(e);
      }
      lastStatus = {for (final e in list) e.id: e.status};
    },
    fireImmediately: true,
  );

  ref.onDispose(controller.close);
  return controller.stream;
});
