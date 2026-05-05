/// 새 그룹 만들기 — 공개/비공개 + 비밀번호.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class CommunityGroupCreatePage extends ConsumerStatefulWidget {
  const CommunityGroupCreatePage({super.key});

  @override
  ConsumerState<CommunityGroupCreatePage> createState() =>
      _CommunityGroupCreatePageState();
}

class _CommunityGroupCreatePageState
    extends ConsumerState<CommunityGroupCreatePage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _password = TextEditingController();
  String _emoji = '🥗';
  GroupVisibility _visibility = GroupVisibility.public;
  bool _saving = false;
  String? _error;

  static const _emojiPicks = ['🥗', '🍳', '🍱', '🥑', '🍓', '🥦', '🍵', '🏋️', '🔥', '✨'];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_name.text.trim().isEmpty) return false;
    if (_visibility == GroupVisibility.private) {
      final p = _password.text;
      if (p.length < 4 || p.length > 8) return false;
    }
    return !_saving;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ref.read(communityServiceProvider);
      final id = await svc.createGroup(
        name: _name.text.trim(),
        emoji: _emoji,
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        visibility: _visibility,
        password: _visibility == GroupVisibility.private
            ? _password.text
            : null,
      );
      ref.invalidate(myGroupsProvider);
      if (!mounted) return;
      // 만든 그룹 상세로 이동.
      context.go('/community/group/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '그룹 생성에 실패했어요: ${_short(e.toString())}';
      });
    }
  }

  String _short(String s) => s.length > 100 ? '${s.substring(0, 100)}…' : s;

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
          onPressed: () => context.pop(),
        ),
        title: Text('새 그룹 만들기',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FoodietShape.sp20),
          child: ListView(
            children: [
              const _Label('이모지'),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _emojiPicks)
                    _EmojiPick(
                      emoji: e,
                      selected: _emoji == e,
                      onTap: () => setState(() => _emoji = e),
                    ),
                ],
              ),
              const SizedBox(height: FoodietShape.sp16),
              const _Label('그룹 이름'),
              TextField(
                controller: _name,
                maxLength: 40,
                decoration: const InputDecoration(
                  hintText: '예: 헬창 모임',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FoodietShape.sp16),
              const _Label('소개글 (선택)'),
              TextField(
                controller: _desc,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: '예: 평일 점심 인증하는 모임',
                ),
              ),
              const SizedBox(height: FoodietShape.sp20),
              const _Label('공개 범위'),
              _VisibilitySegmented(
                value: _visibility,
                onChanged: (v) => setState(() => _visibility = v),
              ),
              const SizedBox(height: FoodietShape.sp12),
              if (_visibility == GroupVisibility.private) ...[
                const _Label('비밀번호 (4~8자)'),
                TextField(
                  controller: _password,
                  maxLength: 8,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '카톡으로 공유하기 좋은 짧은 코드',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(FoodietShape.sp12),
                  decoration: BoxDecoration(
                    color: FoodietColors.cream50,
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                  ),
                  child: Text(
                    '공개 그룹은 누구나 검색해서 들어올 수 있어요.\n비공개 그룹은 비밀번호를 아는 사람만 가입돼요.',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500, height: 1.4),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: FoodietShape.sp16),
                Text(_error!,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.danger)),
              ],
              const SizedBox(height: FoodietShape.sp24),
              PrimaryButton(
                label: _saving ? '만드는 중…' : '그룹 만들기',
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: FoodietText.bodySm.copyWith(
              color: FoodietColors.warm700, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmojiPick extends StatelessWidget {
  const _EmojiPick({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FoodietColors.coral100 : FoodietColors.cream50,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
        ),
      ),
    );
  }
}

class _VisibilitySegmented extends StatelessWidget {
  const _VisibilitySegmented({
    required this.value,
    required this.onChanged,
  });
  final GroupVisibility value;
  final ValueChanged<GroupVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Row(
        children: [
          _Seg(
            label: '공개',
            selected: value == GroupVisibility.public,
            onTap: () => onChanged(GroupVisibility.public),
          ),
          _Seg(
            label: '비공개',
            selected: value == GroupVisibility.private,
            onTap: () => onChanged(GroupVisibility.private),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                label,
                style: FoodietText.bodySm.copyWith(
                  color: selected
                      ? FoodietColors.coral600
                      : FoodietColors.warm700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
