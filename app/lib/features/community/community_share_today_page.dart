/// 오늘 식단 공유 페이지 — 그룹 선택 + 항목 선택 + 공개 항목 토글 + 캡션.
///
/// 흐름:
///   1. 내 그룹 목록을 보여주고 1개 선택 (없으면 "그룹 만들기" 안내).
///   2. 오늘 `done` entries 체크리스트. 이미 같은 그룹/날짜에 공유한 항목은
///      "이미 공유됨" 라벨 + 기본 미선택 (사용자가 원하면 override 가능).
///   3. 사진/칼로리/영양소 토글 — 멤버십 기본값을 채움.
///   4. 캡션 (선택, 200자 이내).
///   5. 공유 버튼 → community_posts INSERT (선택 entries 합산) + 그룹 상세로 이동.
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
import '../../widgets/signed_network_image.dart';

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

  /// 사용자가 체크한 entry id들.
  final Set<String> _selectedEntryIds = <String>{};

  /// 이 그룹/오늘 날짜에 내가 이미 공유한 entry id들. 기본 미선택 처리에 사용.
  Set<String> _alreadyShared = <String>{};

  /// `_alreadyShared` 가 어떤 그룹 기준으로 fetch 됐는지. 그룹 바꾸면 다시 fetch.
  String? _alreadySharedForGroupId;
  bool _loadingAlreadyShared = false;

  /// 토글 기본값을 멤버십에서 한 번만 채웠는지.
  bool _togglesPrimed = false;

  /// 선택 기본값을 한 번 깔았는지 (그룹 기준). 그룹 바뀌면 false 로 리셋.
  bool _selectionPrimedForGroup = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _fetchAlreadyShared(String groupId) async {
    if (_alreadySharedForGroupId == groupId) return;
    if (_loadingAlreadyShared) return;
    _loadingAlreadyShared = true;
    try {
      final svc = ref.read(communityServiceProvider);
      final shared = await svc.alreadySharedEntryIds(
        groupId: groupId,
        postDate: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _alreadyShared = shared;
        _alreadySharedForGroupId = groupId;
        _selectionPrimedForGroup = false;
      });
    } catch (_) {
      // 실패하면 빈 집합으로 처리 — 모두 선택 가능 상태로 fallback.
      if (!mounted) return;
      setState(() {
        _alreadyShared = <String>{};
        _alreadySharedForGroupId = groupId;
        _selectionPrimedForGroup = false;
      });
    } finally {
      _loadingAlreadyShared = false;
    }
  }

  void _primeSelectionIfNeeded(List<Entry> doneEntries) {
    if (_selectionPrimedForGroup) return;
    _selectedEntryIds
      ..clear()
      ..addAll(doneEntries
          .where((e) => !_alreadyShared.contains(e.id))
          .map((e) => e.id));
    _selectionPrimedForGroup = true;
  }

  void _primeTogglesFromMembership(GroupMember? m) {
    if (_togglesPrimed || m == null) return;
    _showPhotos = m.showPhotos;
    _showKcal = m.showKcal;
    _showMacros = m.showMacros;
    _togglesPrimed = true;
  }

  Future<void> _submit(List<Entry> doneEntries) async {
    if (_saving) return;
    final groupId = _selectedGroupId;
    final user = ref.read(currentUserProvider);
    if (groupId == null || user == null) return;

    final picked = doneEntries
        .where((e) => _selectedEntryIds.contains(e.id))
        .toList();
    if (picked.isEmpty) {
      _showSnack('공유할 항목을 1개 이상 선택해줘.');
      return;
    }

    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      final target = profile?.dailyKcalTarget ?? 1800;
      final consumed = picked.fold<int>(
          0, (acc, e) => acc + (e.kcalPerPerson ?? 0));
      final achievement =
          target == 0 ? 0.0 : (consumed * 100 / target);
      final badge = _badgeFor(achievement);

      // 선택한 entries 중 사진이 있는 것만 captured_at 순으로 첫 4장.
      final photoPaths = picked
          .where((e) => e.imagePath.isNotEmpty)
          .map((e) => e.imagePath)
          .take(4)
          .toList();

      final macros = _sumMacros(picked);

      final svc = ref.read(communityServiceProvider);
      final showPhotos = _showPhotos ?? true;
      final showKcal = _showKcal ?? true;
      final showMacros = _showMacros ?? true;

      await svc.createPost(
        groupId: groupId,
        userId: user.id,
        postDate: DateTime.now(),
        entryIds: picked.map((e) => e.id).toList(),
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
      // share page 닫고 커뮤니티 메인(내 그룹 탭)으로 복귀.
      // invalidate 로 피드는 이미 최신 — 사용자가 거기서 본인 카드를 본다.
      context.pop();
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

  String _mealSlotLabel(String? slot) {
    switch (slot) {
      case 'breakfast':
        return '아침';
      case 'lunch':
        return '점심';
      case 'dinner':
        return '저녁';
      case 'late_night':
        return '야식';
      default:
        return '';
    }
  }

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
    final entriesAsync = ref.watch(todayEntriesProvider);

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

            // 그룹이 바뀌면 already_shared 다시 fetch.
            // (현재 frame 이 끝난 뒤 호출해야 setState 충돌 없음.)
            if (_alreadySharedForGroupId != selectedId &&
                !_loadingAlreadyShared) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fetchAlreadyShared(selectedId);
              });
            }

            final membersAsync = ref.watch(groupMembersProvider(selectedId));
            final myUserId = ref.watch(currentUserProvider)?.id;
            final myMember = (membersAsync.valueOrNull ?? const [])
                .where((m) => m.userId == myUserId)
                .firstOrNull;
            _primeTogglesFromMembership(myMember);

            return entriesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: FoodietColors.coral500)),
              error: (_, __) =>
                  const Center(child: Text('오늘 식단을 불러오지 못했어요.')),
              data: (entries) {
                final done =
                    entries.where((e) => e.status == 'done').toList();
                _primeSelectionIfNeeded(done);

                return ListView(
                  padding: const EdgeInsets.all(FoodietShape.sp20),
                  children: [
                    Text(
                      '${DateFormat('M월 d일').format(DateTime.now())} 오늘 식단을 어디에 공유할까?',
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.warm500),
                    ),
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
                            if (v == null) return;
                            setState(() {
                              _selectedGroupId = v;
                              // 그룹 바뀌면 토글/선택 모두 리셋 — 새 멤버십·이력 기준으로 다시 채움.
                              _togglesPrimed = false;
                              _showPhotos = null;
                              _showKcal = null;
                              _showMacros = null;
                              _selectionPrimedForGroup = false;
                              _alreadySharedForGroupId = null;
                              _alreadyShared = <String>{};
                            });
                          },
                        )),
                    const SizedBox(height: FoodietShape.sp16),
                    _EntryPickerSection(
                      entries: done,
                      selectedIds: _selectedEntryIds,
                      alreadyShared: _alreadyShared,
                      onToggle: (id) {
                        setState(() {
                          if (_selectedEntryIds.contains(id)) {
                            _selectedEntryIds.remove(id);
                          } else {
                            _selectedEntryIds.add(id);
                          }
                        });
                      },
                      mealLabelOf: _mealSlotLabel,
                    ),
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
                    Text('한마디 (선택)',
                        style: FoodietText.bodySm.copyWith(
                            color: FoodietColors.warm700,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _caption,
                      maxLength: 200,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) =>
                          FocusScope.of(context).unfocus(),
                      decoration: const InputDecoration(
                        hintText: '예: 점심 닭가슴살 굿!',
                      ),
                    ),
                    const SizedBox(height: FoodietShape.sp24),
                    PrimaryButton(
                      label: _saving ? '공유 중…' : '공유하기',
                      onPressed: _saving ? null : () => _submit(done),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 오늘 entries 체크리스트. 이미 공유된 항목은 옅게 + "이미 공유됨" 라벨,
/// 기본 미선택. 사용자는 override 해서 다시 포함시킬 수 있다.
class _EntryPickerSection extends StatelessWidget {
  const _EntryPickerSection({
    required this.entries,
    required this.selectedIds,
    required this.alreadyShared,
    required this.onToggle,
    required this.mealLabelOf,
  });

  final List<Entry> entries;
  final Set<String> selectedIds;
  final Set<String> alreadyShared;
  final void Function(String entryId) onToggle;
  final String Function(String? slot) mealLabelOf;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FoodietColors.cream100,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        ),
        child: Text('오늘 분석이 끝난 식단 기록이 없어요. 사진을 한 장이라도 남겨보자!',
            style: FoodietText.bodySm
                .copyWith(color: FoodietColors.warm700)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공유할 항목',
            style: FoodietText.bodySm.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: FoodietShape.sp8),
        ...entries.map((e) {
          final isSelected = selectedIds.contains(e.id);
          final isShared = alreadyShared.contains(e.id);
          final meal = mealLabelOf(e.mealSlot);
          final kcal = e.kcalPerPerson;
          return InkWell(
            // 이미 공유된 항목은 탭/체크 모두 잠금.
            onTap: isShared ? null : () => onToggle(e.id),
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Opacity(
                opacity: isShared ? 0.5 : 1.0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: isShared ? false : isSelected,
                      activeColor: FoodietColors.coral500,
                      onChanged: isShared ? null : (_) => onToggle(e.id),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: e.imagePath.isEmpty
                            ? Container(color: FoodietColors.cream100)
                            : SignedNetworkImage(
                                path: e.imagePath,
                                cacheWidth: 88,
                                cacheHeight: 88,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title?.isNotEmpty == true
                                ? e.title!
                                : (meal.isEmpty ? '식단' : meal),
                            style: FoodietText.body.copyWith(
                                color: FoodietColors.warm900,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (meal.isNotEmpty) ...[
                                Text(meal,
                                    style: FoodietText.caption.copyWith(
                                        color: FoodietColors.warm500)),
                                const SizedBox(width: 8),
                              ],
                              if (kcal != null)
                                Text('${kcal}kcal',
                                    style: FoodietText.caption.copyWith(
                                        color: FoodietColors.warm500)),
                              if (isShared) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: FoodietColors.cream100,
                                    borderRadius:
                                        BorderRadius.circular(FoodietShape.radiusXs),
                                  ),
                                  child: Text('이미 공유됨',
                                      style: FoodietText.caption.copyWith(
                                          color: FoodietColors.warm700,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
