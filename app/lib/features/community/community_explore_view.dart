/// 커뮤니티 > 그룹 탐색 — 공개 그룹 검색/리스트 + 비밀번호 참여 진입.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/community_provider.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityExploreView extends ConsumerStatefulWidget {
  const CommunityExploreView({super.key});

  @override
  ConsumerState<CommunityExploreView> createState() =>
      _CommunityExploreViewState();
}

class _CommunityExploreViewState extends ConsumerState<CommunityExploreView> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(publicGroupsProvider(_query));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp16, FoodietShape.sp8,
          FoodietShape.sp16, FoodietShape.sp8),
      child: Column(
        children: [
          // Hero 검색 — 큰 친근한 안내 문구.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  FoodietColors.coral100.withValues(alpha: 0.55),
                  FoodietColors.cream50,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: FoodietColors.coral100.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('함께할 그룹을 찾아봐요',
                        style: FoodietText.title.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 4),
                    const Text('🔍', style: TextStyle(fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('관심사·목표가 비슷한 사람들과 매일 응원해요.',
                    style: FoodietText.caption.copyWith(
                        color: FoodietColors.warm500)),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: '그룹 이름 검색',
                    hintStyle: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm500),
                    prefixIcon: const Icon(Icons.search,
                        color: FoodietColors.warm500, size: 20),
                    filled: true,
                    fillColor: FoodietColors.cream00,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(
                          color: FoodietColors.coral500, width: 1.2),
                    ),
                  ),
                  onChanged: _onChanged,
                ),
                const SizedBox(height: 10),
                // 비공개 그룹 참여 — 인라인 버튼.
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push('/community/join'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            color: FoodietColors.coral500, size: 16),
                        const SizedBox(width: 4),
                        Text('비공개 그룹 코드로 참여',
                            style: FoodietText.bodySm.copyWith(
                                color: FoodietColors.coral500,
                                fontWeight: FontWeight.w700)),
                        const Icon(Icons.chevron_right,
                            color: FoodietColors.coral500, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FoodietShape.sp12),
          Expanded(
            child: async.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: FoodietColors.coral500),
              ),
              error: (e, _) => Center(
                child: Text('불러오지 못했어요.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      const SizedBox(height: 64),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _query.isEmpty
                                ? '아직 공개 그룹이 없어요.\n첫 그룹을 만들어볼까?'
                                : '"$_query" 와 일치하는 그룹이 없어요.',
                            textAlign: TextAlign.center,
                            style: FoodietText.body.copyWith(
                                color: FoodietColors.warm500),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _ActiveGroupsFooter(),
                    ],
                  );
                }
                return ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: groups.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    if (i == groups.length) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: _ActiveGroupsFooter(),
                      );
                    }
                    final g = groups[i];
                    return _PublicGroupTile(
                      emoji: g.emoji,
                      name: g.name,
                      description: g.description,
                      memberCount: g.memberCount,
                      onTap: () =>
                          context.push('/community/group/${g.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 그룹 탐색 하단 — "지금 이 그룹이 활발해요" 가로 스크롤 카드.
/// 멤버수 ≥ 2 인 공개 그룹을 인기순(멤버수 desc)으로 보여준다.
class _ActiveGroupsFooter extends ConsumerWidget {
  const _ActiveGroupsFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(publicGroupsProvider('')).valueOrNull ?? const [];
    final hot = [...all]
      ..sort((a, b) => (b.memberCount ?? 0).compareTo(a.memberCount ?? 0));
    final picks = hot.where((g) => (g.memberCount ?? 0) >= 1).take(8).toList();
    if (picks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('지금 이 그룹이 활발해요',
                style: FoodietText.title.copyWith(
                    color: FoodietColors.warm900,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            const Text('🔥', style: TextStyle(fontSize: 16)),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: picks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final g = picks[i];
              return _ActiveGroupCard(
                emoji: g.emoji,
                name: g.name,
                memberCount: g.memberCount ?? 0,
                onTap: () => context.push('/community/group/${g.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActiveGroupCard extends StatelessWidget {
  const _ActiveGroupCard({
    required this.emoji,
    required this.name,
    required this.memberCount,
    required this.onTap,
  });
  final String emoji;
  final String name;
  final int memberCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        onTap: onTap,
        child: Container(
          width: 138,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: FoodietColors.cream00,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 8),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoodietText.body.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.people_outline,
                      color: FoodietColors.coral500, size: 14),
                  const SizedBox(width: 4),
                  Text('$memberCount명',
                      style: FoodietText.caption.copyWith(
                          color: FoodietColors.coral500,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicGroupTile extends StatelessWidget {
  const _PublicGroupTile({
    required this.emoji,
    required this.name,
    this.description,
    this.memberCount,
    required this.onTap,
  });
  final String emoji;
  final String name;
  final String? description;
  final int? memberCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(FoodietShape.sp12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: FoodietText.body.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                    if (description != null && description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FoodietText.caption.copyWith(
                                color: FoodietColors.warm500)),
                      ),
                    if (memberCount != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.people_outline,
                                size: 12,
                                color: FoodietColors.warm500),
                            const SizedBox(width: 4),
                            Text('멤버 $memberCount명',
                                style: FoodietText.caption.copyWith(
                                    color: FoodietColors.warm500,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: FoodietColors.warm500),
            ],
          ),
        ),
      ),
    );
  }
}
