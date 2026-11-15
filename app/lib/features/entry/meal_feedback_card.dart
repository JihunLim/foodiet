/// 기록 상세의 한 끼 피드백 카드 — 푸디 한마디(headline/good) + 다음 한 끼
/// 팁(next) + 1탭 보정 질문.
///
/// 스펙 F1. `entry.status == 'done' && entry.feedback != null` 일 때만 그린다
/// (구버전 기록·피드백 생성 실패면 아무것도 안 보임).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/entries_provider.dart';
import '../../services/app_events.dart';
import '../../services/meal_feedback_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/foodie_bubble.dart';

class MealFeedbackCard extends ConsumerStatefulWidget {
  const MealFeedbackCard({super.key, required this.entry});
  final Entry entry;

  @override
  ConsumerState<MealFeedbackCard> createState() => _MealFeedbackCardState();
}

class _MealFeedbackCardState extends ConsumerState<MealFeedbackCard> {
  /// 세션 안에서 같은 기록의 열람 이벤트를 한 번만 남긴다.
  static final Set<String> _viewLogged = {};

  /// 낙관적 표시 — 저장 중/직후 refetch 전에도 칩이 다시 눌리지 않게.
  String? _localAnswer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final f = widget.entry.feedback;
    if (widget.entry.status == 'done' &&
        f != null &&
        _viewLogged.add(widget.entry.id)) {
      AppEvents.log('feedback_viewed', {
        'has_check': f.check != null,
        'answered': f.check?.answered != null,
      });
    }
  }

  @override
  void didUpdateWidget(covariant MealFeedbackCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _localAnswer = null;
      _busy = false;
    }
  }

  Future<void> _answer(CheckOption option) async {
    final check = widget.entry.feedback?.check;
    if (_busy || check == null || (check.answered ?? _localAnswer) != null) {
      return;
    }
    setState(() {
      _busy = true;
      _localAnswer = option.label;
    });
    // 저장 중 화면을 떠나도 invalidate 가 돌도록 await 전에 잡아 둔다
    // (dispose 뒤 `ref` 사용은 StateError).
    final container = ProviderScope.containerOf(context, listen: false);
    final service = container.read(mealFeedbackServiceProvider);
    final entryId = widget.entry.id;
    try {
      await service.answer(widget.entry, option);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localAnswer = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지금은 반영이 안 됐어. 잠깐 뒤에 다시 눌러줘.')),
      );
      return;
    }
    // realtime 이 못 받아도 즉시 반영되도록 수동 invalidate.
    container.invalidate(entryDetailProvider(entryId));
    container.invalidate(todayEntriesProvider);
    container.invalidate(recentEntriesProvider);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final f = entry.feedback;
    if (entry.status != 'done' || f == null) return const SizedBox.shrink();
    final check = f.check;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FoodieBubble(headline: f.headline, why: f.good),
        if (f.next.trim().isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp8),
          _NextTip(text: f.next),
        ],
        if (check != null) ...[
          const SizedBox(height: FoodietShape.sp8),
          _CheckSection(
            check: check,
            answered: check.answered ?? _localAnswer,
            busy: _busy,
            onSelect: _answer,
          ),
        ],
      ],
    );
  }
}

class _NextTip extends StatelessWidget {
  const _NextTip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('다음 한 끼엔',
                    style: FoodietText.caption.copyWith(
                      color: FoodietColors.warm500,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(text,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckSection extends StatelessWidget {
  const _CheckSection({
    required this.check,
    required this.answered,
    required this.busy,
    required this.onSelect,
  });
  final FeedbackCheck check;
  final String? answered;
  final bool busy;
  final ValueChanged<CheckOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: answered != null ? _answeredView() : _questionView(),
    );
  }

  Widget _answeredView() {
    CheckOption? picked;
    for (final o in check.options) {
      if (o.label == answered) picked = o;
    }
    final adjusted = picked != null &&
        (picked.kcalFactor != 1.0 || picked.sodiumFactor != 1.0);
    return Row(
      children: [
        busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: FoodietColors.leaf700),
              )
            : const Icon(Icons.check_circle_rounded,
                size: 18, color: FoodietColors.leaf700),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: busy ? '반영하는 중이야…' : '반영했어 ✓',
                style: FoodietText.bodySm.copyWith(
                  color: FoodietColors.leaf700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: '  $answered${adjusted ? ' (조정됨)' : ''}',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _questionView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(check.question,
            style: FoodietText.body.copyWith(
              color: FoodietColors.warm900,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 2),
        Text('한 번 누르면 칼로리를 맞춰둘게.',
            style:
                FoodietText.caption.copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: FoodietShape.sp8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in check.options)
              _OptionChip(
                label: o.label,
                enabled: !busy,
                onTap: () => onSelect(o),
              ),
          ],
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: FoodietColors.coral300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label,
              style: FoodietText.bodySm.copyWith(
                color: FoodietColors.coral700,
                fontWeight: FontWeight.w700,
              )),
        ),
      ),
    );
  }
}
