/// 포스트 상세 — 사진 확대 + 응원 + 조언 스레드 + 신고/차단/삭제.
///
/// 조언 (Tip) 은 미달성 카드(status_badge='retry') 또는 'almost' 일 때만
/// 입력 가능. 달성 카드(status_badge='achieved') 에는 응원만.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';

class CommunityPostDetailPage extends ConsumerWidget {
  const CommunityPostDetailPage({
    super.key,
    required this.groupId,
    required this.postId,
  });
  final String groupId;
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(postDetailProvider(postId));
    final tipsAsync = ref.watch(postTipsProvider(postId));
    final reactionsAsync = ref.watch(postReactionsProvider(postId));
    final myUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        actions: [
          postAsync.maybeWhen(
            data: (post) {
              if (post == null) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: FoodietColors.warm700),
                onSelected: (key) =>
                    _handleMenu(context, ref, key, post, myUserId),
                itemBuilder: (_) {
                  final isMine = post.userId == myUserId;
                  return [
                    if (isMine)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('삭제'),
                      ),
                    if (!isMine)
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('신고'),
                      ),
                    if (!isMine)
                      const PopupMenuItem(
                        value: 'block',
                        child: Text('이 사용자 차단'),
                      ),
                  ];
                },
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: postAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: FoodietColors.coral500)),
          error: (_, __) =>
              const Center(child: Text('포스트를 찾을 수 없어요.')),
          data: (post) {
            if (post == null) {
              return const Center(child: Text('포스트를 찾을 수 없어요.'));
            }
            final tips = tipsAsync.valueOrNull ?? const <PostTip>[];
            final reactions =
                reactionsAsync.valueOrNull ?? const <PostReaction>[];
            return _PostBody(
              post: post,
              reactions: reactions,
              tips: tips,
              groupId: groupId,
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleMenu(BuildContext context, WidgetRef ref, String key,
      CommunityPost post, String? myUserId) async {
    final svc = ref.read(communityServiceProvider);
    if (key == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('포스트를 삭제할까?'),
          content: const Text('피드에서 즉시 사라져요. 되돌릴 수 없어요.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소')),
            TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: FoodietColors.danger),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('삭제')),
          ],
        ),
      );
      if (confirm != true) return;
      await svc.softDeletePost(post.id);
      invalidateCommunityFor(ref, groupId: groupId, postId: postId);
      if (!context.mounted) return;
      context.pop();
    } else if (key == 'report') {
      await _openReportSheet(context, ref, post);
    } else if (key == 'block') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${post.nickname ?? '구성원'} 차단'),
          content: const Text('차단하면 이 사용자의 카드와 조언이 더 이상 보이지 않아요.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('차단')),
          ],
        ),
      );
      if (confirm != true) return;
      await svc.blockUser(post.userId);
      invalidateCommunityFor(ref, groupId: groupId, postId: postId);
      ref.invalidate(blockedUsersProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('차단했어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      context.pop();
    }
  }
}

Future<void> _openReportSheet(
    BuildContext context, WidgetRef ref, CommunityPost post) async {
  ReportReason selected = ReportReason.inappropriate;
  final detail = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: FoodietColors.cream00,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(FoodietShape.radiusLg)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (_, setState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: FoodietColors.cream100,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('신고하기',
                    style: FoodietText.h3
                        .copyWith(color: FoodietColors.warm900)),
                const SizedBox(height: 8),
                Text('관련된 콘텐츠는 검토 후 조치돼요.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: 16),
                ...ReportReason.values.map((r) => RadioListTile<ReportReason>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.label),
                      value: r,
                      groupValue: selected,
                      activeColor: FoodietColors.coral500,
                      onChanged: (v) => setState(() {
                        if (v != null) selected = v;
                      }),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: detail,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: '추가 설명 (선택)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: FoodietColors.coral500,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('신고 제출'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  if (ok != true) return;
  try {
    await ref.read(communityServiceProvider).submitReport(
          targetType: ReportTargetType.post,
          targetId: post.id,
          reason: selected,
          detail: detail.text.trim().isEmpty ? null : detail.text.trim(),
          groupId: post.groupId,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('신고가 접수됐어요. 검토 후 조치할게요.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FoodietColors.warm700,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('신고 실패: $e'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FoodietColors.danger,
      ),
    );
  }
}

class _PostBody extends ConsumerWidget {
  const _PostBody({
    required this.post,
    required this.reactions,
    required this.tips,
    required this.groupId,
  });
  final CommunityPost post;
  final List<PostReaction> reactions;
  final List<PostTip> tips;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUserId = ref.watch(currentUserProvider)?.id;
    final myReactions = reactions
        .where((r) => r.userId == myUserId)
        .map((r) => r.reaction)
        .toSet();
    final canTip = post.statusBadge != 'achieved'; // 달성 카드엔 조언 X

    final reactionCounts = <ReactionKind, int>{
      for (final k in ReactionKind.values) k: 0,
    };
    for (final r in reactions) {
      reactionCounts[r.reaction] = (reactionCounts[r.reaction] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp20, 0, FoodietShape.sp20, FoodietShape.sp40),
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: FoodietColors.coral100,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('🍓', style: TextStyle(fontSize: 20)),
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
                  Text(DateFormat('M월 d일').format(post.postDate),
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                ],
              ),
            ),
          ],
        ),
        if (post.showPhotos && post.photoPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: post.photoPaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius:
                    BorderRadius.circular(FoodietShape.radiusMd),
                child: SizedBox(
                  width: 240,
                  child: SignedNetworkImage(
                    path: post.photoPaths[i],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _BadgeBlock(post: post),
        if (post.caption != null && post.caption!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(post.caption!,
              style: FoodietText.body.copyWith(color: FoodietColors.warm700)),
        ],
        const SizedBox(height: 16),
        _ReactionBar(
          counts: reactionCounts,
          mine: myReactions,
          onTap: (kind) => _toggleReaction(ref, kind, myReactions),
        ),
        const SizedBox(height: 24),
        if (canTip)
          _TipComposer(postId: post.id, groupId: groupId),
        const SizedBox(height: 12),
        if (tips.isEmpty)
          Center(
            child: Text(
              canTip
                  ? '아직 조언이 없어요. 첫 조언을 남겨볼까?'
                  : '응원해주는 사람이 있어요!',
              style:
                  FoodietText.bodySm.copyWith(color: FoodietColors.warm500),
            ),
          )
        else
          ...tips.map((t) => _TipRow(
                tip: t,
                groupId: groupId,
                isMine: t.userId == myUserId,
              )),
      ],
    );
  }

  Future<void> _toggleReaction(
      WidgetRef ref, ReactionKind kind, Set<ReactionKind> mine) async {
    final svc = ref.read(communityServiceProvider);
    if (mine.contains(kind)) {
      await svc.removeReaction(postId: post.id, reaction: kind);
    } else {
      await svc.addReaction(postId: post.id, reaction: kind);
    }
    ref.invalidate(postReactionsProvider(post.id));
  }
}

class _BadgeBlock extends StatelessWidget {
  const _BadgeBlock({required this.post});
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$emoji $label',
                style: FoodietText.h3.copyWith(
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
            padding: const EdgeInsets.only(top: 4),
            child: Text('${post.totalKcal} / ${post.targetKcal} kcal',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500)),
          ),
        if (post.showMacros && post.macros != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_macroLine(post.macros!),
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ),
      ],
    );
  }

  String _macroLine(Map<String, dynamic> m) {
    String g(dynamic v) {
      if (v is num) return v.round().toString();
      return '0';
    }

    return '탄 ${g(m['carb_g'])}g · 단 ${g(m['protein_g'])}g · 지 ${g(m['fat_g'])}g';
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.counts,
    required this.mine,
    required this.onTap,
  });
  final Map<ReactionKind, int> counts;
  final Set<ReactionKind> mine;
  final ValueChanged<ReactionKind> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final k in ReactionKind.values)
          OutlinedButton.icon(
            onPressed: () => onTap(k),
            icon: Text(k.emoji, style: const TextStyle(fontSize: 16)),
            label: Text(
              counts[k] == 0 ? '응원하기' : '${counts[k]}',
              style: FoodietText.bodySm.copyWith(
                  color: mine.contains(k)
                      ? FoodietColors.coral700
                      : FoodietColors.warm700,
                  fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: mine.contains(k)
                  ? FoodietColors.coral100
                  : FoodietColors.cream50,
              side: BorderSide(
                color: mine.contains(k)
                    ? FoodietColors.coral300
                    : FoodietColors.cream100,
              ),
            ),
          ),
      ],
    );
  }
}

class _TipComposer extends ConsumerStatefulWidget {
  const _TipComposer({required this.postId, required this.groupId});
  final String postId;
  final String groupId;

  @override
  ConsumerState<_TipComposer> createState() => _TipComposerState();
}

class _TipComposerState extends ConsumerState<_TipComposer> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  static const _bannedWords = <String>[
    '실패',
    '망쳤',
    '어겼',
    '어겨',
    '돼지',
    '뚱뚱',
    '못',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty || v.length > 100 || _sending) return;
    if (_hasBanned(v)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('따뜻한 조언으로 바꿔볼까? 푸디가 도와줄게!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warning,
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(communityServiceProvider)
          .addTip(postId: widget.postId, body: v);
      _ctrl.clear();
      ref.invalidate(postTipsProvider(widget.postId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('전송 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _hasBanned(String v) {
    final lower = v.toLowerCase();
    return _bannedWords.any((w) => lower.contains(w));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLength: 100,
              decoration: const InputDecoration(
                hintText: '따뜻한 조언 (100자 이내)',
                counterText: '',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            tooltip: '보내기',
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FoodietColors.coral500,
                    ),
                  )
                : const Icon(Icons.send_rounded,
                    color: FoodietColors.coral500),
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}

class _TipRow extends ConsumerWidget {
  const _TipRow({
    required this.tip,
    required this.groupId,
    required this.isMine,
  });
  final PostTip tip;
  final String groupId;
  final bool isMine;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('조언 삭제'),
        content: const Text('이 조언을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소')),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: FoodietColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(communityServiceProvider).softDeleteTip(tip.id);
    ref.invalidate(postTipsProvider(tip.postId));
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    ReportReason selected = ReportReason.inappropriate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('이 조언 신고'),
        content: StatefulBuilder(
          builder: (_, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: ReportReason.values
                .map((r) => RadioListTile<ReportReason>(
                      title: Text(r.label),
                      value: r,
                      groupValue: selected,
                      activeColor: FoodietColors.coral500,
                      onChanged: (v) {
                        if (v != null) setState(() => selected = v);
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('신고')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(communityServiceProvider).submitReport(
            targetType: ReportTargetType.tip,
            targetId: tip.id,
            reason: selected,
            groupId: groupId,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('신고가 접수됐어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FoodietColors.cream00,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.cream100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tip.nickname ?? '구성원',
                    style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                    DateFormat('M/d HH:mm').format(tip.createdAt),
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500)),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  icon: const Icon(Icons.more_horiz,
                      color: FoodietColors.warm500),
                  onPressed: () => showMenu<String>(
                    context: context,
                    position:
                        const RelativeRect.fromLTRB(200, 200, 0, 0),
                    items: [
                      if (isMine)
                        const PopupMenuItem(value: 'delete', child: Text('삭제')),
                      if (!isMine)
                        const PopupMenuItem(value: 'report', child: Text('신고')),
                    ],
                  ).then((v) {
                    if (!context.mounted) return;
                    if (v == 'delete') _delete(context, ref);
                    if (v == 'report') _report(context, ref);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(tip.body,
                style: FoodietText.body
                    .copyWith(color: FoodietColors.warm900)),
          ],
        ),
      ),
    );
  }
}
