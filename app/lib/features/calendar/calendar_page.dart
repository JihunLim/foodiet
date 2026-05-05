/// 기록 탭 — 날짜별 그룹 리스트.
///
/// 기획안 §4.8 / §11 — 달력 히트맵은 v1.1 로 미루고, MVP 는 과거 기록을
/// 날짜별 섹션으로 묶어 스크롤하게 한다. 각 행은 썸네일 + 끼니 라벨 +
/// kcal + 분석 상태.
///
/// Phase D+E+F (MVP 완성도 개선):
///   - title (음식명) + 1인분 환산 kcal + 공유 인원 배지.
///   - 탭하면 /entry/:id 상세로 이동.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/entries_provider.dart';
import '../../services/daily_share_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';

class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(recentEntriesProvider);
    // pending 엔트리가 있는 동안 3초마다 자동 새로고침 (Realtime 폴백).
    ref.watch(pendingEntriesPollProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('기록',
            style:
                FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: FoodietColors.coral500,
          onRefresh: () async => ref.invalidate(recentEntriesProvider),
          child: entriesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: FoodietColors.coral500,
              ),
            ),
            error: (e, _) => ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(FoodietShape.sp20),
                    child: Text('기록을 불러오지 못했어: $e',
                        textAlign: TextAlign.center,
                        style: FoodietText.body
                            .copyWith(color: FoodietColors.warm700)),
                  ),
                ),
              ],
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 80),
                    _EmptyState(),
                  ],
                );
              }
              final groups = _groupByDay(entries);
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    FoodietShape.sp20, 0, FoodietShape.sp20, FoodietShape.sp40),
                itemCount: groups.length,
                itemBuilder: (_, i) =>
                    _DaySection(date: groups[i].date, entries: groups[i].items),
              );
            },
          ),
        ),
      ),
    );
  }

  List<_DayGroup> _groupByDay(List<Entry> entries) {
    final Map<String, _DayGroup> map = {};
    for (final e in entries) {
      final local = e.capturedAt;
      final key = DateFormat('yyyy-MM-dd').format(local);
      final d = DateTime(local.year, local.month, local.day);
      map.putIfAbsent(key, () => _DayGroup(date: d, items: [])).items.add(e);
    }
    final list = map.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
}

class _DayGroup {
  _DayGroup({required this.date, required this.items});
  final DateTime date;
  final List<Entry> items;
}

class _DaySection extends ConsumerStatefulWidget {
  const _DaySection({required this.date, required this.entries});
  final DateTime date;
  final List<Entry> entries;

  @override
  ConsumerState<_DaySection> createState() => _DaySectionState();
}

class _DaySectionState extends ConsumerState<_DaySection> {
  bool _sharing = false;

  Future<void> _onShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await ref
          .read(dailyShareServiceProvider)
          .shareDay(context, widget.date, widget.entries);
    } on DailyShareException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      _showSnack('공유 이미지를 만드는 데 실패했어요.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final entries = widget.entries;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1]; // DateTime.weekday: 1=월..7=일
    final label = date == today
        ? '오늘'
        : date == yesterday
            ? '어제'
            : '${date.month}월 ${date.day}일 ($weekday)';
    // 1인분 환산으로 합산.
    final kcalSum = entries.fold<int>(0, (a, e) => a + (e.kcalPerPerson ?? 0));
    final hasDoneEntry = entries.any((e) => e.status == 'done');

    return Padding(
      padding: const EdgeInsets.only(top: FoodietShape.sp20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: FoodietText.title
                              .copyWith(color: FoodietColors.warm900)),
                    ),
                    const SizedBox(width: 8),
                    Text('· $kcalSum kcal',
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm500)),
                  ],
                ),
              ),
              _DayShareButton(
                enabled: hasDoneEntry && !_sharing,
                loading: _sharing,
                onTap: _onShare,
                disabledReason: !hasDoneEntry
                    ? (entries.isEmpty
                        ? '공유할 식사 기록이 없어요'
                        : '분석이 아직 진행 중이에요')
                    : '공유 준비 중이에요',
              ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp8),
          ...entries.map((e) => _EntryRow(entry: e)),
        ],
      ),
    );
  }
}

/// 일자 섹션 우측 공유 아이콘. Home AppBar 의 `_ShareButton` 과 동일한 UX.
class _DayShareButton extends StatelessWidget {
  const _DayShareButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
    required this.disabledReason,
  });
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  final String disabledReason;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? FoodietColors.coral500 : FoodietColors.warm500;
    return Tooltip(
      message: enabled ? '이 날 식단 공유' : disabledReason,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FoodietColors.coral500,
                      ),
                    )
                  : Icon(Icons.ios_share_rounded, color: color, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('HH:mm').format(entry.capturedAt);
    final mealLabel = _mealSlotLabel(entry.mealSlot);
    final mealColor = _mealSlotColor(entry.mealSlot);

    return Padding(
      padding: const EdgeInsets.only(top: FoodietShape.sp8),
      child: Material(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
          onTap: () => context.push('/entry/${entry.id}'),
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
                    width: 64,
                    height: 64,
                    // 64pt × 3x DPR = 192 물리 픽셀.
                    child: SignedNetworkImage(
                      path: entry.imagePath,
                      cacheWidth: 192,
                      cacheHeight: 192,
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
                      Text(
                        _primaryLine(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoodietText.body.copyWith(
                          color: FoodietColors.warm900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (entry.status == 'done')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            entry.sharedWithCount > 1
                                ? '${entry.kcalPerPerson ?? 0} kcal · '
                                    '${entry.kcalTotal ?? 0} kcal 중 1인분'
                                : '${entry.kcalPerPerson ?? 0} kcal',
                            style: FoodietText.bodySm
                                .copyWith(color: FoodietColors.warm500),
                          ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📅', style: TextStyle(fontSize: 44)),
          const SizedBox(height: FoodietShape.sp12),
          Text('아직 기록이 없네',
              style: FoodietText.title
                  .copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: 4),
          Text('홈에서 첫 사진을 찍어보자',
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm500)),
        ],
      ),
    );
  }
}
