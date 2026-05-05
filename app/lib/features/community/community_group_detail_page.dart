/// 그룹 상세 — 피드 + 헤더 + 가입/공유 진입.
///
/// 비멤버가 공개 그룹 상세에 들어왔을 때는 "가입하기" 버튼만 보여주고,
/// 멤버가 들어오면 피드 전체가 보인다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import 'community_card.dart';

class CommunityGroupDetailPage extends ConsumerWidget {
  const CommunityGroupDetailPage({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final myGroupsAsync = ref.watch(myGroupsProvider);
    final isMember = (myGroupsAsync.valueOrNull ?? const [])
        .any((g) => g.id == groupId);
    final myUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: FoodietColors.warm900, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go('/community'),
        ),
        title: groupAsync.when(
          loading: () => const Text(''),
          error: (_, __) => const Text(''),
          data: (g) => Text(g?.name ?? '',
              style:
                  FoodietText.h3.copyWith(color: FoodietColors.warm900)),
        ),
        actions: [
          groupAsync.maybeWhen(
            data: (g) {
              if (g == null) return const SizedBox.shrink();
              if (!isMember) return const SizedBox.shrink();
              final isOwner = g.createdBy == myUserId;
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.people_outline,
                        color: FoodietColors.warm700),
                    tooltip: '구성원',
                    onPressed: () =>
                        context.push('/community/group/$groupId/members'),
                  ),
                  if (isOwner)
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: FoodietColors.warm700),
                      tooltip: '설정',
                      onPressed: () =>
                          context.push('/community/group/$groupId/settings'),
                    ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: groupAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
                color: FoodietColors.coral500),
          ),
          error: (_, __) =>
              const Center(child: Text('그룹을 찾을 수 없어요.')),
          data: (g) {
            if (g == null) {
              return const Center(child: Text('그룹을 찾을 수 없어요.'));
            }
            if (!isMember) {
              return _NonMemberView(group: g);
            }
            return _MemberFeed(groupId: groupId, group: g);
          },
        ),
      ),
    );
  }
}

class _NonMemberView extends ConsumerStatefulWidget {
  const _NonMemberView({required this.group});
  final CommunityGroup group;

  @override
  ConsumerState<_NonMemberView> createState() => _NonMemberViewState();
}

class _NonMemberViewState extends ConsumerState<_NonMemberView> {
  bool _joining = false;
  String? _error;

  Future<void> _join() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final svc = ref.read(communityServiceProvider);
      if (widget.group.visibility == GroupVisibility.public) {
        await svc.joinPublicGroup(widget.group.id);
        ref.invalidate(myGroupsProvider);
        ref.invalidate(groupDetailProvider(widget.group.id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('그룹에 참여했어요!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FoodietColors.warm700,
          ),
        );
      } else {
        if (!mounted) return;
        context.push('/community/join');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = _humanize(e);
      });
    }
  }

  String _humanize(Object e) {
    final s = e.toString();
    if (s.contains('group_full')) return '그룹이 가득 찼어요.';
    if (s.contains('kicked_recently')) return '최근 강퇴되어 24시간 동안 재참여할 수 없어요.';
    return '참여에 실패했어요.';
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Padding(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(g.emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text(g.name,
              style: FoodietText.h2.copyWith(color: FoodietColors.warm900)),
          if (g.description != null && g.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(g.description!,
                textAlign: TextAlign.center,
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500)),
          ],
          const SizedBox(height: 8),
          Text('구성원 ${g.memberCount ?? '-'}/${g.maxMembers}',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: 32),
          if (_error != null) ...[
            Text(_error!,
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.danger)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _joining ? null : _join,
            style: FilledButton.styleFrom(
              backgroundColor: FoodietColors.coral500,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_joining ? '참여 중…' : '참여하기'),
          ),
        ],
      ),
    );
  }
}

class _MemberFeed extends ConsumerWidget {
  const _MemberFeed({required this.groupId, required this.group});
  final String groupId;
  final CommunityGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupFeedProvider(groupId));
    return feedAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: FoodietColors.coral500),
      ),
      error: (_, __) =>
          const Center(child: Text('피드를 불러오지 못했어요.')),
      data: (posts) {
        return RefreshIndicator(
          color: FoodietColors.coral500,
          onRefresh: () async {
            ref.invalidate(groupFeedProvider(groupId));
            await ref.read(groupFeedProvider(groupId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                FoodietShape.sp16, FoodietShape.sp8,
                FoodietShape.sp16, FoodietShape.sp40),
            children: [
              if (group.description != null && group.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(group.description!,
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.warm500)),
                ),
              FilledButton.icon(
                onPressed: () => context.push('/community/share-today'),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('오늘 식단 공유하기'),
                style: FilledButton.styleFrom(
                  backgroundColor: FoodietColors.coral500,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 12),
              if (posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('아직 공유된 식단이 없어요. 첫 카드를 올려볼까?',
                      textAlign: TextAlign.center,
                      style: FoodietText.body
                          .copyWith(color: FoodietColors.warm500)),
                )
              else
                ...posts.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: CommunityCard(
                        post: p,
                        onTap: () => context.push(
                            '/community/group/${p.groupId}/post/${p.id}'),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }
}
