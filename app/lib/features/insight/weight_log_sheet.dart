/// 체중 기록 bottom sheet.
///
/// 하루 한 번 등록하면 충분하도록 단순화:
///  - 큰 숫자(현재 값) · -/+ 버튼으로 0.1kg 단위 조정
///  - 숫자 탭하면 키패드로 직접 입력
///  - 날짜는 기본 "오늘", 필요 시 토글로 어제 선택
///  - 저장 → weight_provider.logWeight
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/profile_provider.dart';
import '../../providers/weight_provider.dart';
import '../../theme/foodiet_tokens.dart';

class WeightLogSheet extends ConsumerStatefulWidget {
  const WeightLogSheet({super.key, this.initialKg});
  final double? initialKg;

  static Future<bool?> show(BuildContext context, {double? initialKg}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WeightLogSheet(initialKg: initialKg),
    );
  }

  @override
  ConsumerState<WeightLogSheet> createState() => _WeightLogSheetState();
}

class _WeightLogSheetState extends ConsumerState<WeightLogSheet> {
  late double _weight;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).valueOrNull;
    _weight = widget.initialKg ?? profile?.weightKg ?? 70.0;
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  void _adjust(double delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _weight = (_weight + delta).clamp(20, 300);
      // 0.1 단위 반올림.
      _weight = (_weight * 10).round() / 10;
    });
  }

  Future<void> _editDirect() async {
    final controller = TextEditingController(
      text: _weight.toStringAsFixed(1),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('체중 입력',
            style: FoodietText.title.copyWith(color: FoodietColors.warm900)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          textAlign: TextAlign.center,
          style: FoodietText.numberLarge.copyWith(
              color: FoodietColors.warm900, fontSize: 36),
          decoration: const InputDecoration(suffixText: 'kg'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: FoodietColors.coral500),
            onPressed: () {
              final v = double.tryParse(controller.text);
              if (v == null || v < 20 || v > 300) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop((v * 10).round() / 10);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _weight = result);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await logWeight(
        ref: ref,
        weightKg: _weight,
        loggedAt: _date,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '저장 실패: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final isToday = _sameDay(_date, today);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: FoodietColors.cream00,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusXl)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FoodietShape.sp24,
                FoodietShape.sp12, FoodietShape.sp24, FoodietShape.sp20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle.
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: FoodietShape.sp16),
                    decoration: BoxDecoration(
                      color: FoodietColors.cream100,
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusXs),
                    ),
                  ),
                ),
                Text('오늘 체중 기록',
                    textAlign: TextAlign.center,
                    style: FoodietText.title
                        .copyWith(color: FoodietColors.warm900)),
                const SizedBox(height: 4),
                Text('매일 같은 시간, 같은 조건으로 재는 게 가장 정확해',
                    textAlign: TextAlign.center,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),

                const SizedBox(height: FoodietShape.sp24),

                // 스테퍼.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _StepButton(
                      icon: Icons.remove,
                      onTap: () => _adjust(-0.1),
                      onLongPress: () => _adjust(-1.0),
                    ),
                    const SizedBox(width: FoodietShape.sp12),
                    GestureDetector(
                      onTap: _editDirect,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: FoodietShape.sp16,
                            vertical: FoodietShape.sp12),
                        decoration: BoxDecoration(
                          color: FoodietColors.coral50,
                          borderRadius: BorderRadius.circular(
                              FoodietShape.radiusLg),
                          border:
                              Border.all(color: FoodietColors.coral100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _weight.toStringAsFixed(1),
                              style: FoodietText.numberLarge.copyWith(
                                  color: FoodietColors.coral500,
                                  fontSize: 52),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text('kg',
                                  style: FoodietText.title.copyWith(
                                      color: FoodietColors.coral500)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: FoodietShape.sp12),
                    _StepButton(
                      icon: Icons.add,
                      onTap: () => _adjust(0.1),
                      onLongPress: () => _adjust(1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text('탭해서 직접 입력 · 길게 누르면 1kg 씩',
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                ),

                const SizedBox(height: FoodietShape.sp24),

                // 날짜 토글.
                Row(
                  children: [
                    Expanded(
                      child: _DateChip(
                        label: '오늘 (${today.month}/${today.day})',
                        selected: isToday,
                        onTap: () => setState(() => _date = DateTime(
                            today.year, today.month, today.day)),
                      ),
                    ),
                    const SizedBox(width: FoodietShape.sp8),
                    Expanded(
                      child: _DateChip(
                        label:
                            '어제 (${yesterday.month}/${yesterday.day})',
                        selected: !isToday,
                        onTap: () => setState(() => _date = DateTime(
                            yesterday.year,
                            yesterday.month,
                            yesterday.day)),
                      ),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: FoodietShape.sp12),
                  Text(_error!,
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.danger)),
                ],

                const SizedBox(height: FoodietShape.sp20),

                // 저장.
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: FoodietColors.coral500,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(FoodietShape.radiusMd),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text('저장',
                            style: FoodietText.title
                                .copyWith(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: FoodietColors.cream100),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: FoodietColors.warm700, size: 24),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FoodietColors.coral500 : FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(
              color: selected
                  ? FoodietColors.coral500
                  : FoodietColors.cream100,
            ),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: FoodietText.bodySm.copyWith(
                color: selected ? Colors.white : FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
        ),
      ),
    );
  }
}
