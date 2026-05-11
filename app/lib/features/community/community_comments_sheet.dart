/// 카드에서 직접 띄우는 댓글(조언) 바텀시트 — 인스타 스타일.
///
/// `CommunityCommentsSheet.show(context, post)` 한 줄로 호출. 별도 라우트
/// 이동 없이 시트 안에서 댓글 보기 + 입력까지 처리한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityCommentsSheet extends ConsumerStatefulWidget {
  const CommunityCommentsSheet({super.key, required this.post});
  final CommunityPost post;

  static Future<void> show(BuildContext context, CommunityPost post) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // useSafeArea: true → 시트가 status bar / 노치 영역을 침범하지 않음.
      useSafeArea: true,
      // useRootNavigator: true → Scaffold 의 FAB(중앙 카메라) 위에 띄워서
      //   sheet 가 떠 있을 때 카메라 버튼이 가려지게 한다.
      useRootNavigator: true,
      backgroundColor: FoodietColors.cream00,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityCommentsSheet(post: post),
    );
  }

  @override
  ConsumerState<CommunityCommentsSheet> createState() =>
      _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState
    extends ConsumerState<CommunityCommentsSheet> {
  static const _bannedWords = <String>[
    '실패', '망쳤', '어겼', '어겨', '돼지', '뚱뚱', '못',
  ];

  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  bool _hasText = false;
  // 좋아요 토글 in-flight set — 빠른 더블탭으로 같은 tip 에 중복 RPC 가
  // 안 가게 막는다.
  final Set<String> _likeBusy = <String>{};

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _hasBanned(String v) =>
      _bannedWords.any((w) => v.contains(w));

  Future<void> _send() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty || v.length > 100 || _sending) return;
    if (_hasBanned(v)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('따뜻한 조언으로 바꿔볼까? 푸디가 도와줄게!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(communityServiceProvider)
          .addTip(postId: widget.post.id, body: v);
      if (!mounted) return;
      _ctrl.clear();
      ref.invalidate(postTipsProvider(widget.post.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('조언 등록 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipsAsync = ref.watch(postTipsProvider(widget.post.id));
    final likesAsync = ref.watch(postTipLikesProvider(widget.post.id));
    final myUserId = ref.watch(currentUserProvider)?.id;
    // 키보드 올라온 만큼 sheet 콘텐츠를 위로 push.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    // 키보드 올라오면 sheet 자체 height 를 줄여서 콘텐츠가 노치까지 침범
    // 하지 않게 한다 (useSafeArea: true 로 시작 좌표는 이미 노치 아래지만,
    // 콘텐츠가 그 안쪽에서 너무 높이 올라가지 않도록 추가 클램프).
    final keyboardOpen = keyboard > 0;
    final sheetHeight =
        keyboardOpen ? size.height * 0.55 : size.height * 0.72;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들.
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FoodietColors.cream100,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            // 헤더.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  const Spacer(),
                  Text('댓글',
                      style: FoodietText.title.copyWith(
                          color: FoodietColors.warm900,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: FoodietColors.warm700),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: FoodietColors.cream100),
            // 리스트.
            Expanded(
              child: tipsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: FoodietColors.coral500)),
                error: (e, _) => Center(
                  child: Text('댓글을 불러오지 못했어요.',
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.warm500)),
                ),
                data: (tips) {
                  final visible =
                      tips.where((t) => t.isVisible).toList();
                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('💬',
                                style: TextStyle(fontSize: 36)),
                            const SizedBox(height: 8),
                            Text('아직 조언이 없어요.',
                                style: FoodietText.body.copyWith(
                                    color: FoodietColors.warm700)),
                            const SizedBox(height: 4),
                            Text('첫 따뜻한 조언을 남겨볼까?',
                                style: FoodietText.bodySm.copyWith(
                                    color: FoodietColors.warm500)),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final t = visible[i];
                      final likeStat = likesAsync.valueOrNull?[t.id] ??
                          (count: 0, mine: false);
                      return _CommentRow(
                        tip: t,
                        isMine: t.userId == myUserId,
                        likeCount: likeStat.count,
                        liked: likeStat.mine,
                        onToggleLike: () => _toggleLike(t, likeStat.mine),
                        onEdit: () => _editTip(t),
                        onDelete: () => _deleteTip(t),
                      );
                    },
                  );
                },
              ),
            ),
            // 입력 row — 하단 고정.
            Container(
              decoration: const BoxDecoration(
                color: FoodietColors.cream00,
                border: Border(
                  top: BorderSide(color: FoodietColors.cream100),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        maxLength: 100,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm900),
                        decoration: InputDecoration(
                          hintText: '대화에 참여하세요...',
                          hintStyle: FoodietText.bodySm.copyWith(
                              color: FoodietColors.warm500),
                          isDense: true,
                          filled: true,
                          fillColor: FoodietColors.cream50,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed:
                            (_hasText && !_sending) ? _send : null,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: FoodietColors.coral500),
                              )
                            : Icon(Icons.send_rounded,
                                size: 22,
                                color: _hasText
                                    ? FoodietColors.coral500
                                    : FoodietColors.warm500
                                        .withValues(alpha: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(PostTip t, bool currentlyLiked) async {
    if (_likeBusy.contains(t.id)) return;
    _likeBusy.add(t.id);
    HapticFeedback.lightImpact();
    final svc = ref.read(communityServiceProvider);
    try {
      if (currentlyLiked) {
        await svc.unlikeTip(t.id);
      } else {
        await svc.likeTip(t.id);
      }
    } catch (_) {
      // 실패는 invalidate 후 서버 진실 복원.
    } finally {
      _likeBusy.remove(t.id);
      if (mounted) ref.invalidate(postTipLikesProvider(widget.post.id));
    }
  }

  Future<void> _editTip(PostTip t) async {
    final ctrl = TextEditingController(text: t.body);
    final newBody = await showDialog<String?>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('조언 수정'),
        content: TextField(
          controller: ctrl,
          maxLength: 100,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: '따뜻한 조언을 남겨봐',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(null),
              child: const Text('취소')),
          TextButton(
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(ctrl.text.trim()),
              child: const Text('저장')),
        ],
      ),
    );
    ctrl.dispose();
    if (newBody == null || newBody.isEmpty || newBody == t.body) return;
    if (newBody.length > 100) return;
    if (_hasBanned(newBody)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('따뜻한 조언으로 바꿔볼까? 푸디가 도와줄게!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      return;
    }
    try {
      await ref
          .read(communityServiceProvider)
          .updateTip(tipId: t.id, body: newBody);
      if (!mounted) return;
      ref.invalidate(postTipsProvider(widget.post.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('수정 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  Future<void> _deleteTip(PostTip t) async {
    // builder 의 dialogCtx 로 명시적 pop — outer context 가 stale 하거나
    // sheet ListView 안에서 item 이 dispose 됐을 때도 dialog 가 안 닫히는
    // 케이스 회피. rootNavigator: true 도 명시해서 dialog 가 root navigator
    // 에 push 되도록 보장 (showDialog default 이지만 안전 마진).
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('조언 삭제'),
        content: const Text('이 조언을 삭제할까요?'),
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
    if (confirm != true || !mounted) return;
    HapticFeedback.lightImpact();
    // 낙관적으로 invalidate 먼저 (UI 즉시 갱신) → 서버 호출은 백그라운드.
    // 사용자가 "삭제 후 lag" 로 느끼던 것 제거.
    ref.invalidate(postTipsProvider(widget.post.id));
    try {
      await ref.read(communityServiceProvider).softDeleteTip(t.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
      ref.invalidate(postTipsProvider(widget.post.id));
    }
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.tip,
    required this.isMine,
    required this.likeCount,
    required this.liked,
    required this.onToggleLike,
    required this.onEdit,
    required this.onDelete,
  });
  final PostTip tip;
  final bool isMine;
  final int likeCount;
  final bool liked;
  final VoidCallback onToggleLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final nick = tip.nickname ?? '구성원';
    final initial = nick.isEmpty ? '?' : nick.characters.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [FoodietColors.coral300, FoodietColors.coral500],
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
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
                          style: FoodietText.bodySm.copyWith(
                              color: FoodietColors.warm900,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(_relativeTime(tip.createdAt),
                        style: FoodietText.caption.copyWith(
                            color: FoodietColors.warm500,
                            fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(tip.body,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm900, height: 1.35)),
                if (isMine)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _MineAction(label: '수정', onTap: onEdit),
                        const SizedBox(width: 12),
                        _MineAction(label: '삭제', onTap: onDelete),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 인스타식 우측 하트.
          SizedBox(
            width: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  constraints: const BoxConstraints.tightFor(
                      width: 28, height: 28),
                  onPressed: onToggleLike,
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: liked
                        ? FoodietColors.coral500
                        : FoodietColors.warm500,
                  ),
                ),
                if (likeCount > 0)
                  Text('$likeCount',
                      style: FoodietText.caption.copyWith(
                          color: FoodietColors.warm500,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays == 1) return '어제';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('M/d').format(when);
  }
}

/// 본인 댓글 아래 작고 얇은 메타 액션 (수정 / 삭제).
class _MineAction extends StatelessWidget {
  const _MineAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(label,
            style: FoodietText.caption.copyWith(
                color: FoodietColors.warm500,
                fontWeight: FontWeight.w400,
                fontSize: 11)),
      ),
    );
  }
}
