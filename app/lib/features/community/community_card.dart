/// 커뮤니티 피드의 식단 카드 — 인스타그램 게시글 스타일.
///
/// 카드 안에서 모든 게 보이고/조작된다:
///   · 사진은 좌우 스와이프 (PageView + dot indicator)
///   · 반응 칩으로 응원
///   · 조언(tip) 상위 2개는 카드에 인라인. 더 있으면 "조언 N개 더 보기"
///   · 조언 입력란 인라인 — 제출 즉시 캐시 갱신
///
/// onTap 은 "조언 N개 더 보기" 진입 콜백으로만 사용. 카드 빈 영역 탭으로
/// 별도 페이지를 열지는 않는다 (피드에서 디테일 페이지 왕복 없애기 위함).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';
import 'community_comments_sheet.dart';
import 'community_report_sheet.dart';

class CommunityCard extends ConsumerWidget {
  const CommunityCard({
    super.key,
    required this.post,
    required this.onTap,
    this.groupEmoji,
    this.groupName,
  });

  final CommunityPost post;

  /// "조언 N개 더 보기" 누를 때 — 디테일 페이지로 이동.
  final VoidCallback onTap;

  /// "전체" 모드에서 카드에 그룹 컨텍스트 (이모지/이름) 를 표시.
  final String? groupEmoji;
  final String? groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reactionsAsync = ref.watch(postReactionsProvider(post.id));
    final tipsAsync = ref.watch(postTipsProvider(post.id));
    final reactions = reactionsAsync.valueOrNull ?? const <PostReaction>[];
    final tips = tipsAsync.valueOrNull ?? const <PostTip>[];

    final myUserId = ref.watch(currentUserProvider)?.id;
    final myReactions = reactions
        .where((r) => r.userId == myUserId)
        .map((r) => r.reaction)
        .toSet();

    final hasPhoto = post.showPhotos && post.photoPaths.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: FoodietColors.cream00,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                FoodietShape.sp16, FoodietShape.sp12,
                FoodietShape.sp16, FoodietShape.sp12),
            child: _Header(
              post: post,
              groupEmoji: groupEmoji,
              groupName: groupName,
            ),
          ),
          if (hasPhoto) _PhotoStrip(paths: post.photoPaths),
          Padding(
            padding: EdgeInsets.fromLTRB(
                FoodietShape.sp16,
                hasPhoto ? FoodietShape.sp12 : 0,
                FoodietShape.sp16,
                FoodietShape.sp16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: FoodietShape.sp8),
                _CommentEntry(
                  post: post,
                  tips: tips,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 인스타/카톡 피드 헤더 — "누가 공유했는지"가 즉시 보이는 게 핵심.
/// 우측에 3-dot 메뉴 (본인이면 삭제, 아니면 신고/차단).
class _Header extends ConsumerWidget {
  const _Header({
    required this.post,
    this.groupEmoji,
    this.groupName,
  });
  final CommunityPost post;
  final String? groupEmoji;
  final String? groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = _dateLabel(post.postDate);
    final nick = post.nickname ?? '구성원';
    final initial = _initial(nick);
    final hasGroup = groupName != null && groupName!.isNotEmpty;
    final myUserId = ref.watch(currentUserProvider)?.id;
    final isMine = post.userId == myUserId;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [FoodietColors.coral300, FoodietColors.coral500],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: FoodietColors.coral500.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(nick,
                        overflow: TextOverflow.ellipsis,
                        style: FoodietText.title.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  Text('공유함',
                      style: FoodietText.bodySm.copyWith(
                          color: FoodietColors.warm500,
                          fontWeight: FontWeight.w400)),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(dateLabel,
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                  if (hasGroup) ...[
                    const SizedBox(width: 6),
                    Text('·',
                        style: FoodietText.caption
                            .copyWith(color: FoodietColors.warm500)),
                    const SizedBox(width: 6),
                    if (groupEmoji != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Text(groupEmoji!,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    Flexible(
                      child: Text(groupName!,
                          overflow: TextOverflow.ellipsis,
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.coral500,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // 우측 3-dot 메뉴 — 본인이면 삭제, 아니면 신고/차단.
        SizedBox(
          width: 32,
          height: 32,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz,
                color: FoodietColors.warm500, size: 20),
            tooltip: '옵션',
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (key) =>
                _handleMenu(context, ref, key, isMine: isMine),
            itemBuilder: (_) => [
              if (isMine)
                const PopupMenuItem(value: 'delete', child: Text('삭제')),
              if (!isMine)
                const PopupMenuItem(value: 'report', child: Text('신고')),
              if (!isMine)
                const PopupMenuItem(
                    value: 'block', child: Text('이 사용자 차단')),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String key, {
    required bool isMine,
  }) async {
    if (key == 'report') {
      await CommunityReportSheet.show(
        context,
        targetType: ReportTargetType.post,
        targetId: post.id,
        groupId: post.groupId,
      );
    } else if (key == 'delete' && isMine) {
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('게시물 삭제'),
          content: const Text('이 게시물을 삭제할까요? 같이 달린 응원·조언도 함께 사라져요.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('취소')),
            TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: FoodietColors.danger),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('삭제')),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await ref.read(communityServiceProvider).softDeletePost(post.id);
        if (!context.mounted) return;
        invalidateCommunityFor(ref,
            groupId: post.groupId, postId: post.id);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 실패: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FoodietColors.danger,
          ),
        );
      }
    } else if (key == 'block') {
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('이 사용자 차단'),
          content: const Text('이 사용자의 게시물·조언이 더 이상 보이지 않아요.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('취소')),
            TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: FoodietColors.danger),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('차단')),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await ref.read(communityServiceProvider).blockUser(post.userId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차단했어요.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FoodietColors.warm700,
          ),
        );
        invalidateCommunityFor(ref, groupId: post.groupId);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('차단 실패: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FoodietColors.danger,
          ),
        );
      }
    }
  }

  String _initial(String nick) {
    if (nick.isEmpty) return '?';
    return nick.characters.first;
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

/// 인스타식 사진 스와이프 — PageView + dot indicator.
class _PhotoStrip extends StatefulWidget {
  const _PhotoStrip({required this.paths});
  final List<String> paths;

  @override
  State<_PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<_PhotoStrip> {
  late final PageController _pc;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paths.isEmpty) return const SizedBox.shrink();
    final multi = widget.paths.length > 1;
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.paths.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) => SignedNetworkImage(
              path: widget.paths[i],
              fit: BoxFit.cover,
              // 카드 폭 정사각 — 픽셀 디코드 800px 면 충분, 메모리 절약.
              cacheWidth: 800,
              cacheHeight: 800,
            ),
          ),
          if (multi)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${_idx + 1}/${widget.paths.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          if (multi)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.paths.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _idx ? 8 : 6,
                      height: i == _idx ? 8 : 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _idx
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
        ],
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

    // 링 진행도 — achievement 가 100 이상이어도 시각적으로 1.0 캡.
    final ringPct = ((post.achievement ?? 0) / 100).clamp(0.0, 1.0);

    final macros = post.showMacros ? post.macros : null;
    final macroLabel = macros == null
        ? null
        : '탄 ${_g(macros['carb_g'])}g · 단 ${_g(macros['protein_g'])}g · 지 ${_g(macros['fat_g'])}g';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AchievementRing(value: ringPct, ringColor: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$emoji $label',
                  style: FoodietText.body.copyWith(
                      color: color, fontWeight: FontWeight.w700)),
              if (post.showKcal &&
                  post.totalKcal != null &&
                  post.targetKcal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      '${post.totalKcal} / ${post.targetKcal} kcal',
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
          ),
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

/// 가운데 딸기, 외곽 링이 진행도(0..1)만큼 코랄/리프 색으로 차오른다.
/// 배경 트랙은 cream100 의 옅은 회색.
class _AchievementRing extends StatelessWidget {
  const _AchievementRing({required this.value, required this.ringColor});
  final double value;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 배경 트랙.
          const SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(FoodietColors.cream100),
              backgroundColor: Colors.transparent,
            ),
          ),
          // 진행 호.
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation(ringColor),
              backgroundColor: Colors.transparent,
            ),
          ),
          const Text('🍓', style: TextStyle(fontSize: 22)),
        ],
      ),
    );
  }
}

/// 응원 칩 줄 — 누르면 즉시(낙관적) chip 색·카운트 갱신 + Overlay 로
/// 종류별 애니메이션 분출. 서버 호출은 백그라운드.
class _ReactionRow extends ConsumerStatefulWidget {
  const _ReactionRow({
    required this.post,
    required this.reactions,
    required this.myReactions,
  });

  final CommunityPost post;
  final List<PostReaction> reactions;
  final Set<ReactionKind> myReactions;

  @override
  ConsumerState<_ReactionRow> createState() => _ReactionRowState();
}

class _ReactionRowState extends ConsumerState<_ReactionRow> {
  late Set<ReactionKind> _optimistic;
  // chip 별 위치 측정용 키 — flight 좌표 기준점.
  final Map<ReactionKind, GlobalKey> _keys = {
    for (final k in ReactionKind.values) k: GlobalKey()
  };

  @override
  void initState() {
    super.initState();
    _optimistic = {...widget.myReactions};
  }

  @override
  void didUpdateWidget(covariant _ReactionRow old) {
    super.didUpdateWidget(old);
    // 서버 응답으로 reactions / myReactions 가 갱신되면 optimistic 재동기.
    if (old.myReactions.length != widget.myReactions.length ||
        !old.myReactions.containsAll(widget.myReactions) ||
        !widget.myReactions.containsAll(old.myReactions)) {
      _optimistic = {...widget.myReactions};
    }
  }

  Map<ReactionKind, int> _serverCounts() {
    final counts = <ReactionKind, int>{
      for (final k in ReactionKind.values) k: 0
    };
    for (final r in widget.reactions) {
      counts[r.reaction] = (counts[r.reaction] ?? 0) + 1;
    }
    return counts;
  }

  /// 낙관적 토글이 반영된 카운트.
  Map<ReactionKind, int> _displayCounts() {
    final base = _serverCounts();
    for (final k in ReactionKind.values) {
      final hadIt = widget.myReactions.contains(k);
      final hasIt = _optimistic.contains(k);
      if (!hadIt && hasIt) base[k] = (base[k] ?? 0) + 1;
      if (hadIt && !hasIt) base[k] = (base[k] ?? 0) - 1;
      if ((base[k] ?? 0) < 0) base[k] = 0;
    }
    return base;
  }

  Future<void> _toggle(ReactionKind kind) async {
    final hadIt = _optimistic.contains(kind);
    setState(() {
      if (hadIt) {
        _optimistic.remove(kind);
      } else {
        _optimistic.add(kind);
      }
    });
    HapticFeedback.lightImpact();
    if (!hadIt) _flight(kind);

    try {
      final svc = ref.read(communityServiceProvider);
      if (hadIt) {
        await svc.removeReaction(postId: widget.post.id, reaction: kind);
      } else {
        await svc.addReaction(postId: widget.post.id, reaction: kind);
      }
    } catch (_) {
      if (!mounted) return;
      // 실패 — 롤백.
      setState(() {
        if (hadIt) {
          _optimistic.add(kind);
        } else {
          _optimistic.remove(kind);
        }
      });
    } finally {
      if (mounted) ref.invalidate(postReactionsProvider(widget.post.id));
    }
  }

  void _flight(ReactionKind kind) {
    final ctx = _keys[kind]?.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero);
    final origin = Offset(
      pos.dx + box.size.width / 2,
      pos.dy + box.size.height / 2,
    );
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) {
      return _ReactionFlight(
        origin: origin,
        kind: kind,
        onDone: () => entry.remove(),
      );
    });
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _displayCounts();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final k in ReactionKind.values)
          _Chip(
            chipKey: _keys[k]!,
            emoji: k.emoji,
            count: counts[k] ?? 0,
            selected: _optimistic.contains(k),
            onTap: () => _toggle(k),
          ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.chipKey,
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final Key chipKey;
  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.25), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.25, end: 0.95), weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 0.95, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _handleTap() {
    _bounce.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    // 인스타식 — 박스/배경 없이 emoji + 숫자만. 선택 시 카운트 색만 코랄.
    final fg = widget.selected
        ? FoodietColors.coral500
        : FoodietColors.warm700;
    return ScaleTransition(
      scale: _scale,
      child: Material(
        key: widget.chipKey,
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          // 코랄 톤 ripple/highlight 가 emoji 분출 후 뒤에 노란 띠처럼 보이는
          // 케이스 방지 — bounce scale 자체로 피드백 충분.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: _handleTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.emoji,
                    style: const TextStyle(fontSize: 18)),
                if (widget.count > 0) ...[
                  const SizedBox(width: 4),
                  Text('${widget.count}',
                      style: FoodietText.bodySm.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 위 Overlay 에 떠올라 반응 종류별 다른 효과를 보여주는 위젯.
///   · fire 🔥 — 큰 불꽃이 위로 솟구치며 크기↑·페이드
///   · clap 👏 — 양옆으로 박수 두 개가 튀어나가며 살짝 회전
///   · heart 💚 — 하트 풍선 5개가 좌우로 흔들리며 위로 떠오름
class _ReactionFlight extends StatefulWidget {
  const _ReactionFlight({
    required this.origin,
    required this.kind,
    required this.onDone,
  });

  final Offset origin;
  final ReactionKind kind;
  final VoidCallback onDone;

  @override
  State<_ReactionFlight> createState() => _ReactionFlightState();
}

class _ReactionFlightState extends State<_ReactionFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: switch (widget.kind) {
        ReactionKind.fire => const Duration(milliseconds: 700),
        ReactionKind.clap => const Duration(milliseconds: 600),
        ReactionKind.heart => const Duration(milliseconds: 1300),
      },
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          return Stack(
            children: switch (widget.kind) {
              ReactionKind.fire => _fire(t),
              ReactionKind.clap => _clap(t),
              ReactionKind.heart => _heart(t),
            },
          );
        },
      ),
    );
  }

  // ── 불꽃 — 큰 🔥 + 작은 불꽃 3개가 위로 살짝 튀어 오르며 사라진다.
  List<Widget> _fire(double t) {
    final widgets = <Widget>[];
    // 메인 큰 불꽃.
    final mainDy = -55 * Curves.easeOut.transform(t);
    final mainScale = 1.0 + 1.4 * Curves.easeOutCubic.transform(t);
    final mainOpacity = (1.0 - t).clamp(0.0, 1.0);
    widgets.add(Positioned(
      left: widget.origin.dx - 28,
      top: widget.origin.dy + mainDy - 28,
      child: Opacity(
        opacity: mainOpacity,
        child: Transform.scale(
          scale: mainScale,
          child: const Text('🔥', style: TextStyle(fontSize: 36)),
        ),
      ),
    ));
    // 양옆/위 작은 불꽃 스파크.
    for (int i = 0; i < 3; i++) {
      final angle = (i - 1) * 0.7; // -0.7, 0, 0.7 rad
      final dist = 36 * Curves.easeOutCubic.transform(t);
      final dx = math.sin(angle) * dist;
      final dy = -math.cos(angle) * dist - 20 * t;
      final op = (1.0 - t * 1.2).clamp(0.0, 1.0);
      final scale = 0.4 + 0.5 * t;
      widgets.add(Positioned(
        left: widget.origin.dx + dx - 10,
        top: widget.origin.dy + dy - 10,
        child: Opacity(
          opacity: op,
          child: Transform.scale(
            scale: scale,
            child: const Text('🔥', style: TextStyle(fontSize: 20)),
          ),
        ),
      ));
    }
    return widgets;
  }

  // ── 박수 — 양옆으로 두 손이 튀어나가며 회전 + 위로 살짝.
  List<Widget> _clap(double t) {
    final out = 38 * Curves.easeOutCubic.transform(t);
    final dy = -16 * (4 * t * (1 - t)); // parabola
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    final rot = 0.5 * math.sin(t * math.pi * 4);
    Widget hand({required bool right}) {
      return Positioned(
        left: widget.origin.dx + (right ? out : -out) - 18,
        top: widget.origin.dy + dy - 18,
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: right ? rot : -rot,
            child: Transform.scale(
              scaleX: right ? 1 : -1,
              child: const Text('👏', style: TextStyle(fontSize: 32)),
            ),
          ),
        ),
      );
    }
    return [hand(right: false), hand(right: true)];
  }

  // ── 하트 풍선 — 5개가 시간차로 위로 떠오르며 좌우 흔들림.
  List<Widget> _heart(double t) {
    final widgets = <Widget>[];
    for (int i = 0; i < 5; i++) {
      final delay = i * 0.10;
      final localT = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (localT == 0) continue;
      final dyBase = -150 * Curves.easeOut.transform(localT);
      final dx = (i % 2 == 0 ? -1 : 1) *
          24 *
          math.sin(localT * math.pi * 1.5);
      final opacity = (1.0 - localT).clamp(0.0, 1.0);
      // 약하게 부풀어 올랐다가 줄어듦.
      final scale = 0.6 +
          0.6 * Curves.easeOut.transform(math.sin(localT * math.pi));
      widgets.add(Positioned(
        left: widget.origin.dx + dx - 16,
        top: widget.origin.dy + dyBase - 16,
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: const Text('💚', style: TextStyle(fontSize: 30)),
          ),
        ),
      ));
    }
    return widgets;
  }
}

/// 카드 하단의 단일 댓글 진입 — 첫 번째 조언 1개 미리보기 + 카운트.
/// 누르면 modal bottom sheet (CommunityCommentsSheet) 가 떠서 모든 댓글
/// 보기 + 입력까지 한 곳에서 처리. 새 라우트로 이동하지 않는다.
class _CommentEntry extends StatelessWidget {
  const _CommentEntry({required this.post, required this.tips});
  final CommunityPost post;
  final List<PostTip> tips;

  @override
  Widget build(BuildContext context) {
    final visible = tips.where((t) => t.isVisible).toList();
    final count = visible.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => CommunityCommentsSheet.show(context, post),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: count == 0
            ? Text('첫 따뜻한 조언을 남겨볼까?',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 미리보기 1줄 — 닉네임 + 본문 (인스타식).
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: FoodietText.bodySm.copyWith(
                          color: FoodietColors.warm900, height: 1.3),
                      children: [
                        TextSpan(
                          text: '${visible.first.nickname ?? '구성원'}  ',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: visible.first.body,
                          style: const TextStyle(
                              fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                  if (count > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('댓글 $count개 모두 보기',
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.warm500,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
      ),
    );
  }
}
