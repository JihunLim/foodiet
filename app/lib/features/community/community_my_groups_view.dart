/// 커뮤니티 > 내 그룹 — 그룹 셀렉터 + 선택된 그룹 피드.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../theme/foodiet_tokens.dart';
import 'community_card.dart';

class CommunityMyGroupsView extends ConsumerStatefulWidget {
  const CommunityMyGroupsView({super.key});

  @override
  ConsumerState<CommunityMyGroupsView> createState() =>
      _CommunityMyGroupsViewState();
}

class _CommunityMyGroupsViewState extends ConsumerState<CommunityMyGroupsView> {
  String? _selectedGroupId;

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return groupsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: FoodietColors.coral500),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '그룹을 불러오지 못했어요.\n${_short(e.toString())}',
            textAlign: TextAlign.center,
            style: FoodietText.bodySm.copyWith(color: FoodietColors.warm500),
          ),
        ),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return _EmptyState();
        }
        // 선택 그룹 자동 결정.
        final selected = groups.firstWhere(
          (g) => g.id == _selectedGroupId,
          orElse: () => groups.first,
        );
        if (selected.id != _selectedGroupId) {
          // build 직후 보정.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedGroupId = selected.id);
          });
        }
        return Column(
          children: [
            _GroupSelector(
              groups: groups,
              selectedId: selected.id,
              onTap: (g) => setState(() => _selectedGroupId = g.id),
            ),
            Expanded(child: _GroupFeed(groupId: selected.id)),
          ],
        );
      },
    );
  }

  String _short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.groups,
    required this.selectedId,
    required this.onTap,
  });
  final List<CommunityGroup> groups;
  final String selectedId;
  final void Function(CommunityGroup) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
            horizontal: FoodietShape.sp16, vertical: FoodietShape.sp8),
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = groups[i];
          final selected = g.id == selectedId;
          return Material(
            color: selected ? FoodietColors.coral100 : FoodietColors.cream100,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onTap(g),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(g.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      g.name,
                      style: FoodietText.bodySm.copyWith(
                        color: selected
                            ? FoodietColors.coral700
                            : FoodietColors.warm700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupFeed extends ConsumerWidget {
  const _GroupFeed({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupFeedProvider(groupId));
    final group = ref.watch(groupDetailProvider(groupId)).valueOrNull;

    return feedAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: FoodietColors.coral500),
      ),
      error: (e, _) => Center(
        child: Text('피드를 불러오지 못했어요.',
            style:
                FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
      ),
      data: (posts) {
        return RefreshIndicator(
          color: FoodietColors.coral500,
          onRefresh: () async {
            ref.invalidate(groupFeedProvider(groupId));
            await ref.read(groupFeedProvider(groupId).future);
          },
          child: posts.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 64),
                    Text('아직 공유된 식단이 없어요.\n첫 카드를 올려볼까?',
                        textAlign: TextAlign.center,
                        style: FoodietText.body
                            .copyWith(color: FoodietColors.warm500)),
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: FoodietColors.coral100,
                          foregroundColor: FoodietColors.coral700,
                        ),
                        onPressed: () => context.push('/community/share-today'),
                        child: const Text('오늘 식단 공유하기'),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      FoodietShape.sp16, FoodietShape.sp8,
                      FoodietShape.sp16, FoodietShape.sp40),
                  itemCount: posts.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: FoodietShape.sp12),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _GroupHeader(
                        group: group,
                        onShareToday: () =>
                            context.push('/community/share-today'),
                        onMembers: () => context
                            .push('/community/group/$groupId/members'),
                      );
                    }
                    final post = posts[i - 1];
                    return CommunityCard(
                      post: post,
                      onTap: () => context.push(
                          '/community/group/${post.groupId}/post/${post.id}'),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.onShareToday,
    required this.onMembers,
  });
  final CommunityGroup? group;
  final VoidCallback onShareToday;
  final VoidCallback onMembers;

  @override
  Widget build(BuildContext context) {
    if (group == null) {
      return const SizedBox(height: 64);
    }
    final g = group!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(g.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(g.name,
                        style: FoodietText.h3.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              if (g.description != null && g.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(g.description!,
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('구성원 ${g.memberCount ?? '-'}/${g.maxMembers}',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '구성원',
          icon: const Icon(Icons.people_outline,
              color: FoodietColors.warm700),
          onPressed: onMembers,
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: FoodietColors.coral100,
            foregroundColor: FoodietColors.coral700,
          ),
          onPressed: onShareToday,
          child: const Text('오늘 공유'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.groups_outlined,
              color: FoodietColors.warm500, size: 48),
          const SizedBox(height: 16),
          Text('아직 참여 중인 그룹이 없어요.',
              style: FoodietText.body.copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: 4),
          Text('새로 만들거나 공개 그룹을 찾아보자!',
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _ExploreSheetWrapper(),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: FoodietColors.cream50,
                  foregroundColor: FoodietColors.warm700,
                ),
                child: const Text('그룹 탐색'),
              ),
              FilledButton(
                onPressed: () => context.push('/community/new'),
                style: FilledButton.styleFrom(
                  backgroundColor: FoodietColors.coral500,
                  foregroundColor: Colors.white,
                ),
                child: const Text('새 그룹 만들기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 빈 상태에서 "그룹 탐색" 버튼 누르면 explore 탭으로 점프하기보다
/// 단순 화면으로 띄워주는 래퍼. (탭 인덱스 변경은 구조상 어색함)
class _ExploreSheetWrapper extends StatelessWidget {
  const _ExploreSheetWrapper();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('그룹 탐색')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: _ExploreInline(),
      ),
    );
  }
}

class _ExploreInline extends ConsumerStatefulWidget {
  const _ExploreInline();
  @override
  ConsumerState<_ExploreInline> createState() => _ExploreInlineState();
}

class _ExploreInlineState extends ConsumerState<_ExploreInline> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(publicGroupsProvider(_q));
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: '그룹 이름 검색',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: async.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: FoodietColors.coral500)),
            error: (_, __) =>
                const Center(child: Text('불러오지 못했어요.')),
            data: (groups) => groups.isEmpty
                ? const Center(child: Text('일치하는 그룹이 없어요.'))
                : ListView.separated(
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final g = groups[i];
                      return ListTile(
                        leading:
                            Text(g.emoji, style: const TextStyle(fontSize: 22)),
                        title: Text(g.name),
                        subtitle: g.description == null
                            ? null
                            : Text(g.description!),
                        onTap: () => context.push(
                            '/community/group/${g.id}'),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
