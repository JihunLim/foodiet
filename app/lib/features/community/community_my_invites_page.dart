/// 마이 > 그룹 초대장.
///
/// 받은 pending 초대 목록. 카드별 수락 / 거절. 수락하면 즉시 그룹 상세로 이동.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityMyInvitesPage extends ConsumerStatefulWidget {
  const CommunityMyInvitesPage({super.key});

  @override
  ConsumerState<CommunityMyInvitesPage> createState() =>
      _CommunityMyInvitesPageState();
}

class _CommunityMyInvitesPageState
    extends ConsumerState<CommunityMyInvitesPage> {
  // 진행 중 액션을 막아 더블탭 차단.
  final Set<String> _busyIds = <String>{};

  Future<void> _accept(GroupInvite inv) async {
    if (_busyIds.contains(inv.id)) return;
    setState(() => _busyIds.add(inv.id));
    try {
      final groupId = await ref
          .read(communityServiceProvider)
          .acceptGroupInvite(inv.id);
      if (!mounted) return;
      // 캐시 일괄 갱신 — 그룹 목록 / 초대 목록 / 카운트.
      ref.invalidate(myGroupsProvider);
      ref.invalidate(myInvitesProvider);
      ref.invalidate(myInvitesCountProvider);
      // 그룹이 동시에 archive / 삭제됐을 가능성 prefetch 로 검증.
      // 실패하면 그룹 상세 dead route 대신 커뮤니티 메인으로.
      try {
        await ref
            .read(groupDetailProvider(groupId).future)
            .timeout(const Duration(seconds: 5));
        if (!mounted) return;
        context.go('/community/group/$groupId');
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('그룹 정보를 불러올 수 없어요. 잠시 후 다시 시도해주세요.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FoodietColors.warm700,
          ),
        );
        context.go('/community');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(inv.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanError(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  Future<void> _decline(GroupInvite inv) async {
    if (_busyIds.contains(inv.id)) return;
    setState(() => _busyIds.add(inv.id));
    try {
      await ref.read(communityServiceProvider).declineGroupInvite(inv.id);
      if (!mounted) return;
      ref.invalidate(myInvitesProvider);
      ref.invalidate(myInvitesCountProvider);
      setState(() => _busyIds.remove(inv.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(inv.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanError(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  String _humanError(Object e) {
    final s = e.toString();
    if (s.contains('invite_expired')) return '만료된 초대장이에요.';
    if (s.contains('invite_not_pending')) return '이미 처리된 초대장이에요.';
    if (s.contains('group_full')) return '그룹 정원이 가득 찼어요.';
    if (s.contains('group_not_found')) return '그룹이 사라졌어요.';
    if (s.contains('kicked_recently')) return '최근 강퇴되어 다시 참여할 수 없어요.';
    return '처리 실패. 잠시 후 다시 시도해주세요.';
  }

  @override
  Widget build(BuildContext context) {
    final invitesAsync = ref.watch(myInvitesProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('그룹 초대장',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: FoodietColors.coral500,
          onRefresh: () async {
            ref.invalidate(myInvitesProvider);
            ref.invalidate(myInvitesCountProvider);
          },
          child: invitesAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: FoodietColors.coral500)),
            error: (e, _) => ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(FoodietShape.sp20),
                    child: Text('초대장을 불러오지 못했어요.\n$e',
                        textAlign: TextAlign.center,
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm700)),
                  ),
                ),
              ],
            ),
            data: (invites) {
              if (invites.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          const Text('📬', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: FoodietShape.sp12),
                          Text('받은 초대장이 없어요.',
                              style: FoodietText.body.copyWith(
                                  color: FoodietColors.warm700)),
                          const SizedBox(height: 4),
                          Text('새 초대가 오면 여기에 표시돼.',
                              style: FoodietText.bodySm.copyWith(
                                  color: FoodietColors.warm500)),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(FoodietShape.sp16),
                itemCount: invites.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: FoodietShape.sp12),
                itemBuilder: (_, i) {
                  final inv = invites[i];
                  return _InviteCard(
                    invite: inv,
                    busy: _busyIds.contains(inv.id),
                    onAccept: () => _accept(inv),
                    onDecline: () => _decline(inv),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });
  final GroupInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final emoji = invite.groupEmoji ?? '🥗';
    final groupName = invite.groupName ?? '비공개 그룹';
    final inviter = invite.inviterNickname ?? '누군가';
    final dateLabel = DateFormat('M월 d일').format(invite.createdAt);

    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: FoodietColors.cream00,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(groupName,
                        style: FoodietText.title.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('$inviter 님이 초대했어요 · $dateLabel',
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FoodietColors.warm700,
                    side: const BorderSide(color: FoodietColors.cream100),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                    ),
                  ),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: FoodietColors.coral500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('수락'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
