/// 그룹 멤버 초대 — 닉네임 검색 + 닉네임순 사용자 리스트 + 초대 버튼.
///
/// 초대를 누르면 send_group_invite RPC 호출. 결과는 마이 탭의
/// "그룹 초대장" 에 즉시 반영 (realtime).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/community_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityGroupInvitePage extends ConsumerStatefulWidget {
  const CommunityGroupInvitePage({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<CommunityGroupInvitePage> createState() =>
      _CommunityGroupInvitePageState();
}

class _CommunityGroupInvitePageState
    extends ConsumerState<CommunityGroupInvitePage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;
  // 이미 초대 보낸 사용자 — 클라이언트 메모리상 즉시 반영 (RPC 결과는 캐시 갱신 후).
  final Set<String> _invitedUserIds = <String>{};
  // 진행 중인 초대 — 더블탭 방지.
  final Set<String> _pendingUserIds = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  Future<void> _invite(UserHandle u) async {
    if (_pendingUserIds.contains(u.userId)) return;
    setState(() => _pendingUserIds.add(u.userId));
    try {
      await ref.read(communityServiceProvider).sendGroupInvite(
            groupId: widget.groupId,
            inviteeUserId: u.userId,
          );
      if (!mounted) return;
      setState(() {
        _invitedUserIds.add(u.userId);
        _pendingUserIds.remove(u.userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${u.nickname} 님에게 초대를 보냈어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingUserIds.remove(u.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanError(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _humanError(Object e) {
    final s = e.toString();
    if (s.contains('already_member')) return '이미 그룹에 참여하고 있어요.';
    if (s.contains('group_full')) return '그룹 정원이 가득 찼어요.';
    if (s.contains('blocked')) return '차단 관계라 초대할 수 없어요.';
    if (s.contains('kicked_recently')) return '24시간 내 강퇴된 사용자라 초대할 수 없어요.';
    if (s.contains('not_group_member')) return '이 그룹의 멤버만 초대할 수 있어요.';
    return '초대를 보내지 못했어요.';
  }

  @override
  Widget build(BuildContext context) {
    final args = (query: _query, excludeGroupId: widget.groupId);
    final usersAsync = ref.watch(userDirectoryProvider(args));

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('초대',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FoodietShape.sp16, FoodietShape.sp12,
                    FoodietShape.sp16, FoodietShape.sp8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '닉네임으로 검색',
                    prefixIcon: const Icon(Icons.search,
                        color: FoodietColors.warm500),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: FoodietColors.warm500),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: FoodietColors.cream50,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                  ),
                ),
              ),
              Expanded(
                child: usersAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: FoodietColors.coral500)),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(FoodietShape.sp20),
                      child: Text('사용자 목록을 불러오지 못했어요.\n$e',
                          textAlign: TextAlign.center,
                          style: FoodietText.bodySm
                              .copyWith(color: FoodietColors.warm500)),
                    ),
                  ),
                  data: (users) {
                    if (users.isEmpty) {
                      return Center(
                        child: Text(
                          _query.isEmpty
                              ? '초대할 수 있는 사용자가 없어요.'
                              : '"$_query" 와(과) 일치하는 사용자가 없어요.',
                          style: FoodietText.bodySm
                              .copyWith(color: FoodietColors.warm500),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: FoodietShape.sp16,
                          vertical: FoodietShape.sp8),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: FoodietColors.cream100),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final invited = _invitedUserIds.contains(u.userId);
                        final pending = _pendingUserIds.contains(u.userId);
                        return _UserRow(
                          handle: u,
                          invited: invited,
                          pending: pending,
                          onInvite: () => _invite(u),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.handle,
    required this.invited,
    required this.pending,
    required this.onInvite,
  });
  final UserHandle handle;
  final bool invited;
  final bool pending;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: FoodietColors.cream100,
            child: Text(
              _firstChar(handle.nickname),
              style: FoodietText.bodySm.copyWith(
                  color: FoodietColors.warm700, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(handle.nickname,
                style: FoodietText.body.copyWith(
                    color: FoodietColors.warm900,
                    fontWeight: FontWeight.w600)),
          ),
          if (invited)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: FoodietColors.cream50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('초대됨',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
            )
          else
            FilledButton(
              onPressed: pending ? null : onInvite,
              style: FilledButton.styleFrom(
                backgroundColor: FoodietColors.coral500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                minimumSize: const Size(0, 36),
              ),
              child: pending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('초대'),
            ),
        ],
      ),
    );
  }

  String _firstChar(String s) {
    if (s.isEmpty) return '?';
    return s.characters.first;
  }
}
