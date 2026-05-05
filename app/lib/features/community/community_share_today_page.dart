/// 오늘 식단 공유 페이지 — 그룹 선택 + 공개 항목 토글 + 캡션.
///
/// 흐름:
///   1. 내 그룹 목록을 보여주고 1개 선택 (없으면 "그룹 만들기" 안내).
///   2. 사진/칼로리/영양소 토글 — 멤버십 기본값을 채움.
///   3. 캡션 (선택, 200자 이내).
///   4. 공유 버튼 → community_posts INSERT + 즉시 그룹 상세로 이동.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/entries_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/community/community_models.dart';
import '../../services/community/community_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

class CommunityShareTodayPage extends ConsumerStatefulWidget {
  const CommunityShareTodayPage({super.key});

  @override
  ConsumerState<CommunityShareTodayPage> createState() =>
      _CommunityShareTodayPageState();
}

class _CommunityShareTodayPageState
    extends ConsumerState<CommunityShareTodayPage> {
  String? _selectedGroupId;
  final _caption = TextEditingController();
  bool? _showPhotos;
  bool? _showKcal;
  bool? _showMacros;
  bool _saving = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  // 멤버십 기본값으로 토글 채우기 (한 번만).
  void _ensureDefaultsFromMembership(GroupMember? m) {
    if (m == null) return;
    _showPhotos ??= m.showPhotos;
    _showKcal ??= m.showKcal;
    _showMacros ??= m.showMacros;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final groupId = _selectedGroupId;
    final user = ref.read(currentUserProvider);
    if (groupId == null || user == null) return;

    final entries = await ref.read(todayEntriesProvider.future);
    final done = entries.where((e) => e.status == 'done').toList();
    if (done.isEmpty) {
      _showSnack('공유할 식단 기록이 없어요. 사진을 한 장이라도 남겨보자!');
      return;
    }

    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      final target = profile?.dailyKcalTarget ?? 1800;
      final consumed = done.fold<int>(
          0, (acc, e) => acc + (e.kcalPerPerson ?? 0));
      final achievement =
          target == 0 ? 0.0 : (consumed * 100 / target);
      final badge = _badgeFor(achievement);

      // 사진 경로 — 끼니별 대표 1장. 단순히 captured_at 순으로 첫 4장.
      final photoPaths = done
          .map((e) => e.imagePath)
          .where((p) => p.isNotEmpty)
          .take(4)
          .toList();

      // 매크로 합계.
      final macros = _sumMacros(done);

      final svc = ref.read(communityServiceProvider);
      final showPhotos = _showPhotos ?? true;
      final showKcal = _showKcal ?? true;
      final showMacros = _showMacros ?? true;

      final id = await svc.createPost(
        groupId: groupId,
        userId: user.id,
        postDate: DateTime.now(),
        totalKcal: consumed,
        targetKcal: target,
        macros: macros,
        achievement: achievement,
        statusBadge: badge,
        photoPaths: photoPaths,
        showPhotos: showPhotos,
        showKcal: showKcal,
        showMacros: showMacros,
        caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
      );
      invalidateCommunityFor(ref, groupId: groupId);
      if (!mounted) return;
      context.go('/community/group/$groupId/post/$id');
    } catch (e) {
      if (!mounted) return;
      _showSnack('공유에 실패했어요: ${_short(e.toString())}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, num>? _sumMacros(List<Entry> entries) {
    double carb = 0, protein = 0, fat = 0;
    var any = false;
    for (final e in entries) {
      final m = e.macros;
      if (m == null) continue;
      any = true;
      carb += (m['carb_g'] as num?)?.toDouble() ?? 0;
      protein += (m['protein_g'] as num?)?.toDouble() ?? 0;
      fat += (m['fat_g'] as num?)?.toDouble() ?? 0;
    }
    if (!any) return null;
    return {
      'carb_g': carb.round(),
      'protein_g': protein.round(),
      'fat_g': fat.round(),
    };
  }

  String _badgeFor(double achievement) {
    if (achievement >= 90 && achievement <= 110) return 'achieved';
    if (achievement >= 70 && achievement < 90) return 'almost';
    return 'retry';
  }

  String _short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

  void _showSnack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FoodietColors.warm700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('오늘 식단 공유',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: groupsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: FoodietColors.coral500)),
          error: (_, __) =>
              const Center(child: Text('그룹을 불러오지 못했어요.')),
          data: (groups) {
            if (groups.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.groups_outlined,
                        color: FoodietColors.warm500, size: 48),
                    const SizedBox(height: 12),
                    Text('아직 참여 중인 그룹이 없어요.',
                        style: FoodietText.body
                            .copyWith(color: FoodietColors.warm700)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/community/new'),
                      style: FilledButton.styleFrom(
                        backgroundColor: FoodietColors.coral500,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('새 그룹 만들기'),
                    ),
                  ],
                ),
              );
            }
            _selectedGroupId ??= groups.first.id;
            final selectedId = _selectedGroupId!;
            // 선택된 그룹의 내 멤버십 기본값을 토글에 채워준다.
            final membersAsync = ref.watch(groupMembersProvider(selectedId));
            final myUserId = ref.watch(currentUserProvider)?.id;
            final myMember = (membersAsync.valueOrNull ?? const [])
                .where((m) => m.userId == myUserId)
                .firstOrNull;
            _ensureDefaultsFromMembership(myMember);

            return ListView(
              padding: const EdgeInsets.all(FoodietShape.sp20),
              children: [
                Text('${DateFormat('M월 d일').format(DateTime.now())} 오늘 식단을 어디에 공유할까?',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: FoodietShape.sp12),
                ...groups.map((g) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Text(g.emoji,
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(g.name)),
                        ],
                      ),
                      value: g.id,
                      groupValue: selectedId,
                      activeColor: FoodietColors.coral500,
                      onChanged: (v) {
                        setState(() {
                          _selectedGroupId = v;
                          // 그룹 바뀌면 토글 초기화 — 새 멤버십 기본값으로 다시 채움.
                          _showPhotos = null;
                          _showKcal = null;
                          _showMacros = null;
                        });
                      },
                    )),
                const SizedBox(height: FoodietShape.sp16),
                Text('이 카드에 포함할 정보',
                    style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm700,
                        fontWeight: FontWeight.w700)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('음식 사진'),
                  value: _showPhotos ?? true,
                  activeThumbColor: FoodietColors.coral500,
                  onChanged: (v) => setState(() => _showPhotos = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('칼로리'),
                  value: _showKcal ?? true,
                  activeThumbColor: FoodietColors.coral500,
                  onChanged: (v) => setState(() => _showKcal = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('영양소(탄단지)'),
                  value: _showMacros ?? true,
                  activeThumbColor: FoodietColors.coral500,
                  onChanged: (v) => setState(() => _showMacros = v),
                ),
                const SizedBox(height: FoodietShape.sp12),
                TextField(
                  controller: _caption,
                  maxLength: 200,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '한마디 (선택)',
                    hintText: '예: 점심 닭가슴살 굿!',
                  ),
                ),
                const SizedBox(height: FoodietShape.sp24),
                PrimaryButton(
                  label: _saving ? '공유 중…' : '공유하기',
                  onPressed: _saving ? null : _submit,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
