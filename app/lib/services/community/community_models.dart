/// 커뮤니티 데이터 모델 — 그룹, 멤버십, 포스트, 반응, 조언, 신고.
///
/// DB 스키마는 마이그레이션 0007 참고. 클라이언트는 항상 RLS 통과 후의 row 만
/// 본다. 비밀번호 해시는 별도 테이블 community_group_secrets 에 격리되어
/// 여기 모델에는 등장하지 않는다.
library;

import 'package:flutter/material.dart';

enum GroupVisibility { public, private }

extension GroupVisibilityX on GroupVisibility {
  String get value => name; // public | private
  static GroupVisibility parse(String? v) {
    return v == 'public' ? GroupVisibility.public : GroupVisibility.private;
  }
}

class CommunityGroup {
  const CommunityGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.visibility,
    required this.createdBy,
    required this.maxMembers,
    required this.createdAt,
    this.description,
    this.archivedAt,
    this.memberCount,
  });

  final String id;
  final String name;
  final String emoji;
  final String? description;
  final GroupVisibility visibility;
  final String createdBy;
  final int maxMembers;
  final DateTime createdAt;
  final DateTime? archivedAt;
  /// optional, populated from aggregate query.
  final int? memberCount;

  factory CommunityGroup.fromJson(Map<String, dynamic> j, {int? memberCount}) {
    return CommunityGroup(
      id: j['id'] as String,
      name: j['name'] as String,
      emoji: (j['emoji'] as String?) ?? '🥗',
      description: j['description'] as String?,
      visibility: GroupVisibilityX.parse(j['visibility'] as String?),
      createdBy: j['created_by'] as String,
      maxMembers: (j['max_members'] as num?)?.toInt() ?? 32,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      archivedAt: j['archived_at'] == null
          ? null
          : DateTime.tryParse(j['archived_at'] as String)?.toLocal(),
      memberCount: memberCount,
    );
  }

  CommunityGroup copyWith({int? memberCount, String? name, String? emoji,
      String? description, GroupVisibility? visibility}) {
    return CommunityGroup(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      createdBy: createdBy,
      maxMembers: maxMembers,
      createdAt: createdAt,
      archivedAt: archivedAt,
      memberCount: memberCount ?? this.memberCount,
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.groupId,
    required this.userId,
    required this.role,
    required this.showPhotos,
    required this.showKcal,
    required this.showMacros,
    required this.autoShare,
    required this.shareTime,
    required this.joinedAt,
    this.leftAt,
    this.kickedAt,
    this.kickedBy,
    this.nickname,
  });

  final String groupId;
  final String userId;
  final String role; // owner | member
  final bool showPhotos;
  final bool showKcal;
  final bool showMacros;
  final bool autoShare;
  final TimeOfDay shareTime;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final DateTime? kickedAt;
  final String? kickedBy;
  /// joined from profiles via separate query.
  final String? nickname;

  bool get isOwner => role == 'owner';
  bool get isActive => leftAt == null && kickedAt == null;

  factory GroupMember.fromJson(Map<String, dynamic> j, {String? nickname}) {
    return GroupMember(
      groupId: j['group_id'] as String,
      userId: j['user_id'] as String,
      role: j['role'] as String? ?? 'member',
      showPhotos: j['show_photos'] as bool? ?? true,
      showKcal: j['show_kcal'] as bool? ?? true,
      showMacros: j['show_macros'] as bool? ?? true,
      autoShare: j['auto_share'] as bool? ?? false,
      shareTime: _parseTime(j['share_time'] as String?),
      joinedAt: DateTime.parse(j['joined_at'] as String).toLocal(),
      leftAt: j['left_at'] == null
          ? null
          : DateTime.tryParse(j['left_at'] as String)?.toLocal(),
      kickedAt: j['kicked_at'] == null
          ? null
          : DateTime.tryParse(j['kicked_at'] as String)?.toLocal(),
      kickedBy: j['kicked_by'] as String?,
      nickname: nickname,
    );
  }

  static TimeOfDay _parseTime(String? s) {
    if (s == null) return const TimeOfDay(hour: 21, minute: 0);
    final parts = s.split(':');
    if (parts.length < 2) return const TimeOfDay(hour: 21, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 21,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.postDate,
    required this.statusBadge,
    required this.photoPaths,
    required this.showPhotos,
    required this.showKcal,
    required this.showMacros,
    required this.createdAt,
    this.totalKcal,
    this.targetKcal,
    this.macros,
    this.achievement,
    this.caption,
    this.deletedAt,
    this.hiddenAt,
    this.nickname,
  });

  final String id;
  final String groupId;
  final String userId;
  final DateTime postDate;
  final int? totalKcal;
  final int? targetKcal;
  final Map<String, dynamic>? macros;
  final double? achievement;
  final String statusBadge; // achieved | almost | retry
  final List<String> photoPaths;
  final bool showPhotos;
  final bool showKcal;
  final bool showMacros;
  final String? caption;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final DateTime? hiddenAt;
  /// joined from profiles.
  final String? nickname;

  bool get isVisible => deletedAt == null && hiddenAt == null;

  factory CommunityPost.fromJson(Map<String, dynamic> j, {String? nickname}) {
    return CommunityPost(
      id: j['id'] as String,
      groupId: j['group_id'] as String,
      userId: j['user_id'] as String,
      postDate: DateTime.parse(j['post_date'] as String),
      totalKcal: (j['total_kcal'] as num?)?.toInt(),
      targetKcal: (j['target_kcal'] as num?)?.toInt(),
      macros: j['macros'] == null
          ? null
          : Map<String, dynamic>.from(j['macros'] as Map),
      achievement: (j['achievement'] as num?)?.toDouble(),
      statusBadge: j['status_badge'] as String? ?? 'retry',
      photoPaths: (j['photo_paths'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      showPhotos: j['show_photos'] as bool? ?? true,
      showKcal: j['show_kcal'] as bool? ?? true,
      showMacros: j['show_macros'] as bool? ?? true,
      caption: j['caption'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      deletedAt: j['deleted_at'] == null
          ? null
          : DateTime.tryParse(j['deleted_at'] as String)?.toLocal(),
      hiddenAt: j['hidden_at'] == null
          ? null
          : DateTime.tryParse(j['hidden_at'] as String)?.toLocal(),
      nickname: nickname,
    );
  }
}

enum ReactionKind { fire, clap, heart }

extension ReactionKindX on ReactionKind {
  String get value => name; // fire | clap | heart
  static ReactionKind? parse(String? v) {
    switch (v) {
      case 'fire':
        return ReactionKind.fire;
      case 'clap':
        return ReactionKind.clap;
      case 'heart':
        return ReactionKind.heart;
      default:
        return null;
    }
  }

  String get emoji {
    switch (this) {
      case ReactionKind.fire:
        return '🔥';
      case ReactionKind.clap:
        return '👏';
      case ReactionKind.heart:
        return '💚';
    }
  }
}

class PostReaction {
  const PostReaction({
    required this.id,
    required this.postId,
    required this.userId,
    required this.reaction,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String userId;
  final ReactionKind reaction;
  final DateTime createdAt;

  factory PostReaction.fromJson(Map<String, dynamic> j) {
    return PostReaction(
      id: j['id'] as String,
      postId: j['post_id'] as String,
      userId: j['user_id'] as String,
      reaction: ReactionKindX.parse(j['reaction'] as String?) ??
          ReactionKind.fire,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }
}

class PostTip {
  const PostTip({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.deletedAt,
    this.hiddenAt,
    this.nickname,
  });

  final String id;
  final String postId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final DateTime? hiddenAt;
  final String? nickname;

  bool get isVisible => deletedAt == null && hiddenAt == null;

  factory PostTip.fromJson(Map<String, dynamic> j, {String? nickname}) {
    return PostTip(
      id: j['id'] as String,
      postId: j['post_id'] as String,
      userId: j['user_id'] as String,
      body: j['body'] as String,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      deletedAt: j['deleted_at'] == null
          ? null
          : DateTime.tryParse(j['deleted_at'] as String)?.toLocal(),
      hiddenAt: j['hidden_at'] == null
          ? null
          : DateTime.tryParse(j['hidden_at'] as String)?.toLocal(),
      nickname: nickname,
    );
  }
}

enum ReportReason { inappropriate, spam, harassment, other }

extension ReportReasonX on ReportReason {
  String get value => name;
  String get label {
    switch (this) {
      case ReportReason.inappropriate:
        return '부적절한 콘텐츠';
      case ReportReason.spam:
        return '스팸/광고';
      case ReportReason.harassment:
        return '괴롭힘/비방';
      case ReportReason.other:
        return '기타';
    }
  }
}

enum ReportTargetType { post, tip, user }

extension ReportTargetTypeX on ReportTargetType {
  String get value => name;
}

/// 인스타식 신고 사유 — 사용자 보이는 9가지 카테고리.
/// DB enum (`report_reason`) 은 4개라 가까운 값으로 매핑하고, 한국어
/// 라벨은 reports.detail 에 함께 저장해 관리자가 정확한 사유 확인.
enum ReportReasonUi {
  dontLike(
    '마음에 들지 않습니다',
    ReportReason.other,
  ),
  unwantedContact(
    '따돌림 또는 원치 않는 연락',
    ReportReason.harassment,
  ),
  selfHarm(
    '자살, 자해 및 섭식 장애',
    ReportReason.harassment,
  ),
  violence(
    '폭력, 혐오 또는 학대',
    ReportReason.harassment,
  ),
  regulated(
    '규제 품목의 판매 또는 홍보',
    ReportReason.inappropriate,
  ),
  sexual(
    '나체 이미지 또는 성적 행위',
    ReportReason.inappropriate,
  ),
  scam(
    '스캠, 사기 또는 스팸',
    ReportReason.spam,
  ),
  misinformation(
    '거짓 정보',
    ReportReason.other,
  ),
  ipViolation(
    '지식재산권 침해',
    ReportReason.other,
  );

  const ReportReasonUi(this.label, this.dbReason);
  final String label;
  final ReportReason dbReason;
}

// ── 사용자 디렉토리 ───────────────────────────────────────────

/// 닉네임 검색/리스트 RPC 의 행. PII 차단 위해 user_id, nickname 만.
class UserHandle {
  const UserHandle({required this.userId, required this.nickname});
  final String userId;
  final String nickname;

  factory UserHandle.fromJson(Map<String, dynamic> j) => UserHandle(
        userId: j['user_id'] as String,
        nickname: j['nickname'] as String,
      );
}

// ── 그룹 초대 ─────────────────────────────────────────────────

enum GroupInviteStatus { pending, accepted, declined, expired }

extension GroupInviteStatusX on GroupInviteStatus {
  String get value => name;
  static GroupInviteStatus parse(String? v) {
    switch (v) {
      case 'accepted':
        return GroupInviteStatus.accepted;
      case 'declined':
        return GroupInviteStatus.declined;
      case 'expired':
        return GroupInviteStatus.expired;
      case 'pending':
      default:
        return GroupInviteStatus.pending;
    }
  }
}

class GroupInvite {
  const GroupInvite({
    required this.id,
    required this.groupId,
    required this.inviterId,
    required this.inviteeId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
    this.groupName,
    this.groupEmoji,
    this.inviterNickname,
  });

  final String id;
  final String groupId;
  final String inviterId;
  final String inviteeId;
  final GroupInviteStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;

  // 화면 표시용 — 별도 join/lookup 으로 채움.
  final String? groupName;
  final String? groupEmoji;
  final String? inviterNickname;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == GroupInviteStatus.pending && !isExpired;

  factory GroupInvite.fromJson(
    Map<String, dynamic> j, {
    String? groupName,
    String? groupEmoji,
    String? inviterNickname,
  }) {
    return GroupInvite(
      id: j['id'] as String,
      groupId: j['group_id'] as String,
      inviterId: j['inviter_id'] as String,
      inviteeId: j['invitee_id'] as String,
      status: GroupInviteStatusX.parse(j['status'] as String?),
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
      respondedAt: j['responded_at'] == null
          ? null
          : DateTime.tryParse(j['responded_at'] as String)?.toLocal(),
      groupName: groupName,
      groupEmoji: groupEmoji,
      inviterNickname: inviterNickname,
    );
  }
}
