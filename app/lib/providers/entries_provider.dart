/// 오늘 타임라인 / 과거 기록 / 엔트리 상세 조회 프로바이더 + Realtime 구독.
///
/// 기획안 §4.1 / §11.
/// `entries` 테이블에서 사용자의 기록을 캡처 시각 역순으로 가져온다.
///
/// Phase C (MVP 완성도 개선):
///   - `entriesRealtimeProvider` 가 entries 테이블을 구독. 업데이트가 들어오면
///     today/recent 프로바이더를 자동 invalidate → "분석 중" 상태가 자동으로
///     최종 kcal 로 전환된다.
///   - 폴백: Realtime publication 이 비활성화되어 있거나 네트워크 문제로
///     이벤트가 안 올 때를 대비해, pending 엔트리가 하나라도 있으면
///     `pendingEntriesPollProvider` 가 3초마다 today/recent 를 invalidate.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/photo_upload_service.dart';
import 'auth_provider.dart';
import 'supabase_provider.dart';

class Entry {
  const Entry({
    required this.id,
    required this.userId,
    required this.capturedAt,
    required this.imagePath,
    required this.status,
    required this.sharedWithCount,
    this.title,
    this.note,
    this.mealSlot,
    this.eatingType,
    this.kcalTotal,
    this.macros,
    this.confidence,
  });

  final String id;
  final String userId;
  final DateTime capturedAt;
  final String imagePath;
  final String status; // pending | done | failed
  final int sharedWithCount; // 1 = 혼자. 2+ = 공유 식사.
  final String? title;
  final String? note;
  final String? mealSlot; // breakfast | lunch | dinner | late_night
  final String? eatingType; // meal | snack | beverage
  final int? kcalTotal;
  final Map<String, dynamic>? macros;
  final double? confidence;

  /// 1인분 환산 kcal. [sharedWithCount] 로 나눈 값. 합계/표시에 이걸 사용.
  int? get kcalPerPerson {
    final total = kcalTotal;
    if (total == null) return null;
    final n = sharedWithCount < 1 ? 1 : sharedWithCount;
    return (total / n).round();
  }

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        capturedAt: DateTime.parse(j['captured_at'] as String).toLocal(),
        imagePath: j['image_path'] as String,
        status: (j['status'] as String?) ?? 'pending',
        sharedWithCount: (j['shared_with_count'] as int?) ?? 1,
        title: j['title'] as String?,
        note: j['note'] as String?,
        mealSlot: j['meal_slot'] as String?,
        eatingType: j['eating_type'] as String?,
        kcalTotal: j['kcal_total'] as int?,
        macros: j['macros'] == null
            ? null
            : Map<String, dynamic>.from(j['macros'] as Map),
        confidence: (j['confidence'] as num?)?.toDouble(),
      );
}

class EntryItem {
  const EntryItem({
    required this.id,
    required this.name,
    this.kcal,
    this.qtyG,
    this.carbG,
    this.proteinG,
    this.fatG,
    this.confidence,
  });
  final String id;
  final String name;
  final int? kcal;
  final double? qtyG;
  final double? carbG;
  final double? proteinG;
  final double? fatG;
  final double? confidence;

  factory EntryItem.fromJson(Map<String, dynamic> j) => EntryItem(
        id: j['id'] as String,
        name: j['name'] as String,
        kcal: j['kcal'] as int?,
        qtyG: (j['qty_g'] as num?)?.toDouble(),
        carbG: (j['carb_g'] as num?)?.toDouble(),
        proteinG: (j['protein_g'] as num?)?.toDouble(),
        fatG: (j['fat_g'] as num?)?.toDouble(),
        confidence: (j['confidence'] as num?)?.toDouble(),
      );
}

const _entrySelect =
    'id, user_id, captured_at, image_path, status, shared_with_count, '
    'title, note, meal_slot, eating_type, kcal_total, macros, confidence';

/// 오늘(로컬 자정~현재) 타임라인. Home 이 구독.
final AutoDisposeFutureProvider<List<Entry>> todayEntriesProvider =
    FutureProvider.autoDispose<List<Entry>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  // Realtime 구독을 여기서 트리거. autoDispose 가 해제되면 구독도 해제됨.
  ref.watch(_entriesRealtimeProvider);

  final now = DateTime.now();
  // 로컬 자정을 UTC 로 변환해서 필터 (KST 00:00 = UTC 전날 15:00).
  final startOfDay = DateTime(now.year, now.month, now.day).toUtc();

  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('entries')
      .select(_entrySelect)
      .eq('user_id', user.id)
      .gte('captured_at', startOfDay.toIso8601String())
      .order('captured_at', ascending: false);

  return (rows as List)
      .map((r) => Entry.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();
});

/// 전체 기록 (최근 90일). 기록 탭이 구독.
///
/// MVP: 달력 히트맵 대신 날짜별 그룹 리스트. 과거 기록을 확인·재시도·
/// 신뢰도 체크에 사용한다. 90일이면 MVP 저장 정책(§11) 범위 안.
final AutoDisposeFutureProvider<List<Entry>> recentEntriesProvider =
    FutureProvider.autoDispose<List<Entry>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  ref.watch(_entriesRealtimeProvider);

  final since = DateTime.now().subtract(const Duration(days: 90)).toUtc();

  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('entries')
      .select(_entrySelect)
      .eq('user_id', user.id)
      .gte('captured_at', since.toIso8601String())
      .order('captured_at', ascending: false)
      .limit(500);

  return (rows as List)
      .map((r) => Entry.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();
});

/// 단일 엔트리 + 그에 속한 entry_items.
///
/// 상세 페이지가 구독. Realtime 업데이트 시 자동 refresh.
final entryDetailProvider = FutureProvider.autoDispose
    .family<EntryDetail?, String>((ref, entryId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  ref.watch(_entriesRealtimeProvider);

  final client = ref.watch(supabaseClientProvider);
  final entryRow = await client
      .from('entries')
      .select(_entrySelect)
      .eq('id', entryId)
      .eq('user_id', user.id)
      .maybeSingle();
  if (entryRow == null) return null;

  final itemRows = await client
      .from('entry_items')
      .select('id, name, kcal, qty_g, carb_g, protein_g, fat_g, confidence')
      .eq('entry_id', entryId)
      .order('kcal', ascending: false);

  return EntryDetail(
    entry: Entry.fromJson(Map<String, dynamic>.from(entryRow)),
    items: (itemRows as List)
        .map((r) => EntryItem.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
  );
});

class EntryDetail {
  const EntryDetail({required this.entry, required this.items});
  final Entry entry;
  final List<EntryItem> items;
}

/// Realtime 구독 — entries 테이블이 업데이트되면 today/recent/detail 를
/// 자동 invalidate. publication 은 0003_realtime_entries.sql 에서 활성화됨.
final AutoDisposeProvider<void> _entriesRealtimeProvider =
    Provider.autoDispose<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final client = ref.watch(supabaseClientProvider);

  // 채널명은 유저별로 유니크하게. 한 사용자가 여러 채널 만들지 않도록 autoDispose.
  final channel = client.channel('entries_${user.id}');

  void onChange(PostgresChangePayload payload) {
    final newRow = payload.newRecord;
    final oldRow = payload.oldRecord;
    // user_id 필터는 RLS + 서버측 filter 로 이미 걸렸지만 한 번 더.
    if ((newRow['user_id'] ?? oldRow['user_id']) != user.id) return;
    // today / recent / detail 프로바이더 모두 갱신. autoDispose 라 구독 없으면
    // no-op.
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(recentEntriesProvider);
    final id = (newRow['id'] ?? oldRow['id']) as String?;
    if (id != null) {
      ref.invalidate(entryDetailProvider(id));
    }
  }

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'entries',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: onChange,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'entries',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: onChange,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'entries',
        callback: onChange,
      )
      .subscribe();

  ref.onDispose(() {
    // fire-and-forget — unsubscribe 실패해도 UI 영향 없음.
    unawaited(client.removeChannel(channel));
  });
});

/// Realtime 폴백 — pending 엔트리가 하나라도 있으면 3초마다 today/recent 를
/// invalidate. Realtime 이벤트가 도착하면 어차피 invalidate 되므로 중복은
/// Riverpod 가 in-flight 요청을 정리한다. pending 이 사라지면 자동 종료.
final AutoDisposeProvider<void> pendingEntriesPollProvider =
    Provider.autoDispose<void>((ref) {
  final entries = ref.watch(todayEntriesProvider).valueOrNull ?? const [];
  final hasPending = entries.any((e) => e.status == 'pending');
  if (!hasPending) return;

  final timer = Timer(const Duration(seconds: 3), () {
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(recentEntriesProvider);
  });
  ref.onDispose(timer.cancel);
});

/// 단일 엔트리 폴백 폴러 — 상세 페이지에서 사용. 해당 엔트리가 pending 인
/// 동안 3초마다 entryDetailProvider 만 invalidate.
final AutoDisposeProviderFamily<void, String> pendingEntryDetailPollProvider =
    Provider.autoDispose.family<void, String>((ref, entryId) {
  final detail = ref.watch(entryDetailProvider(entryId)).valueOrNull;
  if (detail == null) return;
  if (detail.entry.status != 'pending') return;

  final timer = Timer(const Duration(seconds: 3), () {
    ref.invalidate(entryDetailProvider(entryId));
  });
  ref.onDispose(timer.cancel);
});

final photoUploadServiceProvider = Provider<PhotoUploadService>((ref) {
  return PhotoUploadService(ref.watch(supabaseClientProvider));
});

/// path → signed URL 메모이즈 (1시간).
/// FutureProvider.family 로 각 path 당 한 번만 서명.
///
/// keepAlive — 화면 전환 시에도 URL 캐시를 메모리에 유지해 재서명 라운드트립
/// 을 없앤다 (URL 자체 만료는 1시간이라 안전 마진 충분).
final signedUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, path) async {
  ref.keepAlive();
  final svc = ref.watch(photoUploadServiceProvider);
  return svc.signedUrl(path);
});
