/// 커뮤니티 모델 단위 테스트 — fromJson 파싱 + enum 매핑.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/services/community/community_models.dart';

void main() {
  group('CommunityGroup.fromJson', () {
    test('public visibility 파싱', () {
      final g = CommunityGroup.fromJson({
        'id': '11111111-1111-1111-1111-111111111111',
        'name': '점심 인증',
        'emoji': '🍱',
        'description': null,
        'visibility': 'public',
        'created_by': '22222222-2222-2222-2222-222222222222',
        'max_members': 32,
        'created_at': '2026-05-05T00:00:00Z',
      });
      expect(g.visibility, GroupVisibility.public);
      expect(g.name, '점심 인증');
      expect(g.maxMembers, 32);
    });

    test('private + null fields 안전', () {
      final g = CommunityGroup.fromJson({
        'id': '11111111-1111-1111-1111-111111111111',
        'name': '비공개',
        'visibility': 'private',
        'created_by': '22222222-2222-2222-2222-222222222222',
        'created_at': '2026-05-05T00:00:00Z',
      });
      expect(g.visibility, GroupVisibility.private);
      expect(g.emoji, '🥗');
      expect(g.description, null);
      expect(g.maxMembers, 32);
    });

    test('archivedAt 파싱', () {
      final g = CommunityGroup.fromJson({
        'id': '11111111-1111-1111-1111-111111111111',
        'name': '아카이브된 그룹',
        'visibility': 'public',
        'created_by': '22222222-2222-2222-2222-222222222222',
        'created_at': '2026-01-01T00:00:00Z',
        'archived_at': '2026-05-01T12:00:00Z',
      });
      expect(g.archivedAt, isNotNull);
    });
  });

  group('GroupMember.fromJson', () {
    test('share_time 파싱', () {
      final m = GroupMember.fromJson({
        'group_id': '11111111-1111-1111-1111-111111111111',
        'user_id': '22222222-2222-2222-2222-222222222222',
        'role': 'owner',
        'show_photos': true,
        'show_kcal': true,
        'show_macros': false,
        'auto_share': false,
        'share_time': '21:30',
        'joined_at': '2026-05-05T00:00:00Z',
      });
      expect(m.shareTime, const TimeOfDay(hour: 21, minute: 30));
      expect(m.isOwner, true);
      expect(m.showMacros, false);
    });

    test('잘못된 share_time 은 fallback 21:00', () {
      final m = GroupMember.fromJson({
        'group_id': '11111111-1111-1111-1111-111111111111',
        'user_id': '22222222-2222-2222-2222-222222222222',
        'role': 'member',
        'show_photos': true,
        'show_kcal': true,
        'show_macros': true,
        'auto_share': false,
        'share_time': 'garbage',
        'joined_at': '2026-05-05T00:00:00Z',
      });
      expect(m.shareTime, const TimeOfDay(hour: 21, minute: 0));
    });

    test('isActive — left_at/kicked_at 둘 다 null 일 때만', () {
      final active = GroupMember.fromJson({
        'group_id': '1' * 36,
        'user_id': '2' * 36,
        'role': 'member',
        'show_photos': true,
        'show_kcal': true,
        'show_macros': true,
        'auto_share': false,
        'share_time': '21:00',
        'joined_at': '2026-05-05T00:00:00Z',
      });
      expect(active.isActive, true);

      final kicked = GroupMember.fromJson({
        'group_id': '1' * 36,
        'user_id': '2' * 36,
        'role': 'member',
        'show_photos': true,
        'show_kcal': true,
        'show_macros': true,
        'auto_share': false,
        'share_time': '21:00',
        'joined_at': '2026-05-05T00:00:00Z',
        'kicked_at': '2026-05-05T01:00:00Z',
      });
      expect(kicked.isActive, false);
    });
  });

  group('CommunityPost.fromJson', () {
    test('show_* 가 false 면 모델에는 그대로 false 로 전달', () {
      final p = CommunityPost.fromJson({
        'id': '1' * 36,
        'group_id': '2' * 36,
        'user_id': '3' * 36,
        'post_date': '2026-05-05',
        'total_kcal': 1500,
        'target_kcal': 1800,
        'achievement': 83.3,
        'status_badge': 'almost',
        'photo_paths': ['userA/foo.jpg'],
        'show_photos': false,
        'show_kcal': false,
        'show_macros': false,
        'created_at': '2026-05-05T12:00:00Z',
      });
      expect(p.showPhotos, false);
      expect(p.showKcal, false);
      expect(p.showMacros, false);
      expect(p.statusBadge, 'almost');
      expect(p.photoPaths, ['userA/foo.jpg']);
    });

    test('isVisible — deletedAt/hiddenAt null 인 경우만', () {
      final v = CommunityPost.fromJson({
        'id': '1' * 36,
        'group_id': '2' * 36,
        'user_id': '3' * 36,
        'post_date': '2026-05-05',
        'achievement': 100,
        'status_badge': 'achieved',
        'photo_paths': <dynamic>[],
        'show_photos': true,
        'show_kcal': true,
        'show_macros': true,
        'created_at': '2026-05-05T12:00:00Z',
      });
      expect(v.isVisible, true);

      final hidden = CommunityPost.fromJson({
        ...{
          'id': '1' * 36,
          'group_id': '2' * 36,
          'user_id': '3' * 36,
          'post_date': '2026-05-05',
          'achievement': 100,
          'status_badge': 'achieved',
          'photo_paths': <dynamic>[],
          'show_photos': true,
          'show_kcal': true,
          'show_macros': true,
          'created_at': '2026-05-05T12:00:00Z',
        },
        'hidden_at': '2026-05-05T13:00:00Z',
      });
      expect(hidden.isVisible, false);
    });
  });

  group('ReactionKindX', () {
    test('parse + emoji 매핑', () {
      expect(ReactionKindX.parse('fire'), ReactionKind.fire);
      expect(ReactionKindX.parse('clap'), ReactionKind.clap);
      expect(ReactionKindX.parse('heart'), ReactionKind.heart);
      expect(ReactionKindX.parse('garbage'), null);

      expect(ReactionKind.fire.emoji, '🔥');
      expect(ReactionKind.clap.emoji, '👏');
      expect(ReactionKind.heart.emoji, '💚');
    });
  });

  group('ReportReason / ReportTargetType — value 일관성', () {
    test('value 는 enum.name 과 동일 (서버 RPC 와 매핑)', () {
      expect(ReportReason.inappropriate.value, 'inappropriate');
      expect(ReportReason.spam.value, 'spam');
      expect(ReportReason.harassment.value, 'harassment');
      expect(ReportReason.other.value, 'other');

      expect(ReportTargetType.post.value, 'post');
      expect(ReportTargetType.tip.value, 'tip');
      expect(ReportTargetType.user.value, 'user');
    });
  });
}
