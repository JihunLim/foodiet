/// 커뮤니티 메인 탭.
///
/// 기획서 §4.2 — 상단 [내 그룹] / [그룹 탐색] 두 세그먼트.
///   · 내 그룹: 참여 중인 그룹 셀렉터 + 선택된 그룹 피드
///   · 그룹 탐색: 공개 그룹 검색/리스트 + "비밀번호로 참여"
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/foodiet_tokens.dart';
import 'community_my_groups_view.dart';
import 'community_explore_view.dart';

class CommunityPage extends ConsumerStatefulWidget {
  const CommunityPage({super.key});

  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('커뮤니티',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
        bottom: TabBar(
          controller: _tab,
          labelColor: FoodietColors.coral500,
          unselectedLabelColor: FoodietColors.warm500,
          indicatorColor: FoodietColors.coral500,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: FoodietText.title
              .copyWith(fontWeight: FontWeight.w800, fontSize: 18),
          unselectedLabelStyle: FoodietText.title
              .copyWith(fontWeight: FontWeight.w700, fontSize: 18),
          tabs: const [
            Tab(text: '내 그룹'),
            Tab(text: '그룹 탐색'),
          ],
        ),
        actions: [
          // 탭 인덱스에 따라 다른 액션. AnimatedBuilder 로 _tab 변경 listen.
          AnimatedBuilder(
            animation: _tab,
            builder: (_, __) {
              final isMyGroups = _tab.index == 0;
              return IconButton(
                tooltip: isMyGroups ? '오늘 식단 공유' : '새 그룹 만들기',
                icon: Icon(
                  isMyGroups
                      ? Icons.add_a_photo_outlined
                      : Icons.group_add_outlined,
                  color: FoodietColors.warm900,
                ),
                onPressed: () {
                  if (isMyGroups) {
                    context.push('/community/share-today');
                  } else {
                    context.push('/community/new');
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tab,
          children: const [
            CommunityMyGroupsView(),
            CommunityExploreView(),
          ],
        ),
      ),
    );
  }
}
