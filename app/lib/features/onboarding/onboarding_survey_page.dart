/// Onboarding Survey — 3단계.
///
/// 기획안 §4.5 / §5.1.
/// 1/3 나 (닉네임만)
/// 2/3 현재 (키 cm, 체중 kg)
/// 3/3 목표 (목표 체중, 기한, 활동량)
///
/// 완료 시:
///   - Mifflin-St Jeor + 활동계수 + 감량 적자로 daily_kcal_target 계산.
///     · 성별·나이 미입력 — 중립 fallback (sex 평균 -78, age 30).
///   - profiles 테이블에 upsert (sex / birth_date 는 NULL 로).
///   - /home 으로 이동.
///
/// ⚠️ App Store guideline 5.1.1(v) — 성별·생년월일·식이제한 등 코어 기능에
///    필수가 아닌 개인정보는 온보딩에서 아예 묻지 않는다. 정확도를 더 원하는
///    사용자는 마이 → 프로필 편집 화면에서 선택적으로 입력 가능.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../config/env.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/supabase_provider.dart';
import '../../services/kcal_calc.dart';
import '../../services/nickname_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class OnboardingSurveyPage extends ConsumerStatefulWidget {
  const OnboardingSurveyPage({super.key});

  @override
  ConsumerState<OnboardingSurveyPage> createState() =>
      _OnboardingSurveyPageState();
}

class _OnboardingSurveyPageState
    extends ConsumerState<OnboardingSurveyPage> {
  final _pc = PageController();
  int _step = 0;
  bool _submitting = false;
  String? _error;

  // ── 입력 상태 ─────────────────────────────────────────────────────
  final _nick = TextEditingController();

  final _height = TextEditingController();
  final _weight = TextEditingController();

  final _goalWeight = TextEditingController();
  DateTime? _deadline;
  int? _activity; // 1~5

  @override
  void dispose() {
    _pc.dispose();
    _nick.dispose();
    _height.dispose();
    _weight.dispose();
    _goalWeight.dispose();
    super.dispose();
  }

  // 성별·생년월일은 선택 입력이라 닉네임만 있으면 step1 통과.
  bool get _step1Valid => _nick.text.trim().isNotEmpty;

  bool get _step2Valid {
    final h = double.tryParse(_height.text);
    final w = double.tryParse(_weight.text);
    return h != null && h > 50 && h < 250 && w != null && w > 20 && w < 300;
  }

  bool get _step3Valid {
    final g = double.tryParse(_goalWeight.text);
    return g != null && g > 20 && g < 300 && _activity != null;
  }

  bool get _canNext => switch (_step) {
        0 => _step1Valid,
        1 => _step2Valid,
        2 => _step3Valid,
        _ => false,
      };

  Future<void> _next() async {
    if (!_canNext) return;
    if (_step < 2) {
      setState(() => _step += 1);
      _pc.animateToPage(_step,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut);
    } else {
      await _submit();
    }
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() => _step -= 1);
    _pc.animateToPage(_step,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.add(const Duration(days: 14)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      initialDate: now.add(const Duration(days: 90)),
      helpText: '목표 기한',
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = ref.read(currentUserProvider);
    // dev bypass 일 때는 실제 upsert 불가 — 홈으로만 보낸다.
    if (user == null) {
      if (!mounted) return;
      context.go('/home');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final h = double.parse(_height.text);
    final w = double.parse(_weight.text);
    final goalW = double.parse(_goalWeight.text);

    // 성별·생년월일은 온보딩에서 묻지 않음 — 중립 fallback 으로 계산.
    // 사용자는 마이 → 프로필 편집에서 원하면 추가 입력 가능.
    final result = computeKcalTarget(KcalTargetInput(
      sex: null,
      ageYears: null,
      heightCm: h,
      weightKg: w,
      activityLevel: _activity!,
      goalWeightKg: goalW,
      goalDeadline: _deadline,
    ));

    try {
      final client = ref.read(supabaseClientProvider);
      final svc = ref.read(nicknameServiceProvider);
      final desiredNick = _nick.text.trim();

      // 닉네임은 전체 서비스 unique. 사용자가 입력한 닉네임을 형식·중복
      // 양쪽 다 검증해야 한다. 형식은 클라이언트에서 즉시 잡고 (서버 RPC
      // 호출 줄임), 중복은 RPC 한 번 + insert 의 unique 제약이 최종 가드.
      final fmt = svc.validateFormat(desiredNick);
      if (!fmt.isValid) {
        setState(() {
          _submitting = false;
          _error = fmt.message ?? '닉네임 형식이 올바르지 않아요.';
        });
        return;
      }
      // 빠른 사전 체크 — 다른 사용자가 같은 닉네임을 막 쓰는 시점이 있다면
      // upsert 가 unique 제약 위반(23505)을 던질 수 있으므로 그때도 잡는다.
      final available = await svc.isAvailable(desiredNick).timeout(
        const Duration(seconds: 8),
        onTimeout: () => true, // 네트워크 느리면 일단 시도. 서버가 막아주면 됨.
      );
      if (!available) {
        setState(() {
          _submitting = false;
          _error = '이미 사용 중인 닉네임이에요. 다른 걸로 시도해보자.';
        });
        return;
      }

      try {
        await client
            .from('profiles')
            .upsert({
              'user_id': user.id,
              'nickname': desiredNick,
              'locale': Env.defaultLocale,
              'unit_energy': Env.defaultEnergyUnit,
              'unit_mass': Env.defaultMassUnit,
              'height_cm': h,
              'weight_kg': w,
              'goal_weight_kg': goalW,
              'goal_deadline':
                  _deadline?.toIso8601String().substring(0, 10),
              'activity_level': _activity,
              'diet_restrictions': const <String>[],
              'daily_kcal_target': result.dailyKcalTarget,
              'birth_date': null,
              'sex': null,
            }, onConflict: 'user_id')
            .timeout(const Duration(seconds: 15));
      } on PostgrestException catch (e) {
        // 23505 = unique_violation. 누군가 동시에 같은 닉네임을 쓴 race condition.
        if (e.code == '23505' || e.message.contains('nickname')) {
          setState(() {
            _submitting = false;
            _error = '닉네임이 방금 사용됐어요. 다시 시도해주세요.';
          });
          return;
        }
        rethrow;
      }

      // profileProvider 재조회 — 라우터 가드가 재평가될 때
      // stale(null) 을 읽고 다시 /onboarding/survey 로 튕기는 걸 막기 위해
      // 여기서 새 값이 실제로 들어올 때까지 기다린다.
      ref.invalidate(profileProvider);
      await ref
          .read(profileProvider.future)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '저장 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: FoodietColors.warm900, size: 18),
          onPressed: _submitting ? null : _back,
        ),
        title: Text('${_step + 1}/3',
            style:
                FoodietText.title.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ProgressBar(step: _step, total: 3),
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step1Me(
                    nick: _nick,
                    onChanged: () => setState(() {}),
                  ),
                  _Step2Now(
                    height: _height,
                    weight: _weight,
                    onChanged: () => setState(() {}),
                  ),
                  _Step3Goal(
                    goalWeight: _goalWeight,
                    deadline: _deadline,
                    activity: _activity,
                    onDeadline: _pickDeadline,
                    onActivity: (a) => setState(() => _activity = a),
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FoodietShape.sp20,
                  vertical: FoodietShape.sp8,
                ),
                child: Text(_error!,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.danger)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  FoodietShape.sp20, FoodietShape.sp8,
                  FoodietShape.sp20, FoodietShape.sp24),
              child: PrimaryButton(
                label: _step == 2
                    ? (_submitting ? '저장 중…' : '완료')
                    : '다음',
                onPressed:
                    (!_canNext || _submitting) ? null : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / total;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: FoodietShape.sp20, vertical: FoodietShape.sp8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: FoodietColors.cream100,
          valueColor:
              const AlwaysStoppedAnimation<Color>(FoodietColors.coral500),
        ),
      ),
    );
  }
}

// ── Step 1 ─────────────────────────────────────────────────────────
class _Step1Me extends StatelessWidget {
  const _Step1Me({
    required this.nick,
    required this.onChanged,
  });

  final TextEditingController nick;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        Text('나에 대해서 🌸',
            style: FoodietText.h2.copyWith(color: FoodietColors.warm900)),
        const SizedBox(height: FoodietShape.sp4),
        Text('푸디가 부를 닉네임만 정해주면 돼.',
            style:
                FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: FoodietShape.sp24),
        const _Label('닉네임'),
        const SizedBox(height: 6),
        TextField(
          controller: nick,
          maxLength: 16,
          decoration: _inputDecoration('예: 후니'),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: FoodietShape.sp16),
        // 칼로리 계산을 더 정밀하게 하고 싶으면 마이 → 프로필 편집에서
        // 성별·생년월일을 선택적으로 추가할 수 있다는 친절 안내.
        Container(
          padding: const EdgeInsets.all(FoodietShape.sp12),
          decoration: BoxDecoration(
            color: FoodietColors.cream50,
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: FoodietColors.warm500, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '나중에 마이 > 프로필 편집에서 성별·생년월일을 추가하면 칼로리 계산이 더 정확해져 (선택).',
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 2 ─────────────────────────────────────────────────────────
class _Step2Now extends StatelessWidget {
  const _Step2Now({
    required this.height,
    required this.weight,
    required this.onChanged,
  });

  final TextEditingController height;
  final TextEditingController weight;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        Text('지금의 나 🍓',
            style: FoodietText.h2.copyWith(color: FoodietColors.warm900)),
        const SizedBox(height: FoodietShape.sp4),
        Text('키와 현재 체중을 알려줘.',
            style:
                FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: FoodietShape.sp24),
        const _Label('키 (cm)'),
        const SizedBox(height: 6),
        TextField(
          controller: height,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: _inputDecoration('예: 170'),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: FoodietShape.sp16),
        const _Label('현재 체중 (kg)'),
        const SizedBox(height: 6),
        TextField(
          controller: weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: _inputDecoration('예: 62.5'),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

// ── Step 3 ─────────────────────────────────────────────────────────
class _Step3Goal extends StatelessWidget {
  const _Step3Goal({
    required this.goalWeight,
    required this.deadline,
    required this.activity,
    required this.onDeadline,
    required this.onActivity,
    required this.onChanged,
  });

  final TextEditingController goalWeight;
  final DateTime? deadline;
  final int? activity;
  final VoidCallback onDeadline;
  final ValueChanged<int> onActivity;
  final VoidCallback onChanged;

  static const _activityLabels = <int, (String, String)>{
    1: ('거의 안 움직여', '사무직 · 재택, 운동 없음'),
    2: ('조금 움직여', '주 1~3회 가벼운 운동'),
    3: ('보통', '주 3~5회 중강도 운동'),
    4: ('많이 움직여', '주 6~7회 강한 운동'),
    5: ('매우 활동적', '육체직 · 선수 수준'),
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        Text('어디로 가볼까 🎯',
            style: FoodietText.h2.copyWith(color: FoodietColors.warm900)),
        const SizedBox(height: FoodietShape.sp4),
        Text('목표 체중 · 기한 · 활동량으로 일일 권장량을 계산해.',
            style:
                FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: FoodietShape.sp24),
        const _Label('목표 체중 (kg)'),
        const SizedBox(height: 6),
        TextField(
          controller: goalWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: _inputDecoration('예: 58.0'),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: FoodietShape.sp16),
        const _Label('목표 기한 (선택)'),
        const SizedBox(height: 6),
        InkWell(
          onTap: onDeadline,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: FoodietColors.cream50,
              borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Row(
              children: [
                const Icon(Icons.flag_outlined,
                    color: FoodietColors.warm500, size: 18),
                const SizedBox(width: 10),
                Text(
                  deadline == null
                      ? '언제까지 할래?'
                      : '${deadline!.year}.${deadline!.month.toString().padLeft(2, '0')}'
                          '.${deadline!.day.toString().padLeft(2, '0')}',
                  style: FoodietText.body.copyWith(
                    color: deadline == null
                        ? FoodietColors.warm500
                        : FoodietColors.warm900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FoodietShape.sp20),
        const _Label('활동량'),
        const SizedBox(height: 6),
        ..._activityLabels.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActivityTile(
                selected: activity == e.key,
                title: e.value.$1,
                subtitle: e.value.$2,
                onTap: () => onActivity(e.key),
              ),
            )),
      ],
    );
  }
}

// ── 공통 위젯 ─────────────────────────────────────────────────────
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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? FoodietColors.coral50
              : FoodietColors.cream50,
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
        borderSide:
            const BorderSide(color: FoodietColors.coral500, width: 1.5),
      ),
    );
