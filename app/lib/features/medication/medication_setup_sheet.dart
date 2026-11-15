/// GLP-1 투약 계획 설정 시트 — 약·현재 용량·간격·첫 투약일·알림 시각.
///
/// 용량은 사용자가 처방받은 값을 그대로 적는다. 앱은 용량을 추천하거나 바꾸라고
/// 하지 않는다(프리셋은 입력 편의용).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/medication_provider.dart';
import '../../services/medication_schedule.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';
import 'medication_widgets.dart';

/// 저장했으면 true.
Future<bool> showMedicationSetupSheet(
  BuildContext context, {
  MedicationPlan? initial,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: FoodietColors.cream00,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusLg)),
    ),
    builder: (_) => MedicationSetupSheet(initial: initial),
  );
  return saved ?? false;
}

class MedicationSetupSheet extends ConsumerStatefulWidget {
  const MedicationSetupSheet({super.key, this.initial});
  final MedicationPlan? initial;

  @override
  ConsumerState<MedicationSetupSheet> createState() =>
      _MedicationSetupSheetState();
}

class _MedicationSetupSheetState extends ConsumerState<MedicationSetupSheet> {
  late String _drug;
  late final TextEditingController _customName;
  late final TextEditingController _dose;
  late int _interval;
  late DateTime _start;
  late bool _reminder;
  late int _hour;
  late bool _coachContext;
  bool _saving = false;

  /// 저장 실패 안내 — 스낵바는 시트 뒤에 가려지므로 시트 안에 표시.
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final now = DateTime.now();
    _drug = p?.drug ?? 'wegovy';
    _customName = TextEditingController(text: p?.drugLabel ?? '');
    _dose = TextEditingController(
        text: p == null || p.currentDoseMg <= 0
            ? ''
            : doseInputText(p.currentDoseMg));
    _interval = p?.intervalDays ?? 7;
    // 꺼둔 계획을 다시 켤 때는 옛 시작일 대신 오늘을 기본값으로 — 그대로 저장해도
    // '지남'으로 남거나 알림이 안 걸리지 않게. (최근 기록이 더 뒤면 기록이 우선.)
    final today = DateTime(now.year, now.month, now.day);
    _start = (p == null || !p.active) ? today : (p.startDate ?? today);
    _reminder = p?.reminderEnabled ?? true;
    _hour = p?.reminderHour ?? 9;
    _coachContext = p?.coachContext ?? true;
  }

  @override
  void dispose() {
    _customName.dispose();
    _dose.dispose();
    super.dispose();
  }

  double? get _doseValue => parseDose(_dose.text);

  bool get _valid =>
      _doseValue != null &&
      (_drug != 'other' || _customName.text.trim().isNotEmpty);

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final yearAgo = DateTime(now.year - 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      // 1년 넘게 쓴 계획의 시작일도 initialDate 로 열 수 있게(피커 assert 방지).
      firstDate: _start.isBefore(yearAgo) ? _start : yearAgo,
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: _start,
      helpText: '첫 투약일',
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickHour() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: 0),
      helpText: '알림 시각 (시 단위)',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox(),
      ),
    );
    if (picked != null) setState(() => _hour = picked.hour);
  }

  Future<void> _save() async {
    final dose = _doseValue;
    if (_saving || dose == null || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(medicationRepoProvider).savePlan(MedicationPlan(
            drug: _drug,
            drugLabel: _drug == 'other' ? _customName.text.trim() : null,
            currentDoseMg: dose,
            intervalDays: _interval,
            startDate: _start,
            reminderEnabled: _reminder,
            reminderHour: _hour,
            active: true,
            coachContext: _coachContext,
          ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '저장하지 못했어. 잠시 후 다시 해볼래?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final presets = dosePresets(_drug);
    final dose = _doseValue;

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
                Text(widget.initial == null ? '투약 관리 시작하기' : '투약 계획',
                    style: FoodietText.h3
                        .copyWith(color: FoodietColors.warm900)),
                const SizedBox(height: 4),
                Text('처방받은 그대로 적어줘. 다음 투약일을 계산하고 알려줄게.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: FoodietShape.sp20),

                // 약
                const MedSectionLabel('약'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in kMedicationDrugs)
                      MedPill(
                        label: drugLabel(d),
                        selected: _drug == d,
                        onTap: () => setState(() {
                          if (_drug == d) return;
                          // 약을 바꾸면 이전 약의 프리셋 용량이 남지 않게 비운다.
                          final v = _doseValue;
                          if (v != null &&
                              dosePresets(_drug).contains(v) &&
                              !dosePresets(d).contains(v)) {
                            _dose.clear();
                          }
                          _drug = d;
                        }),
                      ),
                  ],
                ),
                if (_drug == 'other') ...[
                  const SizedBox(height: FoodietShape.sp8),
                  TextField(
                    controller: _customName,
                    maxLength: 30,
                    onChanged: (_) => setState(() {}),
                    decoration: medInputDecoration('약 이름'),
                  ),
                ],
                const SizedBox(height: FoodietShape.sp20),

                // 용량
                const MedSectionLabel('현재 용량'),
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
                  decoration: medInputDecoration(
                      presets.isEmpty ? '용량 입력' : '직접 입력',
                      suffix: 'mg'),
                ),
                const SizedBox(height: FoodietShape.sp20),

                // 간격
                const MedSectionLabel('투약 간격'),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FoodietColors.cream50,
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    border: Border.all(color: FoodietColors.cream100),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _interval > 1
                            ? () => setState(() => _interval--)
                            : null,
                        icon: const Icon(Icons.remove_rounded),
                        color: FoodietColors.warm700,
                      ),
                      Expanded(
                        child: Text(
                          _interval == 7 ? '7일 (매주)' : '$_interval일마다',
                          textAlign: TextAlign.center,
                          style: FoodietText.body.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _interval < 60
                            ? () => setState(() => _interval++)
                            : null,
                        icon: const Icon(Icons.add_rounded),
                        color: FoodietColors.warm700,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FoodietShape.sp20),

                // 첫 투약일
                const MedSectionLabel('첫 투약일'),
                MedValueRow(
                  icon: Icons.event_outlined,
                  label: '시작일',
                  value: medDateLabel(_start),
                  onTap: _pickStart,
                ),
                const SizedBox(height: 4),
                Text(
                    '기록이 쌓이면 마지막 투약일 기준으로 다음 날짜를 계산해. '
                    '쉬었다가 다시 시작하면 시작일을 새로 골라줘.',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: FoodietShape.sp20),

                // 알림
                const MedSectionLabel('알림'),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: FoodietColors.cream50,
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    border: Border.all(color: FoodietColors.cream100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('투약 예정일에 알려줘',
                            style: FoodietText.body
                                .copyWith(color: FoodietColors.warm900)),
                      ),
                      Switch(
                        value: _reminder,
                        onChanged: (v) => setState(() => _reminder = v),
                        activeThumbColor: FoodietColors.coral500,
                      ),
                    ],
                  ),
                ),
                if (_reminder) ...[
                  const SizedBox(height: FoodietShape.sp8),
                  MedValueRow(
                    icon: Icons.alarm_rounded,
                    label: '알림 시각',
                    value: medHourLabel(_hour),
                    onTap: _pickHour,
                  ),
                ],
                const SizedBox(height: FoodietShape.sp20),

                // 푸디 조언 반영
                InkWell(
                  onTap: () =>
                      setState(() => _coachContext = !_coachContext),
                  borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _coachContext,
                        onChanged: (v) =>
                            setState(() => _coachContext = v ?? false),
                        activeColor: FoodietColors.coral500,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('푸디 조언에 GLP-1 사용 여부만 반영',
                                  style: FoodietText.body.copyWith(
                                    color: FoodietColors.warm900,
                                    fontWeight: FontWeight.w700,
                                  )),
                              const SizedBox(height: 2),
                              Text(
                                '켜면 적게 먹는 날에도 단백질·수분을 먼저 챙기도록 '
                                '식사 조언에 반영해. 투약 기록·용량은 AI 에 보내지 않아.',
                                style: FoodietText.caption.copyWith(
                                    color: FoodietColors.warm500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FoodietShape.sp16),
                const MedDisclaimer(),
                const SizedBox(height: FoodietShape.sp16),
                if (_error != null) ...[
                  Text(_error!,
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.danger)),
                  const SizedBox(height: FoodietShape.sp8),
                ],
                PrimaryButton(
                  label: _saving ? '저장 중…' : '저장',
                  onPressed: _valid && !_saving ? _save : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
