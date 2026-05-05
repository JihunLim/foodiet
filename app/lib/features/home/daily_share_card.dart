/// PT 친구에게 공유하기 — "오늘의 식단" 카드.
///
/// 기획안 §4.7 확장. Home AppBar 의 share 버튼이 이 위젯을 off-screen 에
/// 붙였다가 `RepaintBoundary.toImage(pixelRatio: 3.0)` 으로 PNG 로 뽑는다.
///
/// ── 디자인 지침 ─────────────────────────────────────────────
/// · 가로 폭 360 logical px → pixelRatio 3 이면 1080 px 이미지 (인스타/카톡 OK).
/// · 컬러·타입은 FoodietTokens 만 사용 (§7 1:1 거울).
/// · 네트워크 썸네일은 호출자가 `precacheImage` 로 미리 로드한 상태여야 한다.
///   (toImage 는 비동기 로드 중인 이미지를 그려주지 않는다.)
library;

import 'package:flutter/material.dart';
// intl 이 TextDirection 클래스를 재정의해 TextDirection.ltr 을 가리기 때문에
// hide.
import 'package:intl/intl.dart' hide TextDirection;

import '../../providers/entries_provider.dart';
import '../../theme/foodiet_tokens.dart';

class DailyShareCardData {
  const DailyShareCardData({
    required this.date,
    required this.nickname,
    required this.targetKcal,
    required this.entries,
    required this.photoUrls,
  });

  final DateTime date;
  final String nickname;
  final int targetKcal;

  /// status == 'done' 인 엔트리만 들어와야 한다.
  final List<Entry> entries;

  /// image_path → signed URL. 호출자가 precacheImage 완료한 상태.
  final Map<String, String> photoUrls;
}

class DailyShareCard extends StatelessWidget {
  const DailyShareCard({super.key, required this.data});
  final DailyShareCardData data;

  static const double cardWidth = 360;

  @override
  Widget build(BuildContext context) {
    final consumed = data.entries.fold<int>(
      0,
      (acc, e) => acc + (e.kcalPerPerson ?? 0),
    );
    final progress = data.targetKcal <= 0
        ? 0.0
        : (consumed / data.targetKcal).clamp(0.0, 1.0);
    final remaining = (data.targetKcal - consumed)
        .clamp(-9999, 99999)
        .toInt();

    final totals = _sumMacros(data.entries);

    return MediaQuery(
      // 시스템 텍스트 스케일이 공유 이미지에 영향 주면 안 됨.
      data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: cardWidth,
            padding: const EdgeInsets.all(FoodietShape.sp20),
            decoration: BoxDecoration(
              color: FoodietColors.cream00,
              borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(date: data.date),
                const SizedBox(height: FoodietShape.sp16),
                _SummaryTitle(
                  nickname: data.nickname,
                  entryCount: data.entries.length,
                  consumed: consumed,
                  dayLabel: _dayLabel(data.date),
                ),
                const SizedBox(height: FoodietShape.sp16),
                _KcalPanel(
                  consumed: consumed,
                  target: data.targetKcal,
                  remaining: remaining,
                  progress: progress,
                ),
                const SizedBox(height: FoodietShape.sp12),
                _MacroRow(totals: totals),
                const SizedBox(height: FoodietShape.sp20),
                if (data.entries.isEmpty)
                  const _EmptyHint()
                else
                  ...data.entries.map((e) => _EntryRow(
                        entry: e,
                        url: data.photoUrls[e.imagePath],
                      )),
                const SizedBox(height: FoodietShape.sp16),
                _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 날짜에 따른 "오늘 / 어제 / M월 d일" 라벨.
  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return DateFormat('M월 d일', 'ko').format(target);
  }

  _MacroTotals _sumMacros(List<Entry> entries) {
    double carb = 0, protein = 0, fat = 0;
    for (final e in entries) {
      final m = e.macros;
      if (m == null) continue;
      final share = e.sharedWithCount < 1 ? 1 : e.sharedWithCount;
      carb += ((m['carb_g'] as num?)?.toDouble() ?? 0) / share;
      protein += ((m['protein_g'] as num?)?.toDouble() ?? 0) / share;
      fat += ((m['fat_g'] as num?)?.toDouble() ?? 0) / share;
    }
    return _MacroTotals(carb: carb, protein: protein, fat: fat);
  }
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

// ─── header ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('yyyy.MM.dd (EEE)', 'ko').format(date.toLocal());
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            const Text('🍓', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              'foodiet',
              style: FoodietText.title.copyWith(
                color: FoodietColors.coral500,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        Text(
          dateLabel,
          style: FoodietText.caption.copyWith(
            color: FoodietColors.warm500,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─── summary title ──────────────────────────────────────────────────────

class _SummaryTitle extends StatelessWidget {
  const _SummaryTitle({
    required this.nickname,
    required this.entryCount,
    required this.consumed,
    required this.dayLabel,
  });
  final String nickname;
  final int entryCount;
  final int consumed;
  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$nickname의 $dayLabel 식단',
          style: FoodietText.h2.copyWith(
            color: FoodietColors.warm900,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          entryCount == 0
              ? '아직 기록이 없어요'
              : '$entryCount끼 · ${NumberFormat.decimalPattern().format(consumed)} kcal 섭취',
          style: FoodietText.bodySm.copyWith(color: FoodietColors.warm500),
        ),
      ],
    );
  }
}

// ─── kcal panel ─────────────────────────────────────────────────────────

class _KcalPanel extends StatelessWidget {
  const _KcalPanel({
    required this.consumed,
    required this.target,
    required this.remaining,
    required this.progress,
  });
  final int consumed;
  final int target;
  final int remaining;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final remainLabel = remaining >= 0
        ? '${NumberFormat.decimalPattern().format(remaining)} kcal 남았어요'
        : '목표보다 ${NumberFormat.decimalPattern().format(-remaining)} kcal 초과';
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormat.decimalPattern().format(consumed),
                style: FoodietText.numberLarge.copyWith(
                  color: FoodietColors.coral500,
                  fontSize: 34,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ ${NumberFormat.decimalPattern().format(target)} kcal',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500),
                ),
              ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: FoodietColors.coral100,
              valueColor: const AlwaysStoppedAnimation<Color>(
                FoodietColors.coral500,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            remainLabel,
            style: FoodietText.caption
                .copyWith(color: FoodietColors.warm700, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── macro row ──────────────────────────────────────────────────────────

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.totals});
  final _MacroTotals totals;

  @override
  Widget build(BuildContext context) {
    return Row(
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

// ─── entry rows ─────────────────────────────────────────────────────────

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.url});
  final Entry entry;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('HH:mm').format(entry.capturedAt);
    final mealLabel = _mealSlotLabel(entry.mealSlot);
    final mealColor = _mealSlotColor(entry.mealSlot);
    final kcal = entry.kcalPerPerson ?? 0;
    final macros = entry.macros;
    final share = entry.sharedWithCount < 1 ? 1 : entry.sharedWithCount;

    final carb = macros == null
        ? null
        : ((macros['carb_g'] as num?)?.toDouble() ?? 0) / share;
    final protein = macros == null
        ? null
        : ((macros['protein_g'] as num?)?.toDouble() ?? 0) / share;
    final fat = macros == null
        ? null
        : ((macros['fat_g'] as num?)?.toDouble() ?? 0) / share;

    return Padding(
      padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
      child: Container(
        padding: const EdgeInsets.all(FoodietShape.sp8),
        decoration: BoxDecoration(
          color: FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.cream100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
              child: SizedBox(
                width: 64,
                height: 64,
                child: url == null
                    ? _thumbFallback()
                    : Image.network(
                        url!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbFallback(),
                      ),
              ),
            ),
            const SizedBox(width: FoodietShape.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: mealColor.withValues(alpha: 0.16),
                          borderRadius:
                              BorderRadius.circular(FoodietShape.radiusSm),
                        ),
                        child: Text(
                          mealLabel,
                          style: FoodietText.caption.copyWith(
                            color: mealColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeLabel,
                        style: FoodietText.caption.copyWith(
                          color: FoodietColors.warm500,
                          fontSize: 11,
                        ),
                      ),
                      if (entry.sharedWithCount > 1) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.group_rounded,
                            size: 11, color: FoodietColors.warm500),
                        const SizedBox(width: 2),
                        Text(
                          '${entry.sharedWithCount}명',
                          style: FoodietText.caption.copyWith(
                            color: FoodietColors.warm500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (entry.title?.trim().isNotEmpty ?? false)
                        ? entry.title!
                        : '식사 기록',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoodietText.body.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '$kcal kcal',
                        style: FoodietText.bodySm.copyWith(
                          color: FoodietColors.coral500,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      if (carb != null || protein != null || fat != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _macroLine(carb, protein, fat),
                          style: FoodietText.caption.copyWith(
                            color: FoodietColors.warm500,
                            fontSize: 11,
                          ),
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
    );
  }

  String _macroLine(double? c, double? p, double? f) {
    final parts = <String>[];
    if (c != null) parts.add('탄 ${c.toStringAsFixed(0)}');
    if (p != null) parts.add('단 ${p.toStringAsFixed(0)}');
    if (f != null) parts.add('지 ${f.toStringAsFixed(0)}');
    return parts.join('·');
  }

  Widget _thumbFallback() => Container(
        color: FoodietColors.cream100,
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 20)),
      );

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
        return '기타';
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

// ─── empty hint ─────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          const Text('🥗', style: TextStyle(fontSize: 28)),
          const SizedBox(width: FoodietShape.sp12),
          Expanded(
            child: Text(
              '오늘 기록이 아직 없어요.\n첫 사진을 찍어 시작해보세요.',
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── footer ─────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'made with ',
          style: FoodietText.caption.copyWith(
            color: FoodietColors.warm500,
            fontSize: 11,
          ),
        ),
        const Text('🍓', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 3),
        Text(
          'foodiet',
          style: FoodietText.caption.copyWith(
            color: FoodietColors.coral500,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
