/// 커뮤니티 > 내 그룹 — 그룹 셀렉터 + 선택된 그룹 피드.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../theme/foodiet_tokens.dart';
import 'community_card.dart';
import 'community_comments_sheet.dart';

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
        // _selectedGroupId == null  →  "전체" 모드.
        // 그렇지 않으면 해당 그룹.
        return Column(
          children: [
            _GroupSelector(
              groups: groups,
              selectedId: _selectedGroupId,
              onTap: (id) => setState(() => _selectedGroupId = id),
            ),
            Expanded(
              child: _GroupFeed(
                groupId: _selectedGroupId,
                groups: groups,
              ),
            ),
          ],
        );
      },
    );
  }

  String _short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;
}

/// 가로 스크롤 chip 셀렉터. selectedId == null → "전체".
/// onTap(null) = 전체, onTap(groupId) = 해당 그룹.
class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.groups,
    required this.selectedId,
    required this.onTap,
  });
  final List<CommunityGroup> groups;
  final String? selectedId;
  final void Function(String?) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
            horizontal: FoodietShape.sp16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _ChipPill(
              label: '전체',
              selected: selectedId == null,
              onTap: () => onTap(null),
            );
          }
          final g = groups[i - 1];
          final selected = g.id == selectedId;
          return _ChipPill(
            emoji: g.emoji,
            label: g.name,
            selected: selected,
            onTap: () => onTap(g.id),
          );
        },
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({
    this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String? emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FoodietColors.coral500 : FoodietColors.cream100,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: FoodietText.caption.copyWith(
                  color: selected
                      ? Colors.white
                      : FoodietColors.warm700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupFeed extends ConsumerWidget {
  const _GroupFeed({required this.groupId, required this.groups});
  final String? groupId;
  final List<CommunityGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAll = groupId == null;
    final feedAsync = isAll
        ? ref.watch(allMyFeedsProvider)
        : ref.watch(groupFeedProvider(groupId!));
    final group =
        isAll ? null : ref.watch(groupDetailProvider(groupId!)).valueOrNull;
    // "전체" 모드에서 카드에 그룹 컨텍스트 표시할 수 있도록 lookup 맵.
    final groupById = {for (final g in groups) g.id: g};

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
        // 카드 빈 영역 탭 / 스크롤 시 키보드 자동 dismiss.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: RefreshIndicator(
            color: FoodietColors.coral500,
            onRefresh: () async {
              if (isAll) {
                ref.invalidate(allMyFeedsProvider);
                await ref.read(allMyFeedsProvider.future);
              } else {
                ref.invalidate(groupFeedProvider(groupId!));
                await ref.read(groupFeedProvider(groupId!).future);
              }
            },
            child: posts.isEmpty
                ? ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                          onPressed: () =>
                              context.push('/community/share-today'),
                          child: const Text('오늘 식단 공유하기'),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                        FoodietShape.sp16, FoodietShape.sp8,
                        FoodietShape.sp16, FoodietShape.sp40),
                    itemCount: isAll ? posts.length : posts.length + 1,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: FoodietShape.sp12),
                    itemBuilder: (_, i) {
                      if (!isAll && i == 0) {
                        return _GroupHeader(
                          group: group,
                          onShareToday: () =>
                              context.push('/community/share-today'),
                          onMembers: () => context
                              .push('/community/group/$groupId/members'),
                          onSettings: () => context
                              .push('/community/group/$groupId/settings'),
                        );
                      }
                      final postIndex = isAll ? i : i - 1;
                      final post = posts[postIndex];
                      final pg = groupById[post.groupId];
                      return CommunityCard(
                        post: post,
                        // "전체" 모드에서만 카드 헤더에 그룹 컨텍스트 표시.
                        groupEmoji: isAll ? pg?.emoji : null,
                        groupName: isAll ? pg?.name : null,
                        // 댓글 진입은 시트로 — 별도 라우트 X.
                        onTap: () =>
                            CommunityCommentsSheet.show(context, post),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

/// 그룹 헤더 — 이모지·이름·"활발한 그룹" 배지·설정 버튼 + 멤버 수/활동중 +
/// 멤버 아바타 스택. 그 다음 줄에 "오늘 공유" CTA.
class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({
    required this.group,
    required this.onShareToday,
    required this.onMembers,
    required this.onSettings,
  });
  final CommunityGroup? group;
  final VoidCallback onShareToday;
  final VoidCallback onMembers;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (group == null) {
      return const SizedBox(height: 8);
    }
    final g = group!;
    final myUserId = ref.watch(currentUserProvider)?.id;
    final isOwner = g.createdBy == myUserId;
    final membersAsync = ref.watch(groupMembersProvider(g.id));
    final members = membersAsync.valueOrNull ?? const <GroupMember>[];
    final active = members
        .where((m) => m.leftAt == null && m.kickedAt == null)
        .toList();
    // 7일 이내 가입한 사람 — 활동중 근사 (실제 활동 데이터 없음).
    final now = DateTime.now();
    final activeRecently = active.where((m) =>
        now.difference(m.joinedAt).inDays <= 7).length;
    // 멤버수 ≥ 3 이면 "활발한 그룹" 라벨.
    final isVibrant = active.length >= 3;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: FoodietColors.cream00,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
        boxShadow: [
          BoxShadow(
            color: FoodietColors.warm900.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 좌측 큰 이모지 원형.
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: FoodietColors.cream50,
                  shape: BoxShape.circle,
                ),
                child: Text(g.emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(g.name,
                              overflow: TextOverflow.ellipsis,
                              style: FoodietText.h3.copyWith(
                                  color: FoodietColors.warm900,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (isVibrant) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: FoodietColors.coral100,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🔥',
                                    style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 4),
                                Text('활발한 그룹',
                                    style: FoodietText.caption.copyWith(
                                        color: FoodietColors.coral700,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onMembers,
                      child: Row(
                        children: [
                          Text('멤버 ${active.length}명',
                              style: FoodietText.bodySm.copyWith(
                                  color: FoodietColors.warm700,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Text('|',
                              style: FoodietText.bodySm.copyWith(
                                  color: FoodietColors.cream100)),
                          const SizedBox(width: 8),
                          Text(
                              '활동중 ${activeRecently == 0 ? active.length : activeRecently}명',
                              style: FoodietText.bodySm.copyWith(
                                  color: FoodietColors.warm500)),
                          const SizedBox(width: 8),
                          _MemberAvatarStack(members: active),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isOwner)
                Material(
                  color: FoodietColors.cream50,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onSettings,
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.tune_rounded,
                          color: FoodietColors.warm700, size: 16),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 그라데이션 CTA — hero 카드 톤과 어울리게.
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onShareToday,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        FoodietColors.coral500,
                        FoodietColors.coral600,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: FoodietColors.coral500.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_outlined,
                          size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('오늘 식단 공유',
                          style: FoodietText.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 멤버 4명 아바타가 살짝 겹치며 나열, 그 이상은 +N 알.
class _MemberAvatarStack extends StatelessWidget {
  const _MemberAvatarStack({required this.members});
  final List<GroupMember> members;

  static const _palette = <Color>[
    FoodietColors.coral500,
    FoodietColors.coral300,
    FoodietColors.leaf500,
    FoodietColors.leaf300,
    FoodietColors.warm500,
  ];

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    final shown = members.take(4).toList();
    final more = members.length - shown.length;
    const size = 26.0;
    const overlap = 9.0;
    final width = size + (shown.length - 1) * (size - overlap) +
        (more > 0 ? (size - overlap) : 0);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: _AvatarCircle(
                size: size,
                color: _palette[i % _palette.length],
                label: _initial(shown[i].nickname),
              ),
            ),
          if (more > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: _AvatarCircle(
                size: size,
                color: FoodietColors.cream100,
                textColor: FoodietColors.warm700,
                label: '+$more',
                small: true,
              ),
            ),
        ],
      ),
    );
  }

  String _initial(String? nick) {
    if (nick == null || nick.isEmpty) return '?';
    return nick.characters.first;
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.size,
    required this.color,
    required this.label,
    this.textColor = Colors.white,
    this.small = false,
  });
  final double size;
  final Color color;
  final String label;
  final Color textColor;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: FoodietColors.cream00, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: small ? 9 : 11,
          fontWeight: FontWeight.w800,
        ),
      ),
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
          Text("아직 참여 중인 그룹이 없어요",
              style: FoodietText.body
                  .copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: 4),
          Text("그룹 탐색에서 찾아보거나 새 그룹을 만들어봐",
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm500)),
        ],
      ),
    );
  }
}
