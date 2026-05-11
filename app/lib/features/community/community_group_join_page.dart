/// 비공개 그룹 비밀번호 참여 페이지.
///
/// 그룹 ID + 비밀번호를 입력해 join_private_group RPC 호출.
/// 그룹 ID 는 보통 비공개 그룹 카드/상세에서 들어왔을 때 url 로 받지만,
/// 여기는 "공개 탐색에선 노출 안 됨" 이라는 정의에 충실하게,
/// 그룹 ID 도 사용자가 직접 입력하도록 한다 (카톡으로 함께 공유).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/community_provider.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class CommunityGroupJoinPage extends ConsumerStatefulWidget {
  const CommunityGroupJoinPage({super.key});

  @override
  ConsumerState<CommunityGroupJoinPage> createState() =>
      _CommunityGroupJoinPageState();
}

class _CommunityGroupJoinPageState
    extends ConsumerState<CommunityGroupJoinPage> {
  final _groupId = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _groupId.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canJoin {
    final id = _groupId.text.trim();
    final p = _password.text;
    return id.length >= 32 && p.length >= 4 && p.length <= 8 && !_saving;
  }

  Future<void> _join() async {
    if (!_canJoin) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final svc = ref.read(communityServiceProvider);
    try {
      await svc.joinPrivateGroup(
        groupId: _groupId.text.trim(),
        password: _password.text,
      );
      ref.invalidate(myGroupsProvider);
      if (!mounted) return;
      context.go('/community/group/${_groupId.text.trim()}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _humanize(e);
      });
    }
  }

  String _humanize(Object e) {
    final s = e.toString();
    if (s.contains('password_mismatch')) return '비밀번호가 일치하지 않아요.';
    if (s.contains('group_not_found')) return '그룹을 찾을 수 없어요. 코드를 다시 확인해주세요.';
    if (s.contains('group_not_private')) return '비공개 그룹이 아니에요.';
    if (s.contains('group_full')) return '그룹이 가득 찼어요 (최대 32명).';
    if (s.contains('kicked_recently')) return '최근에 강퇴되어 24시간 동안 재참여할 수 없어요.';
    return '참여 실패. 잠시 후 다시 시도해주세요.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('비밀번호로 참여',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FoodietShape.sp20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('그룹장이 알려준 그룹 ID 와 비밀번호를 입력해주세요.',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
              const SizedBox(height: FoodietShape.sp16),
              const _Label('그룹 ID'),
              TextField(
                controller: _groupId,
                decoration: const InputDecoration(
                  hintText: '예: 1a2b3c4d-...',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FoodietShape.sp16),
              const _Label('비밀번호 (4~8자)'),
              TextField(
                controller: _password,
                maxLength: 8,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: FoodietShape.sp12),
                Text(_error!,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.danger)),
              ],
              const SizedBox(height: FoodietShape.sp24),
              PrimaryButton(
                label: _saving ? '참여 중…' : '참여하기',
                onPressed: _canJoin ? _join : null,
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
