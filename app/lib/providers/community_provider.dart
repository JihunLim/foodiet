/// 커뮤니티 데이터 프로바이더 — 그룹 / 멤버 / 피드 / 반응 / 조언.
///
/// 모두 autoDispose family 로 — 화면 떠나면 캐시 비움.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/community/community_models.dart';
import '../services/community/community_service.dart';
import 'auth_provider.dart';
import 'supabase_provider.dart';

/// 내가 참여 중인 그룹 목록.
final myGroupsProvider =
    FutureProvider.autoDispose<List<CommunityGroup>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  // realtime invalidation 트리거 — 멤버십 / 그룹 변경 시 자동 갱신.
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchMyGroups(user.id);
});

/// 공개 그룹 검색/리스트 — query 가 바뀌면 새 family.
final publicGroupsProvider = FutureProvider.autoDispose
    .family<List<CommunityGroup>, String>((ref, query) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchPublicGroups(query: query);
});

/// 단일 그룹.
final groupDetailProvider =
    FutureProvider.autoDispose.family<CommunityGroup?, String>((ref, id) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchGroup(id);
});

/// 그룹 멤버 목록.
final groupMembersProvider = FutureProvider.autoDispose
    .family<List<GroupMember>, String>((ref, groupId) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchMembers(groupId);
});

/// 그룹 피드.
final groupFeedProvider = FutureProvider.autoDispose
    .family<List<CommunityPost>, String>((ref, groupId) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchFeed(groupId);
});

/// 단일 포스트.
final postDetailProvider = FutureProvider.autoDispose
    .family<CommunityPost?, String>((ref, postId) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchPost(postId);
});

/// 포스트의 모든 반응.
final postReactionsProvider = FutureProvider.autoDispose
    .family<List<PostReaction>, String>((ref, postId) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchReactions(postId);
});

/// 포스트의 조언 스레드.
final postTipsProvider = FutureProvider.autoDispose
    .family<List<PostTip>, String>((ref, postId) async {
  ref.watch(_communityRealtimeProvider);
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchTips(postId);
});

/// 차단한 사용자 id 목록 (UI 에서 본인 차단 표시용).
final blockedUsersProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final svc = ref.watch(communityServiceProvider);
  return svc.fetchBlockedUserIds();
});

/// Realtime 구독 — community_posts/reactions/tips 가 바뀌면 모든 family invalidate.
/// 채널 1개로 통합 (여러 그룹을 동시에 보고 있을 일이 거의 없으므로).
final AutoDisposeProvider<void> _communityRealtimeProvider =
    Provider.autoDispose<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;
  final client = ref.watch(supabaseClientProvider);

  final ch = client.channel('community_${user.id}');

  void invalidateAll(PostgresChangePayload _) {
    ref.invalidate(myGroupsProvider);
    // family 들은 keepAlive 가 아니라 autoDispose 이므로 사용 중인 것만 살아있다.
    // invalidate 호출은 그런 경우에만 효과.
  }

  ch
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'community_posts',
        callback: invalidateAll,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'post_reactions',
        callback: invalidateAll,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'post_tips',
        callback: invalidateAll,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'group_members',
        callback: invalidateAll,
      )
      .subscribe();

  ref.onDispose(() {
    unawaited(client.removeChannel(ch));
  });
});

/// 호출자 편의: 그룹/포스트/반응 캐시를 일괄 invalidate.
void invalidateCommunityFor(WidgetRef ref, {String? groupId, String? postId}) {
  ref.invalidate(myGroupsProvider);
  if (groupId != null) {
    ref.invalidate(groupDetailProvider(groupId));
    ref.invalidate(groupFeedProvider(groupId));
    ref.invalidate(groupMembersProvider(groupId));
  }
  if (postId != null) {
    ref.invalidate(postDetailProvider(postId));
    ref.invalidate(postReactionsProvider(postId));
    ref.invalidate(postTipsProvider(postId));
  }
}
