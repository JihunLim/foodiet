/// 게시물/조언 신고 — 인스타식 사유 picker bottom sheet.
///
/// 사유는 한국어 9가지. DB enum 은 4개(inappropriate/spam/harassment/other)
/// 라 가장 가까운 값으로 매핑하고, 한국어 라벨은 reports.detail 에 함께
/// 저장해 관리자가 원래 카테고리를 잃지 않게 한다.
///
/// `submit_report` RPC 가 누적 2회 신고 시 자동 hidden_at 처리 + Edge
/// Function (community-report) 가 관리자 device 토큰으로 푸시 알림.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityReportSheet extends ConsumerStatefulWidget {
  const CommunityReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.groupId,
  });

  final ReportTargetType targetType;
  final String targetId;
  final String groupId;

  static Future<void> show(
    BuildContext context, {
    required ReportTargetType targetType,
    required String targetId,
    required String groupId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: FoodietColors.cream00,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityReportSheet(
        targetType: targetType,
        targetId: targetId,
        groupId: groupId,
      ),
    );
  }

  @override
  ConsumerState<CommunityReportSheet> createState() =>
      _CommunityReportSheetState();
}

class _CommunityReportSheetState extends ConsumerState<CommunityReportSheet> {
  bool _submitting = false;

  Future<void> _submit(ReportReasonUi reason) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(communityServiceProvider).submitReport(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason.dbReason,
            detail: reason.label,
            groupId: widget.groupId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('신고 접수됐어요. 관리자가 확인합니다 — "${reason.label}"'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('신고 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      height: size.height * 0.86,
      child: Column(
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 32),
                const Spacer(),
                Text('신고하기',
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
          // 인트로.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              children: [
                Text(
                  _intro,
                  textAlign: TextAlign.center,
                  style: FoodietText.h3.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  '회원님의 신고는 익명으로 처리돼요. 누군가 위급한 상황에 있다고 '
                  '생각된다면 즉시 응급 서비스 기관에 연락해주세요.',
                  textAlign: TextAlign.center,
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.warm500, height: 1.4),
                ),
              ],
            ),
          ),
          // 사유 리스트.
          Expanded(
            child: IgnorePointer(
              ignoring: _submitting,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: ReportReasonUi.values.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1, color: FoodietColors.cream100),
                itemBuilder: (_, i) {
                  final r = ReportReasonUi.values[i];
                  return InkWell(
                    onTap: () => _submit(r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(r.label,
                                style: FoodietText.body.copyWith(
                                    color: FoodietColors.warm900,
                                    fontWeight: FontWeight.w500)),
                          ),
                          const Icon(Icons.chevron_right,
                              color: FoodietColors.warm500, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_submitting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: FoodietColors.coral500),
              ),
            ),
        ],
      ),
    );
  }

  String get _intro {
    switch (widget.targetType) {
      case ReportTargetType.post:
        return '이 게시물을 신고하는 이유';
      case ReportTargetType.tip:
        return '이 댓글을 신고하는 이유';
      case ReportTargetType.user:
        return '이 사용자를 신고하는 이유';
    }
  }
}
