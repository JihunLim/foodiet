/// 커뮤니티 피드의 식단 카드 위젯.
///
/// 기획서 §8.1. 표시 항목은 포스트 자체의 show_* 플래그를 따른다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';

class CommunityCard extends ConsumerWidget {
  const CommunityCard({
    super.key,
    required this.post,
    required this.onTap,
  });

  final CommunityPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reactionsAsync = ref.watch(postReactionsProvider(post.id));
    final reactions = reactionsAsync.valueOrNull ?? const <PostReaction>[];

    final myUserId = ref.watch(currentUserProvider)?.id;
    final myReactions =
        reactions.where((r) => r.userId == myUserId).map((r) => r.reaction).toSet();

    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(FoodietShape.sp16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(post: post),
              if (post.showPhotos && post.photoPaths.isNotEmpty) ...[
                const SizedBox(height: FoodietShape.sp12),
                _PhotoStrip(paths: post.photoPaths),
              ],
              const SizedBox(height: FoodietShape.sp12),
              _AchievementRow(post: post),
              if (post.caption != null && post.caption!.isNotEmpty) ...[
                const SizedBox(height: FoodietShape.sp8),
                Text(post.caption!,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm700)),
              ],
              const SizedBox(height: FoodietShape.sp12),
              _ReactionRow(
                post: post,
                reactions: reactions,
                myReactions: myReactions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateLabel(post.postDate);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: FoodietColors.coral100,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text('🍓', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(post.nickname ?? '구성원',
                  style: FoodietText.body.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700)),
              Text(dateLabel,
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500)),
            ],
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime date) {
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final d0 = DateTime(date.year, date.month, date.day);
    final diff = today0.difference(d0).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return DateFormat('M월 d일').format(date);
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final shown = paths.take(4).toList();
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
            child: SizedBox(
              width: 84,
              height: 84,
              child: SignedNetworkImage(
                path: shown[i],
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final color = switch (post.statusBadge) {
      'achieved' => FoodietColors.leaf500,
      'almost' => FoodietColors.coral500,
      _ => FoodietColors.warm500,
    };
    final emoji = switch (post.statusBadge) {
      'achieved' => '🎯',
      'almost' => '💪',
      _ => '🌱',
    };
    final label = switch (post.statusBadge) {
      'achieved' => '목표 달성!',
      'almost' => '거의 다 왔어',
      _ => '내일 다시!',
    };
    final pct = post.achievement?.toStringAsFixed(0);

    final macros = post.showMacros ? post.macros : null;
    final macroLabel = macros == null
        ? null
        : '탄 ${_g(macros['carb_g'])}g · 단 ${_g(macros['protein_g'])}g · 지 ${_g(macros['fat_g'])}g';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$emoji $label',
                style: FoodietText.body.copyWith(
                    color: color, fontWeight: FontWeight.w700)),
            if (pct != null) ...[
              const SizedBox(width: 8),
              Text('$pct%',
                  style: FoodietText.body.copyWith(
                      color: FoodietColors.warm700,
                      fontWeight: FontWeight.w700)),
            ],
          ],
        ),
        if (post.showKcal && post.totalKcal != null && post.targetKcal != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${post.totalKcal} / ${post.targetKcal} kcal',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500)),
          ),
        if (macroLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(macroLabel,
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ),
      ],
    );
  }

  String _g(dynamic v) {
    if (v is num) return v.round().toString();
    if (v is String) {
      final p = double.tryParse(v);
      if (p != null) return p.round().toString();
    }
    return '0';
  }
}

class _ReactionRow extends ConsumerWidget {
  const _ReactionRow({
    required this.post,
    required this.reactions,
    required this.myReactions,
  });

  final CommunityPost post;
  final List<PostReaction> reactions;
  final Set<ReactionKind> myReactions;

  Map<ReactionKind, int> _counts() {
    final counts = <ReactionKind, int>{
      for (final k in ReactionKind.values) k: 0
    };
    for (final r in reactions) {
      counts[r.reaction] = (counts[r.reaction] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _toggle(WidgetRef ref, ReactionKind kind) async {
    final svc = ref.read(communityServiceProvider);
    if (myReactions.contains(kind)) {
      await svc.removeReaction(postId: post.id, reaction: kind);
    } else {
      await svc.addReaction(postId: post.id, reaction: kind);
    }
    ref.invalidate(postReactionsProvider(post.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = _counts();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final k in ReactionKind.values)
          _Chip(
            emoji: k.emoji,
            count: counts[k] ?? 0,
            selected: myReactions.contains(k),
            onTap: () => _toggle(ref, k),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? FoodietColors.coral100 : FoodietColors.cream100;
    final fg = selected ? FoodietColors.coral700 : FoodietColors.warm700;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text('$count',
                    style: FoodietText.caption
                        .copyWith(color: fg, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
