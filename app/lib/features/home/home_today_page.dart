/// 홈 > 오늘.
///
/// 기획안 §4.7 / §6 — 남은 칼로리 링 + 코치 메시지 + 타임라인.
/// entries 의 `kcal_total` 합계로 남은 칼로리를 계산한다.
///
/// Phase D+F (MVP 완성도 개선):
///   - 각 행에 `title` (음식명 요약) 노출.
///   - `shared_with_count` 로 1인분 환산 kcal 사용.
///   - 탭하면 `/entry/:id` 상세 페이지로 이동 (수정·삭제·공유 인원).
///
/// 커뮤니티 도입 (community_기획서.md):
///   - 기존 우상단 공유(IOS Share) 버튼은 **마이(프로필) 아이콘** 으로 교체.
///     공유 기능은 커뮤니티 탭의 그룹 공유 흐름으로 이동.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/entries_provider.dart';
import '../../providers/home_widget_sync_provider.dart';
import '../../providers/profile_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/ai_coach_card.dart';
import '../../widgets/foodie_bubble.dart';
import '../../widgets/signed_network_image.dart';
import 'quick_record_chips.dart';

class HomeTodayPage extends ConsumerStatefulWidget {
  const HomeTodayPage({super.key});

  @override
  ConsumerState<HomeTodayPage> createState() => _HomeTodayPageState();
}

class _HomeTodayPageState extends ConsumerState<HomeTodayPage> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final nickname = profile?.nickname ?? '후니';
    final target = profile?.dailyKcalTarget ?? 1800;
    final entriesAsync = ref.watch(todayEntriesProvider);
    // pending 엔트리가 있는 동안 3초마다 자동 새로고침 (Realtime 폴백).
    ref.watch(pendingEntriesPollProvider);
    // 홈 데이터가 바뀌면 홈스크린 위젯(iOS/Android) 도 함께 갱신.
    ref.watch(homeWidgetSyncProvider);

    final entries = entriesAsync.valueOrNull ?? const <Entry>[];
    final consumed = entries.fold<int>(
      0,
      // 1인분 환산. shared_with_count=2 면 kcal 의 절반만 내 섭취로 기록.
      (acc, e) => acc + (e.kcalPerPerson ?? 0),
    );
    final remaining = (target - consumed).clamp(0, target).toInt();
    final macros = _sumMacros(entries);
    final hasDoneEntry = entries.any((e) => e.status == 'done');

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('foodiet',
            style:
                FoodietText.h3.copyWith(color: FoodietColors.warm900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FoodietShape.sp8),
            child: _ProfileButton(
              onTap: () => context.push('/profile'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: FoodietColors.coral500,
          onRefresh: () async => ref.invalidate(todayEntriesProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                FoodietShape.sp20, 0, FoodietShape.sp20, FoodietShape.sp40),
            children: [
              Text('안녕, $nickname야 👋',
                  style: FoodietText.h2
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: FoodietShape.sp4),
              Text(entries.isEmpty
                      ? '오늘은 사진 한 장으로 시작해볼까?'
                      : '오늘 기록한 ${entries.length}장, 잘하고 있어 ✨',
                  style: FoodietText.body
                      .copyWith(color: FoodietColors.warm500)),
              const SizedBox(height: FoodietShape.sp16),

              const AiCoachCard(),

              const SizedBox(height: FoodietShape.sp16),

              _KcalCard(
                  remaining: remaining, consumed: consumed, target: target),

              const SizedBox(height: FoodietShape.sp12),

              _MacrosCard(totals: macros, hasDoneEntry: hasDoneEntry),

              const SizedBox(height: FoodietShape.sp20),

              if (entries.isEmpty)
                FoodieBubble(
                  headline: '첫 사진 찍어보자!',
                  why: '기록을 시작하면 여기에 푸디의 조언이 떠.',
                  suggestedAction: '카메라 열기',
                  onTapMore: () => context.push('/camera'),
                ),

              const SizedBox(height: FoodietShape.sp24),

              // 빠른 기록 — 즐겨찾기가 있을 때만 칩 행을 노출 (없으면 shrink).
              const QuickRecordChips(),

              Text('오늘 타임라인',
                  style: FoodietText.title
                      .copyWith(color: FoodietColors.warm700)),
              const SizedBox(height: FoodietShape.sp12),
              if (entriesAsync.isLoading && entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(FoodietShape.sp24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: FoodietColors.coral500,
                    ),
                  ),
                )
              else if (entries.isEmpty)
                const _EmptyTimeline()
              else
                ...entries.map((e) => _TimelineRow(entry: e)),
            ],
          ),
        ),
      ),
    );
  }
}

_MacroTotals _sumMacros(List<Entry> entries) {
  double carb = 0, protein = 0, fat = 0;
  for (final e in entries) {
    if (e.status != 'done') continue;
    final m = e.macros;
    if (m == null) continue;
    final share = e.sharedWithCount < 1 ? 1 : e.sharedWithCount;
    carb += ((m['carb_g'] as num?)?.toDouble() ?? 0) / share;
    protein += ((m['protein_g'] as num?)?.toDouble() ?? 0) / share;
    fat += ((m['fat_g'] as num?)?.toDouble() ?? 0) / share;
  }
  return _MacroTotals(carb: carb, protein: protein, fat: fat);
}

class _MacroTotals {
  const _MacroTotals({
    required this.carb,
    required this.protein,
    required this.fat,
  });
  final double carb;
  final double protein;
  final double fat;
}

class _MacrosCard extends StatelessWidget {
  const _MacrosCard({required this.totals, required this.hasDoneEntry});
  final _MacroTotals totals;
  final bool hasDoneEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('오늘의 영양소 섭취',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: FoodietShape.sp8),
          if (!hasDoneEntry)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FoodietShape.sp4),
              child: Text(
                '기록을 추가하면 탄·단·지가 여기에 쌓여요.',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _MacroCell(
                    label: '탄수',
                    grams: totals.carb,
                    color: FoodietColors.mealBreakfast,
                  ),
                ),
                const SizedBox(width: FoodietShape.sp8),
                Expanded(
                  child: _MacroCell(
                    label: '단백',
                    grams: totals.protein,
                    color: FoodietColors.leaf500,
                  ),
                ),
                const SizedBox(width: FoodietShape.sp8),
                Expanded(
                  child: _MacroCell(
                    label: '지방',
                    grams: totals.fat,
                    color: FoodietColors.mealDinner,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MacroCell extends StatelessWidget {
  const _MacroCell({
    required this.label,
    required this.grams,
    required this.color,
  });
  final String label;
  final double grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: FoodietShape.sp8, vertical: FoodietShape.sp8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: FoodietText.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${grams.toStringAsFixed(grams < 10 ? 1 : 0)}g',
            style: FoodietText.title.copyWith(
              color: FoodietColors.warm900,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _KcalCard extends StatelessWidget {
  const _KcalCard({
    required this.remaining,
    required this.consumed,
    required this.target,
  });
  final int remaining;
  final int consumed;
  final int target;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('오늘의 남은 칼로리',
                        style: FoodietText.caption
                            .copyWith(color: FoodietColors.warm500)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$remaining',
                            style: FoodietText.numberLarge
                                .copyWith(color: FoodietColors.coral500)),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('kcal 남음',
                              style: FoodietText.bodySm.copyWith(
                                  color: FoodietColors.warm500)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: FoodietColors.coral100, width: 8),
                ),
                alignment: Alignment.center,
                child: const Text('🍓', style: TextStyle(fontSize: 28)),
              ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FoodietColors.cream00,
              borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Text('섭취 $consumed / $target kcal',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm700)),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp24),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Center(
        child: Column(
          children: [
            const Text('🥗', style: TextStyle(fontSize: 44)),
            const SizedBox(height: FoodietShape.sp12),
            Text('아직 기록이 없네!',
                style: FoodietText.title
                    .copyWith(color: FoodietColors.warm700)),
            const SizedBox(height: 4),
            Text('첫 사진 찍어보자',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500)),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('HH:mm').format(entry.capturedAt);
    final mealLabel = _mealSlotLabel(entry.mealSlot);
    final mealColor = _mealSlotColor(entry.mealSlot);

    return Padding(
      padding: const EdgeInsets.only(bottom: FoodietShape.sp12),
      child: Material(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        child: InkWell(
          onTap: () => context.push('/entry/${entry.id}'),
          borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(FoodietShape.sp12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    // 72pt × 3x DPR = 216 물리 픽셀. 디코드 크기 제한으로
                    // 메모리 압력을 낮춘다 — ImageCache 덮어쓰기 방지에도 도움.
                    child: SignedNetworkImage(
                      path: entry.imagePath,
                      cacheWidth: 216,
                      cacheHeight: 216,
                    ),
                  ),
                ),
                const SizedBox(width: FoodietShape.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: mealColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(
                                  FoodietShape.radiusSm),
                            ),
                            child: Text(mealLabel,
                                style: FoodietText.caption.copyWith(
                                  color: mealColor,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                          const SizedBox(width: 6),
                          Text(timeLabel,
                              style: FoodietText.caption.copyWith(
                                  color: FoodietColors.warm500)),
                          if (entry.sharedWithCount > 1) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.group_rounded,
                                size: 12, color: FoodietColors.warm500),
                            const SizedBox(width: 2),
                            Text('${entry.sharedWithCount}명',
                                style: FoodietText.caption.copyWith(
                                    color: FoodietColors.warm500)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 음식 이름 — title 이 있으면 표시, 없으면 상태 문구.
                      Text(
                        _primaryLine(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoodietText.body.copyWith(
                          color: FoodietColors.warm900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _secondaryLine(entry),
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm500),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: FoodietColors.warm500, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _primaryLine(Entry e) {
    if (e.status == 'pending') return '푸디가 분석 중…';
    if (e.status == 'failed') return '분석 실패 · 다시 시도';
    return e.title?.trim().isNotEmpty == true ? e.title! : '식사 기록';
  }

  String _secondaryLine(Entry e) {
    if (e.status != 'done') return '';
    final per = e.kcalPerPerson ?? 0;
    if (e.sharedWithCount > 1) {
      return '$per kcal · ${e.kcalTotal ?? 0} kcal 중 1인분';
    }
    return '$per kcal';
  }

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
        return '분석중';
    }
  }

  Color _mealSlotColor(String? slot) {
    switch (slot) {
      case 'breakfast':
        return FoodietColors.mealBreakfast;
      case 'lunch':
        return FoodietColors.mealLunch;
      case 'dinner':
        return FoodietColors.mealDinner;
      case 'late_night':
        return FoodietColors.warm700;
      default:
        return FoodietColors.warm500;
    }
  }
}

/// AppBar 우상단 공유 버튼. 완료된 기록이 하나라도 있어야 활성화.
/// 홈 AppBar 우측 — 설정 진입 아이콘.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '설정',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(Icons.menu_rounded,
                  color: FoodietColors.warm700, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
