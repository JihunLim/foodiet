/// 인사이트 — 체중 탭 + 영양 탭.
///
/// 기획안 §4.7 / §4.4.
///
/// - **체중**: 체중 추적 · 예측 차트 · 목표 도달 verdict — 이 앱의 핵심 성과
///   화면. `weight_insight_page.dart` 에서 렌더.
/// - **영양**: 주간/월간 섭취 · 목표 달성률 · 끼니 분포 · 자주 먹은 음식 ·
///   푸디 한줄평. 기존 content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl 이 TextDirection 을 재정의해 Flutter 의 TextDirection.ltr 을 가리므로 hide.
import 'package:intl/intl.dart' hide TextDirection;

import '../../providers/entries_provider.dart';
import '../../providers/insight_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/native_ad_card.dart';
import '../../widgets/science_citations_sheet.dart';
import 'weight_insight_page.dart';

class InsightPage extends ConsumerWidget {
  const InsightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: FoodietColors.cream00,
        appBar: AppBar(
          backgroundColor: FoodietColors.cream00,
          elevation: 0,
          title: Text('인사이트',
              style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Container(
              margin: const EdgeInsets.fromLTRB(
                  FoodietShape.sp20, 0, FoodietShape.sp20, FoodietShape.sp8),
              decoration: BoxDecoration(
                color: FoodietColors.cream50,
                borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                border: Border.all(color: FoodietColors.cream100),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: FoodietColors.coral500,
                  borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(3),
                labelColor: Colors.white,
                unselectedLabelColor: FoodietColors.warm700,
                labelStyle: FoodietText.bodySm
                    .copyWith(fontWeight: FontWeight.w700),
                unselectedLabelStyle: FoodietText.bodySm
                    .copyWith(fontWeight: FontWeight.w700),
                dividerColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [
                  Tab(text: '체중'),
                  Tab(text: '영양'),
                ],
              ),
            ),
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            physics: ClampingScrollPhysics(),
            children: [
              WeightInsightPage(),
              _NutritionTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NutritionTab extends ConsumerWidget {
  const _NutritionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(insightSummaryProvider);
    final window = ref.watch(insightWindowProvider);

    return RefreshIndicator(
      color: FoodietColors.coral500,
      onRefresh: () async => ref.invalidate(recentEntriesProvider),
      child: summaryAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: FoodietColors.coral500),
        ),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(FoodietShape.sp20),
                child: Text('인사이트를 불러오지 못했어: $e',
                    textAlign: TextAlign.center,
                    style: FoodietText.body
                        .copyWith(color: FoodietColors.warm700)),
              ),
            ),
          ],
        ),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(FoodietShape.sp20, 0,
              FoodietShape.sp20, FoodietShape.sp40),
          children: [
            _WindowToggle(current: window),
            const SizedBox(height: FoodietShape.sp16),
            if (s.recordDays == 0)
              const _EmptyInsight()
            else ...[
              _HeroCard(summary: s),
              const SizedBox(height: FoodietShape.sp12),
              _CoachCard(summary: s),
              // AdMob 네이티브 광고 #1 (인사이트 상단).
              const SizedBox(height: FoodietShape.sp12),
              const NativeAdCard(key: ValueKey('insight-ad-top')),
              const SizedBox(height: FoodietShape.sp12),
              _CalorieChartCard(summary: s),
              const SizedBox(height: FoodietShape.sp12),
              _GoalBreakdownCard(summary: s),
              const SizedBox(height: FoodietShape.sp12),
              _MealSlotCard(summary: s),
              const SizedBox(height: FoodietShape.sp12),
              _MacroCard(summary: s),
              if (s.topFoods.isNotEmpty) ...[
                // AdMob 네이티브 광고 #2 (자주 먹은 음식 카드 위).
                const SizedBox(height: FoodietShape.sp12),
                const NativeAdCard(key: ValueKey('insight-ad-bottom')),
                const SizedBox(height: FoodietShape.sp12),
                _TopFoodsCard(summary: s),
              ],
              // 산출 근거 / 의료 면책 — App Store guideline 1.4.1 대응.
              const SizedBox(height: FoodietShape.sp24),
              const ScienceCitationsLink(),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 윈도우 토글 ──────────────────────────────────────────────────────────
//
// 상단의 [체중/영양] 탭바와 시각적으로 겹치지 않도록, 우측에 소형
// iOS 풍 segmented control 로 배치. 라벨도 "지난 7일" → "7일" 로 축약.

class _WindowToggle extends ConsumerWidget {
  const _WindowToggle({required this.current});
  final InsightWindow current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget seg(InsightWindow w, String text) {
      final active = w == current;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => ref.read(insightWindowProvider.notifier).state = w,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: active ? FoodietColors.cream00 : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color:
                          FoodietColors.warm900.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            text,
            style: FoodietText.caption.copyWith(
              color: active
                  ? FoodietColors.coral500
                  : FoodietColors.warm500,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: FoodietShape.sp4),
      child: Row(
        children: [
          Text('기간',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: FoodietColors.cream100,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                seg(InsightWindow.week, '7일'),
                seg(InsightWindow.month, '30일'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 빈 상태 ──────────────────────────────────────────────────────────────

class _EmptyInsight extends StatelessWidget {
  const _EmptyInsight();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp24),
      margin: const EdgeInsets.only(top: FoodietShape.sp40),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        children: [
          const Text('📊', style: TextStyle(fontSize: 44)),
          const SizedBox(height: FoodietShape.sp12),
          Text('아직 인사이트를 만들기엔 기록이 부족해',
              style:
                  FoodietText.title.copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: 4),
          Text('며칠만 더 기록하면 추세 · 달성률 · 푸디 리뷰가 여기 채워져.',
              textAlign: TextAlign.center,
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm500)),
        ],
      ),
    );
  }
}

// ─── 요약 카드 (평균 섭취 · 달성률 · 스트릭) ──────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary});
  final InsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final rate = (summary.onGoalRate * 100).round();
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FoodietColors.coral100, FoodietColors.cream50],
        ),
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary.window.label,
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${summary.avgKcal}',
                  style: FoodietText.numberLarge
                      .copyWith(color: FoodietColors.coral500)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('kcal / 기록한 날 평균',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${summary.windowDays}일 기간 평균 ${summary.avgKcalAllDays} kcal · '
              '목표 ${summary.targetKcal} kcal ±10%',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: FoodietShape.sp16),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: '달성률',
                  value: '$rate%',
                  sub: '${summary.onGoalDays}/${summary.recordDays}일',
                  color: FoodietColors.leaf500,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _HeroStat(
                  label: '현재 연속',
                  value: '${summary.currentStreak}일',
                  sub: '최장 ${summary.bestStreak}일',
                  color: FoodietColors.coral500,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _HeroStat(
                  // 윈도우 총일수 대비 기록 비율 — 7일/30일 전환 시 즉각 변화.
                  label: '기록한 날',
                  value: '${summary.recordDays}/${summary.windowDays}일',
                  sub: '총 ${summary.totalDoneEntries}장',
                  color: FoodietColors.warm700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });
  final String label;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: FoodietColors.cream00,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: FoodietText.title.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          Text(sub,
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── 푸디의 한줄평 ────────────────────────────────────────────────────────

class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.summary});
  final InsightSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.coral50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.coral100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🍓', style: TextStyle(fontSize: 24)),
          const SizedBox(width: FoodietShape.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('푸디의 리뷰',
                    style: FoodietText.caption.copyWith(
                        color: FoodietColors.coral500,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(summary.coachSummary,
                    style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 일별 칼로리 바 차트 ──────────────────────────────────────────────────

class _CalorieChartCard extends StatelessWidget {
  const _CalorieChartCard({required this.summary});
  final InsightSummary summary;

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
          _cardHeader('일별 칼로리 섭취',
              '${summary.windowDays}일 · 막대 색이 밴드 안이면 달성'),
          const SizedBox(height: FoodietShape.sp12),
          SizedBox(
            height: 160,
            child: LayoutBuilder(
              builder: (ctx, c) => CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _CalorieBarPainter(
                  days: summary.days,
                  target: summary.targetKcal,
                ),
              ),
            ),
          ),
          const SizedBox(height: FoodietShape.sp8),
          const _Legend(
            items: [
              _LegendItem(color: FoodietColors.leaf500, label: '목표 ±10%'),
              _LegendItem(color: FoodietColors.warning, label: '초과'),
              _LegendItem(color: FoodietColors.info, label: '부족'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalorieBarPainter extends CustomPainter {
  _CalorieBarPainter({required this.days, required this.target});
  final List<DayBucket> days;
  final int target;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final lower = target * 0.9;
    final upper = target * 1.1;

    // y축 최대 — max(days) 와 upper 의 1.15 배 중 큰 값.
    final maxKcal = days
            .map((d) => d.consumedKcal)
            .fold<int>(0, (a, b) => a > b ? a : b)
            .toDouble();
    final yMax = (maxKcal > upper ? maxKcal : upper) * 1.15;

    // 막대 폭 / 간격.
    final n = days.length;
    final slot = size.width / n;
    final barW = slot * (n > 14 ? 0.6 : 0.5);

    // 하단 라벨 영역 20px 확보.
    final chartH = size.height - 22;

    // 목표 밴드 (옅은 초록 영역).
    final yUpper = chartH - (upper / yMax) * chartH;
    final yLower = chartH - (lower / yMax) * chartH;
    final bandPaint = Paint()
      ..color = FoodietColors.leaf500.withValues(alpha: 0.10);
    canvas.drawRect(
        Rect.fromLTRB(0, yUpper, size.width, yLower), bandPaint);

    // 목표 라인.
    final targetY = chartH - (target / yMax) * chartH;
    final linePaint = Paint()
      ..color = FoodietColors.leaf500.withValues(alpha: 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashW = 4.0;
    for (double x = 0; x < size.width; x += dashW * 2) {
      canvas.drawLine(
          Offset(x, targetY), Offset(x + dashW, targetY), linePaint);
    }

    // 막대.
    for (int i = 0; i < n; i++) {
      final d = days[i];
      if (!d.hasRecord) continue;
      final h = (d.consumedKcal / yMax) * chartH;
      final cx = slot * i + slot / 2;
      final rect = Rect.fromLTWH(
          cx - barW / 2, chartH - h, barW, h.clamp(2.0, chartH));
      final Color color;
      if (d.consumedKcal > upper) {
        color = FoodietColors.warning;
      } else if (d.consumedKcal < lower) {
        color = FoodietColors.info;
      } else {
        color = FoodietColors.leaf500;
      }
      final paint = Paint()..color = color;
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
    }

    // x축 라벨 — 7일은 매일, 30일은 7일 간격.
    final step = n <= 10 ? 1 : (n / 5).floor();
    final labelStyle = FoodietText.caption.copyWith(
      color: FoodietColors.warm500,
      fontSize: 10,
    );
    for (int i = 0; i < n; i += step) {
      final d = days[i];
      final text = DateFormat('M/d').format(d.date);
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = slot * i + slot / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, chartH + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _CalorieBarPainter old) {
    if (old.target != target) return true;
    if (old.days.length != days.length) return true;
    for (int i = 0; i < days.length; i++) {
      if (old.days[i].consumedKcal != days[i].consumedKcal ||
          old.days[i].date != days[i].date) {
        return true;
      }
    }
    return false;
  }
}

// ─── 목표 달성 세부 ───────────────────────────────────────────────────────

class _GoalBreakdownCard extends StatelessWidget {
  const _GoalBreakdownCard({required this.summary});
  final InsightSummary summary;

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
          _cardHeader('목표 달성 분석',
              '${summary.windowDays}일 중 ${summary.recordDays}일 기록 · '
              '목표 ${summary.targetKcal} kcal 기준'),
          const SizedBox(height: FoodietShape.sp12),
          _GoalBar(summary: summary),
          const SizedBox(height: FoodietShape.sp12),
          Row(
            children: [
              Expanded(
                child: _GoalCell(
                  label: '성공',
                  count: summary.onGoalDays,
                  total: summary.recordDays,
                  color: FoodietColors.leaf500,
                  emoji: '✅',
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _GoalCell(
                  label: '초과',
                  count: summary.overDays,
                  total: summary.recordDays,
                  color: FoodietColors.warning,
                  emoji: '⚠️',
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _GoalCell(
                  label: '부족',
                  count: summary.underDays,
                  total: summary.recordDays,
                  color: FoodietColors.info,
                  emoji: '🍚',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.summary});
  final InsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final total = summary.recordDays == 0 ? 1 : summary.recordDays;
    final onFlex = summary.onGoalDays;
    final overFlex = summary.overDays;
    final underFlex = summary.underDays;
    return ClipRRect(
      borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (onFlex > 0)
              Expanded(
                  flex: onFlex,
                  child: Container(color: FoodietColors.leaf500)),
            if (overFlex > 0)
              Expanded(
                  flex: overFlex,
                  child: Container(color: FoodietColors.warning)),
            if (underFlex > 0)
              Expanded(
                  flex: underFlex,
                  child: Container(color: FoodietColors.info)),
            if (onFlex + overFlex + underFlex == 0)
              Expanded(
                  flex: total,
                  child: Container(color: FoodietColors.cream100)),
          ],
        ),
      ),
    );
  }
}

class _GoalCell extends StatelessWidget {
  const _GoalCell({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    required this.emoji,
  });
  final String label;
  final int count;
  final int total;
  final Color color;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : ((count / total) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text(label,
                  style: FoodietText.caption.copyWith(
                      color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$count일',
              style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          Text('$pct%',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
        ],
      ),
    );
  }
}

// ─── 끼니별 분포 ──────────────────────────────────────────────────────────

class _MealSlotCard extends StatelessWidget {
  const _MealSlotCard({required this.summary});
  final InsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final slots = summary.mealSlots;
    final totalKcal = slots.fold<int>(0, (a, b) => a + b.kcalTotal);
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
          _cardHeader('끼니별 비중',
              '${summary.windowDays}일 · 어느 끼니에 칼로리가 몰려 있는지'),
          const SizedBox(height: FoodietShape.sp12),
          if (totalKcal == 0)
            Text('기록이 쌓이면 끼니별 분포를 보여줄게.',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500))
          else ...[
            _MealSlotBar(slots: slots, totalKcal: totalKcal),
            const SizedBox(height: FoodietShape.sp12),
            ...slots.where((s) => s.count > 0).map((s) => _MealSlotRow(
                  slot: s,
                  totalKcal: totalKcal,
                )),
          ],
        ],
      ),
    );
  }
}

class _MealSlotBar extends StatelessWidget {
  const _MealSlotBar({required this.slots, required this.totalKcal});
  final List<MealSlotStat> slots;
  final int totalKcal;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final s in slots)
              if (s.kcalTotal > 0)
                Expanded(
                  flex: s.kcalTotal,
                  child: Container(color: _mealColor(s.slot)),
                ),
          ],
        ),
      ),
    );
  }
}

class _MealSlotRow extends StatelessWidget {
  const _MealSlotRow({required this.slot, required this.totalKcal});
  final MealSlotStat slot;
  final int totalKcal;

  @override
  Widget build(BuildContext context) {
    final pct = totalKcal == 0 ? 0 : ((slot.kcalTotal / totalKcal) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _mealColor(slot.slot),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_mealLabel(slot.slot),
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm700)),
          ),
          Text('${slot.count}끼 · ${slot.kcalTotal} kcal',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text('$pct%',
                textAlign: TextAlign.right,
                style: FoodietText.bodySm.copyWith(
                    color: FoodietColors.warm900,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

Color _mealColor(String slot) {
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

String _mealLabel(String slot) {
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

// ─── 평균 매크로 ──────────────────────────────────────────────────────────

class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.summary});
  final InsightSummary summary;

  @override
  Widget build(BuildContext context) {
    String fmt(double g) =>
        g < 10 ? g.toStringAsFixed(1) : g.toStringAsFixed(0);
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
          _cardHeader('평균 탄·단·지',
              '${summary.windowDays}일 중 기록된 날의 하루 평균 섭취량'),
          const SizedBox(height: FoodietShape.sp12),
          Row(
            children: [
              Expanded(
                child: _MacroBig(
                  label: '탄수',
                  value: '${fmt(summary.avgCarbG)}g',
                  color: FoodietColors.mealBreakfast,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _MacroBig(
                  label: '단백',
                  value: '${fmt(summary.avgProteinG)}g',
                  color: FoodietColors.leaf500,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _MacroBig(
                  label: '지방',
                  value: '${fmt(summary.avgFatG)}g',
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

class _MacroBig extends StatelessWidget {
  const _MacroBig({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: FoodietText.caption
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value,
              style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── Top 자주 먹은 음식 ────────────────────────────────────────────────

class _TopFoodsCard extends StatelessWidget {
  const _TopFoodsCard({required this.summary});
  final InsightSummary summary;

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
          _cardHeader('자주 먹은 음식',
              '지난 ${summary.windowDays}일 중 가장 많이 등장한 상위 5개'),
          const SizedBox(height: FoodietShape.sp8),
          ...List.generate(summary.topFoods.length, (i) {
            final f = summary.topFoods[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? FoodietColors.coral500
                          : FoodietColors.cream100,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: FoodietText.caption.copyWith(
                        color: i == 0 ? Colors.white : FoodietColors.warm700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: FoodietShape.sp12),
                  Expanded(
                    child: Text(f.name,
                        style: FoodietText.body.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text('${f.count}회',
                      style: FoodietText.bodySm
                          .copyWith(color: FoodietColors.warm500)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── 공용 헬퍼 ────────────────────────────────────────────────────────────

Widget _cardHeader(String title, String sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style:
                FoodietText.title.copyWith(color: FoodietColors.warm900)),
        const SizedBox(height: 2),
        Text(sub,
            style: FoodietText.caption
                .copyWith(color: FoodietColors.warm500)),
      ],
    );

class _LegendItem {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});
  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: items
          .map((it) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: it.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(it.label,
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                ],
              ))
          .toList(),
    );
  }
}
