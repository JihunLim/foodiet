/// 닉네임 변경 화면.
///
/// 기획서 §2.4 — 사용자 입력 시 실시간 형식 검증 + 300ms debounce 후
/// 서버 중복 확인. 모두 통과해야 "저장" 활성화. 저장 시 서버 RPC 한 번 더
/// 검증 (race-safe).
///
/// 30일 1회 변경 제한: cooldown 안 끝났으면 입력 disabled + 안내 텍스트.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/profile_provider.dart';
import '../../services/nickname_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class NicknameEditPage extends ConsumerStatefulWidget {
  const NicknameEditPage({super.key});

  @override
  ConsumerState<NicknameEditPage> createState() => _NicknameEditPageState();
}

enum _CheckState { idle, checking, available, taken, invalidFormat, error }

class _NicknameEditPageState extends ConsumerState<NicknameEditPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  String _initial = '';
  _CheckState _check = _CheckState.idle;
  String? _hintMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).valueOrNull;
    final initial = profile?.nickname ?? '';
    _initial = initial;
    _ctrl.text = initial;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final trimmed = v.trim();
    _debounce?.cancel();

    // 변경 안 한 경우 — idle (현재 닉네임).
    if (trimmed == _initial) {
      setState(() {
        _check = _CheckState.idle;
        _hintMessage = null;
      });
      return;
    }

    final svc = ref.read(nicknameServiceProvider);
    final fmt = svc.validateFormat(trimmed);
    if (!fmt.isValid) {
      setState(() {
        _check = _CheckState.invalidFormat;
        _hintMessage = fmt.message;
      });
      return;
    }

    // 형식은 OK — 300ms debounce 후 서버 중복 확인.
    setState(() {
      _check = _CheckState.checking;
      _hintMessage = '확인 중…';
    });
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final available =
            await svc.isAvailable(trimmed).timeout(const Duration(seconds: 6));
        if (!mounted) return;
        // 입력값이 그새 바뀌었으면 결과 무시.
        if (_ctrl.text.trim() != trimmed) return;
        setState(() {
          _check = available ? _CheckState.available : _CheckState.taken;
          _hintMessage = available
              ? '사용 가능한 닉네임이에요!'
              : '이미 사용 중인 닉네임이에요.';
        });
      } catch (_) {
        if (!mounted) return;
        if (_ctrl.text.trim() != trimmed) return;
        setState(() {
          _check = _CheckState.error;
          _hintMessage = '네트워크 문제로 확인하지 못했어요. 잠시 후 다시 시도해주세요.';
        });
      }
    });
  }

  bool get _canSave =>
      _check == _CheckState.available && !_saving;

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);
    final svc = ref.read(nicknameServiceProvider);
    final result = await svc.updateNickname(_ctrl.text.trim());
    if (!mounted) return;

    if (result.ok) {
      ref.invalidate(profileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('닉네임을 바꿨어 ✨'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      // 페이지 뒤로 이동 — back stack 가드.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
      return;
    }

    setState(() => _saving = false);
    final msg = switch (result.error) {
      NicknameUpdateError.taken => '이미 사용 중인 닉네임이에요.',
      NicknameUpdateError.cooldown => '닉네임은 30일에 한 번만 바꿀 수 있어요.',
      NicknameUpdateError.invalidFormat => '닉네임 형식이 올바르지 않아요.',
      NicknameUpdateError.authRequired => '로그인이 필요해요.',
      NicknameUpdateError.network => '네트워크 문제로 변경하지 못했어요.',
      NicknameUpdateError.unknown => '변경에 실패했어요. 잠시 후 다시 시도해주세요.',
      null => '변경에 실패했어요.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FoodietColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final canChangeNow = profile?.canChangeNicknameNow ?? true;
    final availableAt = profile?.nicknameChangeAvailableAt;

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: FoodietColors.warm900, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text('닉네임 변경',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FoodietShape.sp20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('커뮤니티에서 사용할 이름이에요.',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
              const SizedBox(height: FoodietShape.sp16),
              if (!canChangeNow && availableAt != null) ...[
                Container(
                  padding: const EdgeInsets.all(FoodietShape.sp12),
                  decoration: BoxDecoration(
                    color: FoodietColors.cream50,
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    border: Border.all(color: FoodietColors.cream100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: FoodietColors.warm500, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${DateFormat('M월 d일').format(availableAt)} 이후에 다시 변경할 수 있어요.\n(닉네임은 30일에 한 번만 변경 가능)',
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.warm700, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FoodietShape.sp16),
              ],
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                enabled: canChangeNow && !_saving,
                maxLength: 12,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: InputDecoration(
                  hintText: '예: 활발한_딸기_042',
                  filled: true,
                  fillColor: FoodietColors.cream50,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    borderSide: const BorderSide(
                      color: FoodietColors.coral500,
                      width: 1.5,
                    ),
                  ),
                  suffixIcon: _StatusSuffix(state: _check),
                ),
                onChanged: _onChanged,
              ),
              if (_hintMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _hintMessage!,
                  style: FoodietText.caption.copyWith(
                    color: switch (_check) {
                      _CheckState.available => FoodietColors.leaf700,
                      _CheckState.taken => FoodietColors.danger,
                      _CheckState.invalidFormat => FoodietColors.danger,
                      _CheckState.error => FoodietColors.warning,
                      _ => FoodietColors.warm500,
                    },
                  ),
                ),
              ],
              const SizedBox(height: FoodietShape.sp16),
              _Rules(),
              const Spacer(),
              PrimaryButton(
                label: _saving ? '저장 중…' : '저장',
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSuffix extends StatelessWidget {
  const _StatusSuffix({required this.state});
  final _CheckState state;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: switch (state) {
        _CheckState.checking => const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: FoodietColors.coral500,
              ),
            ),
          ),
        _CheckState.available => const Icon(
            Icons.check_circle,
            color: FoodietColors.leaf500,
            size: 20,
          ),
        _CheckState.taken => const Icon(
            Icons.cancel,
            color: FoodietColors.danger,
            size: 20,
          ),
        _CheckState.invalidFormat => const Icon(
            Icons.error_outline,
            color: FoodietColors.danger,
            size: 20,
          ),
        _CheckState.error => const Icon(
            Icons.warning_amber_rounded,
            color: FoodietColors.warning,
            size: 20,
          ),
        _CheckState.idle => const SizedBox.shrink(),
      },
    );
  }
}

class _Rules extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('닉네임 규칙',
              style: FoodietText.bodySm.copyWith(
                  color: FoodietColors.warm700,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ..._items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('· $t',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500, height: 1.4)),
              )),
        ],
      ),
    );
  }

  static const _items = <String>[
    '2~12자',
    '한글, 영문, 숫자, 언더스코어(_)',
    '띄어쓰기·이모지·특수문자 불가',
    '다른 사용자와 같은 닉네임은 사용할 수 없어요',
    '한번 변경하면 30일 동안 다시 못 바꿔요',
  ];
}
