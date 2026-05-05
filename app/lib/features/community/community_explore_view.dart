/// 커뮤니티 > 그룹 탐색 — 공개 그룹 검색/리스트 + 비밀번호 참여 진입.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/community_provider.dart';
import '../../theme/foodiet_tokens.dart';

class CommunityExploreView extends ConsumerStatefulWidget {
  const CommunityExploreView({super.key});

  @override
  ConsumerState<CommunityExploreView> createState() =>
      _CommunityExploreViewState();
}

class _CommunityExploreViewState extends ConsumerState<CommunityExploreView> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(publicGroupsProvider(_query));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp16, FoodietShape.sp8,
          FoodietShape.sp16, FoodietShape.sp8),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: '그룹 이름 검색',
              prefixIcon: const Icon(Icons.search,
                  color: FoodietColors.warm500),
              filled: true,
              fillColor: FoodietColors.cream50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onChanged,
          ),
          const SizedBox(height: FoodietShape.sp8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/community/join'),
              icon: const Icon(Icons.lock_outline,
                  color: FoodietColors.coral500, size: 18),
              label: Text('비밀번호로 참여',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.coral500)),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: FoodietColors.coral500),
              ),
              error: (e, _) => Center(
                child: Text('불러오지 못했어요.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
              ),
              data: (groups) => groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _query.isEmpty
                              ? '아직 공개 그룹이 없어요.\n첫 그룹을 만들어볼까?'
                              : '"$_query" 와 일치하는 그룹이 없어요.',
                          textAlign: TextAlign.center,
                          style: FoodietText.body.copyWith(
                              color: FoodietColors.warm500),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final g = groups[i];
                        return _PublicGroupTile(
                          emoji: g.emoji,
                          name: g.name,
                          description: g.description,
                          onTap: () =>
                              context.push('/community/group/${g.id}'),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicGroupTile extends StatelessWidget {
  const _PublicGroupTile({
    required this.emoji,
    required this.name,
    this.description,
    required this.onTap,
  });
  final String emoji;
  final String name;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(FoodietShape.sp12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: FoodietText.body.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                    if (description != null && description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FoodietText.caption.copyWith(
                                color: FoodietColors.warm500)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: FoodietColors.warm500),
            ],
          ),
        ),
      ),
    );
  }
}
