/// 커뮤니티 백엔드 호출 모음.
///
/// 그룹 CRUD / 멤버십 / 포스트 / 반응 / 조언 / 신고 / 차단의 단순한 thin wrapper.
/// 비즈니스 로직 (검증, 에러 매핑) 은 호출자(provider/UI) 에서 처리.
///
/// SECURITY DEFINER RPC 가 필요한 작업 (그룹 생성, 비밀번호 검증, 강퇴, 신고 등)
/// 은 모두 RPC 로 호출. 일반 select / insert 는 supabase-flutter 클라이언트로.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/supabase_provider.dart';
import 'community_models.dart';

class CommunityService {
  CommunityService(this._client);
  final SupabaseClient _client;

  // ── 그룹 ───────────────────────────────────────────────────

  /// 새 그룹 생성. 성공 시 생성된 group id 반환.
  /// password 는 visibility=private 일 때만 사용 (4~8자).
  Future<String> createGroup({
    required String name,
    required String emoji,
    String? description,
    required GroupVisibility visibility,
    String? password,
  }) async {
    final result = await _client.rpc<dynamic>(
      'create_community_group',
      params: {
        'p_name': name,
        'p_emoji': emoji,
        'p_description': description,
        'p_visibility': visibility.value,
        'p_password': password,
      },
    );
    if (result is String) return result;
    throw Exception('create_community_group returned non-string: $result');
  }

  /// 공개 그룹 가입. 강퇴 24h 가드 + 정원 체크는 서버에서.
  Future<void> joinPublicGroup(String groupId) async {
    await _client.rpc<dynamic>(
      'join_public_group',
      params: {'p_group_id': groupId},
    );
  }

  /// 비공개 그룹 비밀번호 검증 + 가입.
  Future<void> joinPrivateGroup({
    required String groupId,
    required String password,
  }) async {
    await _client.rpc<dynamic>(
      'join_private_group',
      params: {
        'p_group_id': groupId,
        'p_password': password,
      },
    );
  }

  /// 그룹장: 비밀번호 변경.
  Future<void> changeGroupPassword({
    required String groupId,
    required String newPassword,
  }) async {
    await _client.rpc<dynamic>(
      'change_group_password',
      params: {
        'p_group_id': groupId,
        'p_new_password': newPassword,
      },
    );
  }

  /// 그룹장: 구성원 강퇴.
  Future<void> kickMember({
    required String groupId,
    required String targetUserId,
  }) async {
    await _client.rpc<dynamic>(
      'kick_group_member',
      params: {
        'p_group_id': groupId,
        'p_target_user': targetUserId,
      },
    );
  }

  /// 그룹장: 그룹 아카이브 (soft delete).
  Future<void> archiveGroup(String groupId) async {
    await _client.rpc<dynamic>(
      'archive_community_group',
      params: {'p_group_id': groupId},
    );
  }

  /// 그룹 메타 변경 (이름/이모지/소개글/visibility).
  /// 비밀번호는 별도 RPC `changeGroupPassword`.
  Future<void> updateGroupMeta({
    required String groupId,
    String? name,
    String? emoji,
    String? description,
    GroupVisibility? visibility,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (emoji != null) patch['emoji'] = emoji;
    if (description != null) patch['description'] = description;
    if (visibility != null) patch['visibility'] = visibility.value;
    if (patch.isEmpty) return;
    await _client.from('community_groups').update(patch).eq('id', groupId);
  }

  /// 본인 탈퇴 (left_at 세팅, soft).
  Future<void> leaveGroup({required String groupId, required String userId}) async {
    await _client
        .from('group_members')
        .update({'left_at': DateTime.now().toUtc().toIso8601String()})
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  /// 본인의 멤버십 설정 변경 (show_*, auto_share, share_time).
  Future<void> updateMyMembership({
    required String groupId,
    required String userId,
    bool? showPhotos,
    bool? showKcal,
    bool? showMacros,
    bool? autoShare,
    String? shareTimeHHmm,
  }) async {
    final patch = <String, dynamic>{};
    if (showPhotos != null) patch['show_photos'] = showPhotos;
    if (showKcal != null) patch['show_kcal'] = showKcal;
    if (showMacros != null) patch['show_macros'] = showMacros;
    if (autoShare != null) patch['auto_share'] = autoShare;
    if (shareTimeHHmm != null) patch['share_time'] = shareTimeHHmm;
    if (patch.isEmpty) return;
    await _client
        .from('group_members')
        .update(patch)
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  // ── 조회 ───────────────────────────────────────────────────

  /// 내가 참여 중인 활성 그룹 + 각 그룹의 활성 멤버 수.
  Future<List<CommunityGroup>> fetchMyGroups(String userId) async {
    final memberships = await _client
        .from('group_members')
        .select('group_id, role')
        .eq('user_id', userId)
        .filter('left_at', 'is', null)
        .filter('kicked_at', 'is', null);

    final ids =
        (memberships as List).map((r) => r['group_id'] as String).toList();
    if (ids.isEmpty) return const [];

    final rows = await _client
        .from('community_groups')
        .select('id, name, emoji, description, visibility, created_by, '
            'max_members, created_at, archived_at')
        .inFilter('id', ids)
        .filter('archived_at', 'is', null);

    final groups = (rows as List)
        .map((r) =>
            CommunityGroup.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();

    // 멤버 수 추가 조회 (성능 무난 — N+1 이지만 32명 소규모이므로 OK).
    // 실제 운영에서는 view 또는 aggregate RPC 로 최적화 가능.
    final counts = <String, int>{};
    for (final g in groups) {
      final cnt = await _client
          .from('group_members')
          .count(CountOption.exact)
          .eq('group_id', g.id)
          .filter('left_at', 'is', null)
          .filter('kicked_at', 'is', null);
      counts[g.id] = cnt;
    }
    return groups
        .map((g) => g.copyWith(memberCount: counts[g.id]))
        .toList();
  }

  /// 공개 그룹 목록 (최근 활동 순. simple — 그냥 최신 생성순).
  Future<List<CommunityGroup>> fetchPublicGroups({String? query}) async {
    var q = _client
        .from('community_groups')
        .select('id, name, emoji, description, visibility, created_by, '
            'max_members, created_at, archived_at')
        .eq('visibility', 'public')
        .filter('archived_at', 'is', null);

    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }

    final rows = await q.order('created_at', ascending: false).limit(50);
    return (rows as List)
        .map((r) =>
            CommunityGroup.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<CommunityGroup?> fetchGroup(String id) async {
    final row = await _client
        .from('community_groups')
        .select('id, name, emoji, description, visibility, created_by, '
            'max_members, created_at, archived_at')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final cnt = await _client
        .from('group_members')
        .count(CountOption.exact)
        .eq('group_id', id)
        .filter('left_at', 'is', null)
        .filter('kicked_at', 'is', null);
    return CommunityGroup.fromJson(row, memberCount: cnt);
  }

  /// 그룹 멤버 목록 (active only) + 닉네임.
  Future<List<GroupMember>> fetchMembers(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select('group_id, user_id, role, show_photos, show_kcal, show_macros, '
            'auto_share, share_time, joined_at, left_at, kicked_at, kicked_by')
        .eq('group_id', groupId)
        .filter('left_at', 'is', null)
        .filter('kicked_at', 'is', null)
        .order('joined_at', ascending: true);

    final list = (rows as List)
        .map((r) => GroupMember.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (list.isEmpty) return list;

    // 닉네임 조회.
    final nicks = await _fetchNicknames(list.map((m) => m.userId).toSet());
    return [
      for (final m in list)
        GroupMember.fromJson(
          {
            'group_id': m.groupId,
            'user_id': m.userId,
            'role': m.role,
            'show_photos': m.showPhotos,
            'show_kcal': m.showKcal,
            'show_macros': m.showMacros,
            'auto_share': m.autoShare,
            'share_time':
                '${m.shareTime.hour.toString().padLeft(2, '0')}:${m.shareTime.minute.toString().padLeft(2, '0')}',
            'joined_at': m.joinedAt.toUtc().toIso8601String(),
          },
          nickname: nicks[m.userId],
        ),
    ];
  }

  /// 그룹 피드 — 최근 14일 포스트.
  Future<List<CommunityPost>> fetchFeed(String groupId, {int limit = 50}) async {
    final rows = await _client
        .from('community_posts')
        .select('id, group_id, user_id, post_date, total_kcal, target_kcal, '
            'macros, achievement, status_badge, photo_paths, '
            'show_photos, show_kcal, show_macros, caption, created_at, '
            'deleted_at, hidden_at')
        .eq('group_id', groupId)
        .filter('deleted_at', 'is', null)
        .filter('hidden_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(limit);

    final list = (rows as List)
        .map((r) => CommunityPost.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (list.isEmpty) return list;
    final nicks = await _fetchNicknames(list.map((p) => p.userId).toSet());
    return [
      for (final p in list)
        CommunityPost.fromJson(_postToJson(p), nickname: nicks[p.userId])
    ];
  }

  Map<String, dynamic> _postToJson(CommunityPost p) {
    return {
      'id': p.id,
      'group_id': p.groupId,
      'user_id': p.userId,
      'post_date': '${p.postDate.year.toString().padLeft(4, '0')}-${p.postDate.month.toString().padLeft(2, '0')}-${p.postDate.day.toString().padLeft(2, '0')}',
      'total_kcal': p.totalKcal,
      'target_kcal': p.targetKcal,
      'macros': p.macros,
      'achievement': p.achievement,
      'status_badge': p.statusBadge,
      'photo_paths': p.photoPaths,
      'show_photos': p.showPhotos,
      'show_kcal': p.showKcal,
      'show_macros': p.showMacros,
      'caption': p.caption,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
      'hidden_at': p.hiddenAt?.toUtc().toIso8601String(),
    };
  }

  // ── 포스트 ─────────────────────────────────────────────────

  Future<CommunityPost?> fetchPost(String postId) async {
    final row = await _client
        .from('community_posts')
        .select('id, group_id, user_id, post_date, total_kcal, target_kcal, '
            'macros, achievement, status_badge, photo_paths, '
            'show_photos, show_kcal, show_macros, caption, created_at, '
            'deleted_at, hidden_at')
        .eq('id', postId)
        .maybeSingle();
    if (row == null) return null;
    final nicks = await _fetchNicknames({row['user_id'] as String});
    return CommunityPost.fromJson(row, nickname: nicks[row['user_id']]);
  }

  /// 새 포스트 생성. show_* 는 그룹 멤버십 설정에서 가져와 카드에 박제 (snapshot).
  /// [entryIds] 는 이 카드가 어떤 식단 항목들을 합산했는지 — 같은 날 또 공유할 때
  /// "이미 공유됨" 판단에 사용된다.
  Future<String> createPost({
    required String groupId,
    required String userId,
    required DateTime postDate,
    required List<String> entryIds,
    int? totalKcal,
    int? targetKcal,
    Map<String, dynamic>? macros,
    required double achievement,
    required String statusBadge,
    required List<String> photoPaths,
    required bool showPhotos,
    required bool showKcal,
    required bool showMacros,
    String? caption,
  }) async {
    final dateStr =
        '${postDate.year.toString().padLeft(4, '0')}-${postDate.month.toString().padLeft(2, '0')}-${postDate.day.toString().padLeft(2, '0')}';
    final inserted = await _client
        .from('community_posts')
        .insert({
          'group_id': groupId,
          'user_id': userId,
          'post_date': dateStr,
          'entry_ids': entryIds,
          'total_kcal': showKcal ? totalKcal : null,
          'target_kcal': showKcal ? targetKcal : null,
          'macros': showMacros ? macros : null,
          'achievement': achievement,
          'status_badge': statusBadge,
          'photo_paths': showPhotos ? photoPaths : <String>[],
          'show_photos': showPhotos,
          'show_kcal': showKcal,
          'show_macros': showMacros,
          'caption': caption,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// 같은 그룹/날짜에 내가 이미 공유한 entry id 집합.
  /// Share 페이지에서 기본 미선택 처리에 사용.
  Future<Set<String>> alreadySharedEntryIds({
    required String groupId,
    required DateTime postDate,
  }) async {
    final dateStr =
        '${postDate.year.toString().padLeft(4, '0')}-${postDate.month.toString().padLeft(2, '0')}-${postDate.day.toString().padLeft(2, '0')}';
    final rows = await _client.rpc(
      'already_shared_entry_ids',
      params: {'p_group_id': groupId, 'p_post_date': dateStr},
    );
    if (rows is List) {
      return rows.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  Future<void> softDeletePost(String postId) async {
    await _client
        .from('community_posts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', postId);
  }

  // ── 반응 ───────────────────────────────────────────────────

  Future<List<PostReaction>> fetchReactions(String postId) async {
    final rows = await _client
        .from('post_reactions')
        .select('id, post_id, user_id, reaction, created_at')
        .eq('post_id', postId);
    return (rows as List)
        .map((r) => PostReaction.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> addReaction({
    required String postId,
    required ReactionKind reaction,
  }) async {
    try {
      await _client.from('post_reactions').insert({
        'post_id': postId,
        'user_id': _client.auth.currentUser!.id,
        'reaction': reaction.value,
      });
    } on PostgrestException catch (e) {
      // unique_violation — 이미 같은 반응. 무시.
      if (e.code == '23505') return;
      rethrow;
    }
  }

  Future<void> removeReaction({
    required String postId,
    required ReactionKind reaction,
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('post_reactions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', uid)
        .eq('reaction', reaction.value);
  }

  // ── 조언 ───────────────────────────────────────────────────

  Future<List<PostTip>> fetchTips(String postId) async {
    final rows = await _client
        .from('post_tips')
        .select('id, post_id, user_id, body, created_at, deleted_at, hidden_at')
        .eq('post_id', postId)
        .filter('deleted_at', 'is', null)
        .filter('hidden_at', 'is', null)
        .order('created_at', ascending: true);
    final list = (rows as List)
        .map((r) => PostTip.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (list.isEmpty) return list;
    final nicks = await _fetchNicknames(list.map((t) => t.userId).toSet());
    return [
      for (final t in list)
        PostTip(
          id: t.id,
          postId: t.postId,
          userId: t.userId,
          body: t.body,
          createdAt: t.createdAt,
          deletedAt: t.deletedAt,
          hiddenAt: t.hiddenAt,
          nickname: nicks[t.userId],
        )
    ];
  }

  Future<String> addTip({required String postId, required String body}) async {
    final inserted = await _client
        .from('post_tips')
        .insert({
          'post_id': postId,
          'user_id': _client.auth.currentUser!.id,
          'body': body,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  // ── 댓글 좋아요 ───────────────────────────────────────────────

  Future<void> likeTip(String tipId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('tip_likes').insert({
        'tip_id': tipId,
        'user_id': uid,
      });
    } on PostgrestException catch (e) {
      // 23505 = unique_violation → 이미 좋아요 누른 상태.
      if (e.code == '23505') return;
      rethrow;
    }
  }

  Future<void> unlikeTip(String tipId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('tip_likes')
        .delete()
        .eq('tip_id', tipId)
        .eq('user_id', uid);
  }

  /// 한 포스트의 모든 tip_id 에 대한 좋아요. tip_id → (count, mine).
  Future<Map<String, ({int count, bool mine})>> fetchTipLikesForTips(
      List<String> tipIds) async {
    if (tipIds.isEmpty) return const {};
    final uid = _client.auth.currentUser?.id;
    final rows = await _client
        .from('tip_likes')
        .select('tip_id, user_id')
        .inFilter('tip_id', tipIds);
    final out = <String, ({int count, bool mine})>{};
    for (final id in tipIds) {
      out[id] = (count: 0, mine: false);
    }
    for (final r in (rows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final tipId = m['tip_id'] as String;
      final userId = m['user_id'] as String;
      final prev = out[tipId] ?? (count: 0, mine: false);
      out[tipId] = (
        count: prev.count + 1,
        mine: prev.mine || userId == uid,
      );
    }
    return out;
  }

  Future<void> updateTip({required String tipId, required String body}) async {
    await _client
        .from('post_tips')
        .update({'body': body})
        .eq('id', tipId);
  }

  Future<void> softDeleteTip(String tipId) async {
    await _client
        .from('post_tips')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', tipId);
  }

  // ── 신고 / 차단 ─────────────────────────────────────────────

  Future<String> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? detail,
    String? groupId,
  }) async {
    final result = await _client.rpc<dynamic>(
      'submit_report',
      params: {
        'p_target_type': targetType.value,
        'p_target_id': targetId,
        'p_reason': reason.value,
        'p_detail': detail,
        'p_group_id': groupId,
      },
    );
    if (result is String) return result;
    throw Exception('submit_report returned non-string: $result');
  }

  Future<void> blockUser(String targetUserId) async {
    try {
      await _client.from('user_blocks').insert({
        'blocker_id': _client.auth.currentUser!.id,
        'blocked_id': targetUserId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // already blocked
      rethrow;
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    await _client
        .from('user_blocks')
        .delete()
        .eq('blocker_id', _client.auth.currentUser!.id)
        .eq('blocked_id', targetUserId);
  }

  Future<List<String>> fetchBlockedUserIds() async {
    final rows = await _client
        .from('user_blocks')
        .select('blocked_id')
        .eq('blocker_id', _client.auth.currentUser!.id);
    return (rows as List).map((r) => r['blocked_id'] as String).toList();
  }

  // ── 사용자 디렉토리 ──────────────────────────────────────────

  /// 닉네임순 사용자 목록 / prefix 검색.
  /// [excludeGroupId] 가 주어지면 해당 그룹의 활성 멤버는 결과에서 빠진다.
  Future<List<UserHandle>> listUsersByNickname({
    String query = '',
    String? excludeGroupId,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client.rpc<dynamic>(
      'list_users_by_nickname',
      params: {
        'p_query': query,
        'p_exclude_group_id': excludeGroupId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (rows as List)
        .map((r) => UserHandle.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── 그룹 초대 ────────────────────────────────────────────────

  Future<String> sendGroupInvite({
    required String groupId,
    required String inviteeUserId,
  }) async {
    final result = await _client.rpc<dynamic>(
      'send_group_invite',
      params: {'p_group_id': groupId, 'p_invitee_id': inviteeUserId},
    );
    return result as String;
  }

  /// 수락 성공 시 가입한 그룹 id 반환.
  Future<String> acceptGroupInvite(String inviteId) async {
    final result = await _client.rpc<dynamic>(
      'accept_group_invite',
      params: {'p_invite_id': inviteId},
    );
    return result as String;
  }

  Future<void> declineGroupInvite(String inviteId) async {
    await _client.rpc<dynamic>(
      'decline_group_invite',
      params: {'p_invite_id': inviteId},
    );
  }

  /// 내가 받은 pending 초대 — 그룹 이모지/이름 + 초대자 닉네임까지 채운다.
  /// 비공개 그룹 초대일 경우 RLS 의 groups_read 정책상 그룹 메타가 안 보일
  /// 수 있어, 그땐 클라이언트가 fallback 표시.
  Future<List<GroupInvite>> fetchMyPendingInvites() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('group_invites')
        .select('id, group_id, inviter_id, invitee_id, status, '
            'created_at, responded_at, expires_at')
        .eq('invitee_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    final list = (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    if (list.isEmpty) return const [];

    final groupIds = list.map((r) => r['group_id'] as String).toSet().toList();
    final groupsRows = await _client
        .from('community_groups')
        .select('id, name, emoji')
        .inFilter('id', groupIds);
    final groupsById = <String, Map<String, dynamic>>{
      for (final r in (groupsRows as List))
        (r as Map)['id'] as String: Map<String, dynamic>.from(r),
    };

    // get_group_member_handles 는 같은 그룹 멤버 사이만 통과하므로,
    // 아직 가입 안 한 invitee 는 inviter 닉네임을 조회 못 함.
    // 별도 RPC get_invite_inviter_handles 를 사용 — 본인이 받은 pending
    // 초대의 inviter 닉네임만 노출.
    final inviterNicks = <String, String>{};
    final inviterRows = await _client
        .rpc<dynamic>('get_invite_inviter_handles');
    for (final r in (inviterRows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      inviterNicks[m['inviter_id'] as String] = m['nickname'] as String;
    }

    return list.map((j) {
      final g = groupsById[j['group_id']];
      return GroupInvite.fromJson(
        j,
        groupName: g?['name'] as String?,
        groupEmoji: g?['emoji'] as String?,
        inviterNickname: inviterNicks[j['inviter_id'] as String],
      );
    }).toList();
  }

  /// 마이 탭 배지용 가벼운 카운트.
  Future<int> countMyPendingInvites() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 0;
    final res = await _client
        .from('group_invites')
        .select('id')
        .eq('invitee_id', uid)
        .eq('status', 'pending')
        .count();
    return res.count;
  }

  // ── 헬퍼: 닉네임 일괄 조회 ────────────────────────────────────

  /// 같은 그룹 멤버의 닉네임만 SECURITY DEFINER RPC 로 조회.
  /// profiles 테이블 자체에 select 정책을 풀면 weight/goal 등 민감 컬럼이 노출되므로
  /// 절대 직접 select 하지 않는다.
  Future<Map<String, String>> _fetchNicknames(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final result = await _client.rpc<dynamic>(
      'get_group_member_handles',
      params: {'p_user_ids': userIds.toList()},
    );
    final out = <String, String>{};
    for (final r in (result as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      out[m['user_id'] as String] = m['nickname'] as String;
    }
    return out;
  }
}

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService(ref.watch(supabaseClientProvider));
});
