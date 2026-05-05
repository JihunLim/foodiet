/// 프로필 편집.
///
/// 기획안 §4.5/§6 — 닉네임/키/체중/목표/기한/활동량/일일 권장 kcal 그리고
/// 선택 입력으로 성별/생년월일을 조정할 수 있는 화면.
///
/// Phase F (MVP 완성도 개선):
///   - 마이 탭 "프로필·목표·기한" 에서 진입.
///   - 저장 시 profiles 테이블 update + profileProvider invalidate.
///   - 일일 권장 kcal 옆 "자동 계산" 버튼:
///       Mifflin-St Jeor + 활동계수 + (기한 있으면 기한 기반 적자, 없으면 ±500)
///       주 1kg 초과 속도, 하한(여 1200 / 남 1500) 캡 경고.
///
/// 식이제한(가리는 음식)은 App Store guideline 5.1.1(v) 대응으로 더 이상
/// 수집하지 않음 — 기존 데이터는 유지하되 UI 에서 노출 안 함.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/supabase_provider.dart';
import '../../services/kcal_calc.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  late final TextEditingController _nick;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _goalWeight;
  late final TextEditingController _kcal;

  DateTime? _birth;
  Sex? _sex;
  DateTime? _goalDeadline;
  int? _activity; // 1~5

  bool _initialized = false;
  bool _saving = false;
  String? _error;

  /// 마지막 자동 계산 결과. null 이면 미적용/미노출.
  KcalTargetResult? _lastAutoCalc;

  static const _activityLabels = <int, (String, String)>{
    1: ('거의 안 움직여', '사무직 · 재택, 운동 없음'),
    2: ('조금 움직여', '주 1~3회 가벼운 운동'),
    3: ('보통', '주 3~5회 중강도 운동'),
    4: ('많이 움직여', '주 6~7회 강한 운동'),
    5: ('매우 활동적', '육체직 · 선수 수준'),
  };

  @override
  void initState() {
    super.initState();
    _nick = TextEditingController();
    _height = TextEditingController();
    _weight = TextEditingController();
    _goalWeight = TextEditingController();
    _kcal = TextEditingController();
  }

  void _hydrate(AppProfile p) {
    if (_initialized) return;
    _nick.text = p.nickname;
    _height.text = p.heightCm == null ? '' : _fmt(p.heightCm!);
    _weight.text = p.weightKg == null ? '' : _fmt(p.weightKg!);
    _goalWeight.text = p.goalWeightKg == null ? '' : _fmt(p.goalWeightKg!);
    _kcal.text = p.dailyKcalTarget?.toString() ?? '';
    _birth = p.birthDate;
    _sex = p.sex;
    _goalDeadline = p.goalDeadline;
    _activity = p.activityLevel;
    _initialized = true;
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _nick.dispose();
    _height.dispose();
    _weight.dispose();
    _goalWeight.dispose();
    _kcal.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_saving) return false;
    if (_nick.text.trim().isEmpty) return false;
    final h = double.tryParse(_height.text);
    final w = double.tryParse(_weight.text);
    final g = double.tryParse(_goalWeight.text);
    if (h == null || h <= 50 || h >= 250) return false;
    if (w == null || w <= 20 || w >= 300) return false;
    if (g == null || g <= 20 || g >= 300) return false;
    if (_activity == null) return false;
    final k = int.tryParse(_kcal.text);
    if (k == null || k < 800 || k > 6000) return false;
    return true;
  }

  bool get _canAutoCalc {
    // sex / birth 는 선택 입력 — 없어도 중립값으로 자동 계산 가능.
    if (_activity == null) return false;
    final h = double.tryParse(_height.text);
    final w = double.tryParse(_weight.text);
    final g = double.tryParse(_goalWeight.text);
    if (h == null || h <= 50 || h >= 250) return false;
    if (w == null || w <= 20 || w >= 300) return false;
    if (g == null || g <= 20 || g >= 300) return false;
    return true;
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 10),
      initialDate: _birth ?? DateTime(now.year - 25, now.month, now.day),
      helpText: '생년월일',
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      initialDate: _goalDeadline ?? now.add(const Duration(days: 90)),
      helpText: '목표 기한',
    );
    if (picked != null) setState(() => _goalDeadline = picked);
  }

  void _clearDeadline() {
    setState(() => _goalDeadline = null);
  }

  void _autoCalcKcal() {
    if (!_canAutoCalc) return;
    final now = DateTime.now();
    final age = _birth == null ? null : _calcAge(_birth!, now);
    final r = computeKcalTarget(KcalTargetInput(
      sex: _sex,
      ageYears: age,
      heightCm: double.parse(_height.text),
      weightKg: double.parse(_weight.text),
      activityLevel: _activity!,
      goalWeightKg: double.parse(_goalWeight.text),
      goalDeadline: _goalDeadline,
      now: now,
    ));
    setState(() {
      _kcal.text = r.dailyKcalTarget.toString();
      _lastAutoCalc = r;
    });
  }

  int _calcAge(DateTime birth, DateTime now) {
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age -= 1;
    }
    return age;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      await client
          .from('profiles')
          .update({
            'nickname': _nick.text.trim(),
            'height_cm': double.parse(_height.text),
            'weight_kg': double.parse(_weight.text),
            'goal_weight_kg': double.parse(_goalWeight.text),
            'goal_deadline':
                _goalDeadline?.toIso8601String().substring(0, 10),
            'activity_level': _activity,
            // diet_restrictions 는 더 이상 UI 에서 수집하지 않음. 기존 값은
            // 보존하기 위해 update 에서 제외 (필드 자체 미포함).
            'daily_kcal_target': int.parse(_kcal.text),
            'birth_date':
                _birth?.toIso8601String().substring(0, 10),
            'sex': _sex == null
                ? null
                : (_sex == Sex.male ? 'male' : 'female'),
          })
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 15));

      ref.invalidate(profileProvider);
      await ref
          .read(profileProvider.future)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장했어 ✨'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '저장 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: FoodietColors.warm900, size: 18),
          onPressed: _saving ? null : () => context.pop(),
        ),
        title: Text('프로필 · 목표',
            style:
                FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: FoodietColors.coral500),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(FoodietShape.sp20),
              child: Text('프로필을 불러오지 못했어: $e',
                  textAlign: TextAlign.center,
                  style: FoodietText.body
                      .copyWith(color: FoodietColors.warm700)),
            ),
          ),
          data: (p) {
            if (p == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.go('/onboarding/survey');
              });
              return const SizedBox.shrink();
            }
            _hydrate(p);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(FoodietShape.sp20,
                        FoodietShape.sp8, FoodietShape.sp20, FoodietShape.sp24),
                    children: [
                      const _SectionHeader('기본 정보'),
                      const SizedBox(height: FoodietShape.sp8),
                      const _Label('닉네임'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nick,
                        maxLength: 16,
                        decoration: _inputDecoration('예: 후니'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: FoodietShape.sp16),
                      const _Label('생년월일 (선택 / Optional)'),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickBirth,
                        borderRadius:
                            BorderRadius.circular(FoodietShape.radiusMd),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: FoodietColors.cream50,
                            borderRadius: BorderRadius.circular(
                                FoodietShape.radiusMd),
                            border:
                                Border.all(color: FoodietColors.cream100),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded,
                                  color: FoodietColors.warm500, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                _birth == null
                                    ? '날짜 선택'
                                    : '${_birth!.year}.'
                                        '${_birth!.month.toString().padLeft(2, '0')}.'
                                        '${_birth!.day.toString().padLeft(2, '0')}',
                                style: FoodietText.body.copyWith(
                                  color: _birth == null
                                      ? FoodietColors.warm500
                                      : FoodietColors.warm900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: FoodietShape.sp16),
                      const _Label('성별 (선택 / Optional)'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _SelectTile(
                              selected: _sex == Sex.female,
                              label: '여성',
                              onTap: () => setState(() => _sex = Sex.female),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SelectTile(
                              selected: _sex == Sex.male,
                              label: '남성',
                              onTap: () => setState(() => _sex = Sex.male),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FoodietShape.sp16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _Label('키 (cm)'),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _height,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.]')),
                                  ],
                                  decoration: _inputDecoration('170'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: FoodietShape.sp12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _Label('현재 체중 (kg)'),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _weight,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.]')),
                                  ],
                                  decoration: _inputDecoration('62.5'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FoodietShape.sp24),

                      const _SectionHeader('목표'),
                      const SizedBox(height: FoodietShape.sp8),
                      const _Label('목표 체중 (kg)'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _goalWeight,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]')),
                        ],
                        decoration: _inputDecoration('예: 58.0'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: FoodietShape.sp16),
                      const _Label('목표 기한'),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickDeadline,
                        borderRadius:
                            BorderRadius.circular(FoodietShape.radiusMd),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: FoodietColors.cream50,
                            borderRadius: BorderRadius.circular(
                                FoodietShape.radiusMd),
                            border:
                                Border.all(color: FoodietColors.cream100),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.flag_outlined,
                                  color: FoodietColors.warm500, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _goalDeadline == null
                                      ? '기한을 정해볼까?'
                                      : '${_goalDeadline!.year}.'
                                          '${_goalDeadline!.month.toString().padLeft(2, '0')}.'
                                          '${_goalDeadline!.day.toString().padLeft(2, '0')}',
                                  style: FoodietText.body.copyWith(
                                    color: _goalDeadline == null
                                        ? FoodietColors.warm500
                                        : FoodietColors.warm900,
                                  ),
                                ),
                              ),
                              if (_goalDeadline != null)
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 18,
                                      color: FoodietColors.warm500),
                                  onPressed: _clearDeadline,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: FoodietShape.sp16),
                      const _Label('활동량'),
                      const SizedBox(height: 6),
                      ..._activityLabels.entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ActivityTile(
                              selected: _activity == e.key,
                              title: e.value.$1,
                              subtitle: e.value.$2,
                              onTap: () =>
                                  setState(() => _activity = e.key),
                            ),
                          )),
                      const SizedBox(height: FoodietShape.sp24),

                      const _SectionHeader('일일 권장 칼로리'),
                      const SizedBox(height: FoodietShape.sp8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _kcal,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _inputDecoration('1800'),
                              onChanged: (_) => setState(() {
                                // 수동 편집 시 자동 계산 결과 숨김.
                                _lastAutoCalc = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _AutoCalcButton(
                            enabled: _canAutoCalc,
                            onPressed: _autoCalcKcal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _KcalHelperText(result: _lastAutoCalc),

                      if (_error != null) ...[
                        const SizedBox(height: FoodietShape.sp16),
                        Text(_error!,
                            style: FoodietText.bodySm
                                .copyWith(color: FoodietColors.danger)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      FoodietShape.sp20,
                      FoodietShape.sp8,
                      FoodietShape.sp20,
                      FoodietShape.sp24),
                  child: PrimaryButton(
                    label: _saving ? '저장 중…' : '저장',
                    onPressed: _canSave ? _save : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AutoCalcButton extends StatelessWidget {
  const _AutoCalcButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.auto_awesome, size: 16),
        label: const Text('자동 계산'),
        style: FilledButton.styleFrom(
          backgroundColor: FoodietColors.coral500,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              FoodietColors.coral500.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          ),
          textStyle: FoodietText.bodySm.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _KcalHelperText extends StatelessWidget {
  const _KcalHelperText({required this.result});
  final KcalTargetResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return Text(
        '나이·성별·키·체중·목표 입력 후 "자동 계산" 을 누르면 BMR + '
        '활동량 + 기한 기반 적자로 추천 칼로리가 채워져. 직접 수정해도 돼.',
        style: FoodietText.caption.copyWith(color: FoodietColors.warm500),
      );
    }

    final mode = switch (r.mode) {
      KcalMode.cut => '감량',
      KcalMode.bulk => '증량',
      KcalMode.maintain => '유지',
    };
    final weekly = r.weeklyChangeKg.abs();
    final direction = r.weeklyChangeKg < 0
        ? '감소'
        : r.weeklyChangeKg > 0
            ? '증가'
            : '유지';

    final line1 = '유지(TDEE) ${r.tdee} kcal · $mode 추천 ${r.dailyKcalTarget} kcal';
    final line2 = r.mode == KcalMode.maintain
        ? '목표와 현재 체중이 거의 같아서 유지 권장.'
        : r.usedDeadline
            ? '기한 기반 적자 — 예상 속도 주 ${weekly.toStringAsFixed(2)} kg $direction'
            : '기한 없음 → 주 0.5kg ${r.mode == KcalMode.cut ? '감량' : '증량'} 가정';

    final warn = r.clampedBySafety
        ? '기한이 짧거나 하한(여 1200 / 남 1500)에 걸려서 안전 속도로 조정됐어. '
            '목표 도달이 설정한 기한보다 늦어질 수 있어.'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line1,
            style: FoodietText.caption
                .copyWith(color: FoodietColors.warm700)),
        const SizedBox(height: 2),
        Text(line2,
            style: FoodietText.caption
                .copyWith(color: FoodietColors.warm500)),
        if (warn != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: FoodietColors.danger.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(FoodietShape.radiusSm),
              border: Border.all(
                color: FoodietColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: FoodietColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(warn,
                      style: FoodietText.caption.copyWith(
                        color: FoodietColors.danger,
                      )),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: FoodietText.title.copyWith(color: FoodietColors.warm900));
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: FoodietText.caption.copyWith(
          color: FoodietColors.warm700,
          fontWeight: FontWeight.w700,
        ));
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? FoodietColors.coral500 : FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(
            color: selected
                ? FoodietColors.coral500
                : FoodietColors.cream100,
          ),
        ),
        child: Text(label,
            style: FoodietText.body.copyWith(
              color: selected ? Colors.white : FoodietColors.warm900,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? FoodietColors.coral50 : FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(
            color: selected
                ? FoodietColors.coral500
                : FoodietColors.cream100,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? FoodietColors.coral500
                  : FoodietColors.warm500,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: FoodietText.body.copyWith(color: FoodietColors.warm500),
      filled: true,
      fillColor: FoodietColors.cream50,
      counterText: '',
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        borderSide: const BorderSide(color: FoodietColors.cream100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        borderSide: const BorderSide(color: FoodietColors.cream100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        borderSide: const BorderSide(color: FoodietColors.coral500, width: 1.5),
      ),
    );
