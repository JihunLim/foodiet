/// "오늘 맞았어" — 투약 기록 시트. 날짜·시각(변경 가능), 용량(기본 = 계획의 현재 용량),
/// 부위(복부/허벅지/팔, 선택), 메모.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/medication_provider.dart';
import '../../services/medication_schedule.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';
import 'medication_widgets.dart';

/// 기록했으면 true.
Future<bool> showMedicationLogSheet(
  BuildContext context, {
  required MedicationPlan plan,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: FoodietColors.cream00,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusLg)),
    ),
    builder: (_) => MedicationLogSheet(plan: plan),
  );
  return saved ?? false;
}

class MedicationLogSheet extends ConsumerStatefulWidget {
  const MedicationLogSheet({super.key, required this.plan});
  final MedicationPlan plan;

  @override
  ConsumerState<MedicationLogSheet> createState() =>
      _MedicationLogSheetState();
}

class _MedicationLogSheetState extends ConsumerState<MedicationLogSheet> {
  late DateTime _at;
  late final TextEditingController _dose;
  final TextEditingController _note = TextEditingController();
  String? _site;
  bool _saving = false;

  /// 안내/실패 문구 — 스낵바는 시트 뒤에 가려지므로 시트 안에 표시.
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _at = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _dose = TextEditingController(
        text: widget.plan.currentDoseMg > 0
            ? doseInputText(widget.plan.currentDoseMg)
            : '');
  }

  @override
  void dispose() {
    _dose.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: now,
      initialDate: _at.isAfter(now) ? now : _at,
      helpText: '투약한 날',
    );
    if (picked == null) return;
    setState(() => _at =
        DateTime(picked.year, picked.month, picked.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _at.hour, minute: _at.minute),
      helpText: '투약한 시각',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox(),
      ),
    );
    if (picked == null) return;
    setState(() => _at =
        DateTime(_at.year, _at.month, _at.day, picked.hour, picked.minute));
  }

  Future<void> _save() async {
    final dose = parseDose(_dose.text);
    if (_saving || dose == null) return;
    if (_at.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(() => _error = '아직 오지 않은 시각이야. 날짜·시각을 확인해줘.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(medicationRepoProvider).logDose(
            plan: widget.plan,
            doseMg: dose,
            takenAtLocal: _at,
            site: _site,
            note: _note.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '기록하지 못했어. 잠시 후 다시 해볼래?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final presets = dosePresets(widget.plan.drug);
    final dose = parseDose(_dose.text);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(FoodietShape.sp20,
                FoodietShape.sp8, FoodietShape.sp20, FoodietShape.sp24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MedSheetHandle(),
                Text('투약 기록',
                    style: FoodietText.h3
                        .copyWith(color: FoodietColors.warm900)),
                const SizedBox(height: 4),
                Text('${widget.plan.displayName} · 맞은 그대로 남겨두자.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: FoodietShape.sp20),

                const MedSectionLabel('언제'),
                MedValueRow(
                  icon: Icons.event_outlined,
                  label: '날짜',
                  value: medDateLabel(_at),
                  onTap: _pickDate,
                ),
                const SizedBox(height: FoodietShape.sp8),
                MedValueRow(
                  icon: Icons.schedule_rounded,
                  label: '시각',
                  value:
                      '${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}',
                  onTap: _pickTime,
                ),
                const SizedBox(height: FoodietShape.sp20),

                const MedSectionLabel('용량'),
                if (presets.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in presets)
                        MedPill(
                          label: formatDose(p),
                          selected: dose == p,
                          onTap: () => setState(
                              () => _dose.text = doseInputText(p)),
                        ),
                    ],
                  ),
                  const SizedBox(height: FoodietShape.sp8),
                ],
                TextField(
                  controller: _dose,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: medInputDecoration('용량 입력', suffix: 'mg'),
                ),
                const SizedBox(height: FoodietShape.sp20),

                const MedSectionLabel('부위 (선택)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in kInjectionSites.entries)
                      MedPill(
                        label: e.value,
                        selected: _site == e.key,
                        onTap: () => setState(
                            () => _site = _site == e.key ? null : e.key),
                      ),
                  ],
                ),
                const SizedBox(height: FoodietShape.sp20),

                const MedSectionLabel('메모 (선택)'),
                TextField(
                  controller: _note,
                  maxLength: 200,
                  maxLines: 2,
                  minLines: 1,
                  decoration: medInputDecoration('느낌이나 남기고 싶은 것'),
                ),
                const SizedBox(height: FoodietShape.sp8),
                if (_error != null) ...[
                  Text(_error!,
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.danger)),
                  const SizedBox(height: FoodietShape.sp8),
                ],
                PrimaryButton(
                  label: _saving ? '기록 중…' : '기록하기',
                  onPressed: dose != null && !_saving ? _save : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
