/// 그룹 설정 — 공통(공유 범위, 자동 공유 시각, 나가기) + 그룹장 전용(이름/이모지/소개글
/// /공개·비공개/비밀번호/그룹 삭제).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class CommunityGroupSettingsPage extends ConsumerWidget {
  const CommunityGroupSettingsPage({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final myUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('그룹 설정',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: groupAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: FoodietColors.coral500)),
          error: (_, __) =>
              const Center(child: Text('그룹을 찾을 수 없어요.')),
          data: (g) {
            if (g == null) return const Center(child: Text('그룹을 찾을 수 없어요.'));
            final isOwner = g.createdBy == myUserId;
            final myMember = (membersAsync.valueOrNull ?? const [])
                .where((m) => m.userId == myUserId)
                .firstOrNull;
            return _Body(group: g, isOwner: isOwner, myMember: myMember);
          },
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _Body extends ConsumerStatefulWidget {
  const _Body({
    required this.group,
    required this.isOwner,
    required this.myMember,
  });
  final CommunityGroup group;
  final bool isOwner;
  final GroupMember? myMember;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late GroupVisibility _visibility;
  String _emoji = '🥗';

  late bool _showPhotos;
  late bool _showKcal;
  late bool _showMacros;
  late bool _autoShare;
  late TimeOfDay _shareTime;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group.name);
    _desc = TextEditingController(text: widget.group.description ?? '');
    _visibility = widget.group.visibility;
    _emoji = widget.group.emoji;
    final m = widget.myMember;
    _showPhotos = m?.showPhotos ?? true;
    _showKcal = m?.showKcal ?? true;
    _showMacros = m?.showMacros ?? true;
    _autoShare = m?.autoShare ?? false;
    _shareTime = m?.shareTime ?? const TimeOfDay(hour: 21, minute: 0);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _saveOwnerMeta() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(communityServiceProvider);
      await svc.updateGroupMeta(
        groupId: widget.group.id,
        name: _name.text.trim(),
        emoji: _emoji,
        description: _desc.text.trim(),
        visibility: _visibility,
      );
      ref.invalidate(groupDetailProvider(widget.group.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('변경사항을 저장했어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMyMembership() async {
    final m = widget.myMember;
    if (m == null) return;
    final svc = ref.read(communityServiceProvider);
    final hh = _shareTime.hour.toString().padLeft(2, '0');
    final mm = _shareTime.minute.toString().padLeft(2, '0');
    await svc.updateMyMembership(
      groupId: widget.group.id,
      userId: m.userId,
      showPhotos: _showPhotos,
      showKcal: _showKcal,
      showMacros: _showMacros,
      autoShare: _autoShare,
      shareTimeHHmm: '$hh:$mm',
    );
    ref.invalidate(groupMembersProvider(widget.group.id));
  }

  Future<void> _changePassword() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('비밀번호 변경'),
        content: TextField(
          controller: ctrl,
          maxLength: 8,
          obscureText: true,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s'))
          ],
          decoration: const InputDecoration(hintText: '4~8자'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('변경')),
        ],
      ),
    );
    if (ok != true) return;
    final p = ctrl.text;
    if (p.length < 4 || p.length > 8) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('비밀번호는 4~8자여야 해요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
      return;
    }
    try {
      await ref.read(communityServiceProvider).changeGroupPassword(
            groupId: widget.group.id,
            newPassword: p,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('비밀번호를 변경했어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('변경 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  Future<void> _leave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('그룹에서 나갈까?'),
        content: const Text('내가 올린 카드는 그대로 남고, 새로 글을 쓰거나 응원할 수는 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('나가기')),
        ],
      ),
    );
    if (confirm != true) return;
    final me = widget.myMember;
    if (me == null) return;
    await ref.read(communityServiceProvider).leaveGroup(
          groupId: widget.group.id,
          userId: me.userId,
        );
    ref.invalidate(myGroupsProvider);
    if (!mounted) return;
    context.go('/community');
  }

  Future<void> _archive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('그룹을 삭제할까?'),
        content: const Text('모든 구성원이 더 이상 글을 쓰거나 응원할 수 없어요. 이 작업은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소')),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: FoodietColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(communityServiceProvider).archiveGroup(widget.group.id);
    ref.invalidate(myGroupsProvider);
    if (!mounted) return;
    context.go('/community');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        if (widget.isOwner) ...[
          _Section('그룹 정보 (그룹장만 변경 가능)'),
          _OwnerEdit(
            name: _name,
            desc: _desc,
            emoji: _emoji,
            onEmoji: (e) => setState(() => _emoji = e),
            visibility: _visibility,
            onVisibility: (v) => setState(() => _visibility = v),
          ),
          const SizedBox(height: FoodietShape.sp12),
          PrimaryButton(
            label: _saving ? '저장 중…' : '변경사항 저장',
            onPressed: _saving ? null : _saveOwnerMeta,
          ),
          if (_visibility == GroupVisibility.private) ...[
            const SizedBox(height: FoodietShape.sp8),
            OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.lock_outline),
              label: const Text('비밀번호 변경'),
            ),
          ],
          const SizedBox(height: FoodietShape.sp24),
        ],
        _Section('내 공유 설정 (이 그룹에서만 적용)'),
        _Toggle(
          label: '음식 사진 공유',
          value: _showPhotos,
          onChanged: (v) {
            setState(() => _showPhotos = v);
            _saveMyMembership();
          },
        ),
        _Toggle(
          label: '칼로리 공유',
          value: _showKcal,
          onChanged: (v) {
            setState(() => _showKcal = v);
            _saveMyMembership();
          },
        ),
        _Toggle(
          label: '영양소(탄단지) 공유',
          value: _showMacros,
          onChanged: (v) {
            setState(() => _showMacros = v);
            _saveMyMembership();
          },
        ),
        const SizedBox(height: FoodietShape.sp16),
        _Section('자동 공유'),
        _Toggle(
          label: '매일 정해진 시각에 자동 공유',
          value: _autoShare,
          onChanged: (v) {
            setState(() => _autoShare = v);
            _saveMyMembership();
          },
        ),
        if (_autoShare)
          ListTile(
            title: const Text('공유 시각'),
            trailing: Text(
                '${_shareTime.hour.toString().padLeft(2, '0')}:${_shareTime.minute.toString().padLeft(2, '0')}',
                style:
                    FoodietText.body.copyWith(fontWeight: FontWeight.w700)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _shareTime,
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx)
                      .copyWith(alwaysUse24HourFormat: true),
                  child: child ?? const SizedBox(),
                ),
              );
              if (picked != null) {
                setState(() => _shareTime = picked);
                await _saveMyMembership();
              }
            },
          ),
        const Divider(height: 40, color: FoodietColors.cream100),
        OutlinedButton.icon(
          icon: const Icon(Icons.exit_to_app, color: FoodietColors.warm700),
          label: const Text('그룹에서 나가기'),
          style: OutlinedButton.styleFrom(
            foregroundColor: FoodietColors.warm700,
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: _leave,
        ),
        if (widget.isOwner) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline,
                color: FoodietColors.danger),
            label: const Text('그룹 삭제'),
            style: OutlinedButton.styleFrom(
              foregroundColor: FoodietColors.danger,
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: _archive,
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(label,
          style: FoodietText.bodySm.copyWith(
              color: FoodietColors.warm700, fontWeight: FontWeight.w700)),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(label,
          style: FoodietText.body.copyWith(color: FoodietColors.warm900)),
      value: value,
      activeThumbColor: FoodietColors.coral500,
      onChanged: onChanged,
    );
  }
}

class _OwnerEdit extends StatelessWidget {
  const _OwnerEdit({
    required this.name,
    required this.desc,
    required this.emoji,
    required this.onEmoji,
    required this.visibility,
    required this.onVisibility,
  });
  final TextEditingController name;
  final TextEditingController desc;
  final String emoji;
  final ValueChanged<String> onEmoji;
  final GroupVisibility visibility;
  final ValueChanged<GroupVisibility> onVisibility;

  static const _picks = ['🥗', '🍳', '🍱', '🥑', '🍓', '🥦', '🍵', '🏋️', '🔥', '✨'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final e in _picks)
              GestureDetector(
                onTap: () => onEmoji(e),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: emoji == e
                        ? FoodietColors.coral100
                        : FoodietColors.cream50,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '그룹 이름'),
        ),
        TextField(
          controller: desc,
          maxLength: 200,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '소개글 (선택)'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<GroupVisibility>(
                contentPadding: EdgeInsets.zero,
                title: const Text('공개'),
                value: GroupVisibility.public,
                groupValue: visibility,
                activeColor: FoodietColors.coral500,
                onChanged: (v) => v == null ? null : onVisibility(v),
              ),
            ),
            Expanded(
              child: RadioListTile<GroupVisibility>(
                contentPadding: EdgeInsets.zero,
                title: const Text('비공개'),
                value: GroupVisibility.private,
                groupValue: visibility,
                activeColor: FoodietColors.coral500,
                onChanged: (v) => v == null ? null : onVisibility(v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
