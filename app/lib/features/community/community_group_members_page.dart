/// 그룹 구성원 목록 + 그룹장 강퇴.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityGroupMembersPage extends ConsumerWidget {
  const CommunityGroupMembersPage({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final myUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('구성원',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: membersAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: FoodietColors.coral500)),
          error: (_, __) =>
              const Center(child: Text('구성원을 불러오지 못했어요.')),
          data: (members) {
            final group = groupAsync.valueOrNull;
            final isOwner =
                group != null && group.createdBy == myUserId;
            return ListView.separated(
              padding: const EdgeInsets.all(FoodietShape.sp16),
              itemCount: members.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: FoodietColors.cream100),
              itemBuilder: (_, i) => _MemberRow(
                member: members[i],
                isMyselfOwner: isOwner,
                isMyself: members[i].userId == myUserId,
                groupId: groupId,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.isMyselfOwner,
    required this.isMyself,
    required this.groupId,
  });
  final GroupMember member;
  final bool isMyselfOwner;
  final bool isMyself;
  final String groupId;

  Future<void> _kick(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${member.nickname ?? '구성원'}님을 그룹에서 내보낼까요?'),
        content: const Text('강퇴 후 24시간 동안은 다시 참여할 수 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소')),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: FoodietColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('강퇴')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(communityServiceProvider).kickMember(
            groupId: groupId,
            targetUserId: member.userId,
          );
      ref.invalidate(groupMembersProvider(groupId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('구성원을 강퇴했어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('강퇴 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canKick = isMyselfOwner && !isMyself && !member.isOwner;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: FoodietColors.coral100,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text('🍓', style: TextStyle(fontSize: 18)),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(member.nickname ?? '구성원',
                overflow: TextOverflow.ellipsis,
                style: FoodietText.body.copyWith(
                    color: FoodietColors.warm900,
                    fontWeight: FontWeight.w700)),
          ),
          if (member.isOwner) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FoodietColors.coral100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('그룹장',
                  style: FoodietText.caption.copyWith(
                      color: FoodietColors.coral700,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
      trailing: canKick
          ? IconButton(
              tooltip: '강퇴',
              icon: const Icon(Icons.person_remove_alt_1_outlined,
                  color: FoodietColors.danger),
              onPressed: () => _kick(context, ref),
            )
          : null,
    );
  }
}
