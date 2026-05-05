/// 인사이트 > 체중 탭.
///
/// 이 앱의 핵심 목적(체중 감량/관리) 을 가장 직관적으로 보여주는 화면.
///
/// 섹션 구성:
///   1) Hero — 현재 체중 + 시작점 대비 변화 + 기록 버튼
///   2) 투영 차트 — 실측 점 + 예측 선 + 목표 라인 + 기한 마커
///   3) Verdict — 🎯 / ⚠️ / 🔴 + 구체적 조언
///   4) 메트릭 — TDEE · 평균 섭취 · 하루 적자/잉여
///   5) 목표 설정 미비/기한 지남 등 empty state 들
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../providers/profile_provider.dart';
import '../../providers/weight_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/science_citations_sheet.dart';
import 'weight_log_sheet.dart';

class WeightInsightPage extends ConsumerWidget {
  const WeightInsightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projAsync = ref.watch(weightProjectionProvider);
    final logsAsync = ref.watch(weightLogsProvider);

    return RefreshIndicator(
      color: FoodietColors.coral500,
      onRefresh: () async {
        ref.invalidate(weightLogsProvider);
        ref.invalidate(profileProvider);
      },
      child: projAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: FoodietColors.coral500),
        ),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(FoodietShape.sp20),
                child: Text('체중 데이터를 불러오지 못했어: $e',
                    textAlign: TextAlign.center,
                    style: FoodietText.body
                        .copyWith(color: FoodietColors.warm700)),
              ),
            ),
          ],
        ),
        data: (proj) => _WeightInsightBody(
          proj: proj,
          logs: logsAsync.valueOrNull ?? const <WeightLog>[],
        ),
      ),
    );
  }
}

class _WeightInsightBody extends ConsumerWidget {
  const _WeightInsightBody({required this.proj, required this.logs});
  final WeightProjection proj;
  final List<WeightLog> logs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 프로필이 모자라면 바로 안내로 끊는다.
    if (proj.verdict == WeightVerdict.missingProfile) {
      return _MissingProfileView();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp20, FoodietShape.sp12, FoodietShape.sp20,
          FoodietShape.sp40),
      children: [
        _HeroCard(proj: proj, logs: logs, onLog: () => _openLogSheet(context)),
        const SizedBox(height: FoodietShape.sp12),

        // 목표 체중 없을 때 — 차트(골라인 없이)까지 보여주고 CTA.
        if (proj.verdict == WeightVerdict.missingGoal) ...[
          if (logs.isNotEmpty) ...[
            _ProjectionChartCard(proj: proj, logs: logs),
            const SizedBox(height: FoodietShape.sp12),
          ],
          _SetupPromptCard(
            emoji: '🎯',
            title: '목표 체중을 설정해봐',
            body: '목표를 알려주면 이대로 가면 도달할 수 있는지 매일 계산해줄게.',
            cta: '프로필에서 설정',
            onTap: () => context.push('/profile/edit'),
          ),
        ] else if (proj.verdict == WeightVerdict.notEnoughIntake) ...[
          _ProjectionChartCard(proj: proj, logs: logs),
          const SizedBox(height: FoodietShape.sp12),
          _SetupPromptCard(
            emoji: '📸',
            title: '3일만 더 기록하면 예측이 시작돼',
            body:
                '지난 14일 중 ${proj.intakeSampleDays}일만 기록돼 있어서 추이를 뽑기 어려워.',
            cta: '오늘 식사 기록',
            onTap: () => context.go('/camera'),
          ),
        ] else if (proj.verdict == WeightVerdict.missingDeadline) ...[
          _ProjectionChartCard(proj: proj, logs: logs),
          const SizedBox(height: FoodietShape.sp12),
          _PaceCard(proj: proj),
          const SizedBox(height: FoodietShape.sp12),
          _SetupPromptCard(
            emoji: '📅',
            title: '목표 기한도 정해보자',
            body: '기한이 있으면 도달 확률과 "이대로 가면 언제 도달" 을 알려줄 수 있어.',
            cta: '기한 설정',
            onTap: () => context.push('/profile/edit'),
          ),
          const SizedBox(height: FoodietShape.sp12),
          _MetricsCard(proj: proj),
        ] else if (proj.verdict == WeightVerdict.pastDeadline) ...[
          _ProjectionChartCard(proj: proj, logs: logs),
          const SizedBox(height: FoodietShape.sp12),
          _SetupPromptCard(
            emoji: '⏰',
            title: '목표 기한이 지났어',
            body: '새 기한을 잡아서 다시 달려보자.',
            cta: '기한 다시 설정',
            onTap: () => context.push('/profile/edit'),
          ),
          const SizedBox(height: FoodietShape.sp12),
          _MetricsCard(proj: proj),
        ] else if (proj.verdict == WeightVerdict.atGoal) ...[
          _ProjectionChartCard(proj: proj, logs: logs),
          const SizedBox(height: FoodietShape.sp12),
          _AtGoalCard(proj: proj),
          const SizedBox(height: FoodietShape.sp12),
          _MetricsCard(proj: proj),
        ] else ...[
          // 메인 경로 — 예측 차트 + verdict + 메트릭.
          _ProjectionChartCard(proj: proj, logs: logs),
          const SizedBox(height: FoodietShape.sp12),
          _VerdictCard(proj: proj),
          const SizedBox(height: FoodietShape.sp12),
          _MetricsCard(proj: proj),
        ],

        if (logs.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp12),
          _RecentLogsCard(logs: logs, onTap: () => _openLogSheet(context)),
        ],

        const SizedBox(height: FoodietShape.sp16),
        _Disclaimer(),
        // 산출 근거 / 의료 면책 — App Store guideline 1.4.1 대응.
        const SizedBox(height: FoodietShape.sp8),
        const ScienceCitationsLink(),
      ],
    );
  }

  Future<void> _openLogSheet(BuildContext context) async {
    await WeightLogSheet.show(context, initialKg: proj.startWeightKg > 0
        ? proj.startWeightKg
        : null);
  }
}

// ─── 프로필 미비 — 전체 화면 ─────────────────────────────────────────────

class _MissingProfileView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        const SizedBox(height: 60),
        Container(
          padding: const EdgeInsets.all(FoodietShape.sp24),
          decoration: BoxDecoration(
            color: FoodietColors.cream50,
            borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Column(
            children: [
              const Text('⚖️', style: TextStyle(fontSize: 52)),
              const SizedBox(height: FoodietShape.sp12),
              Text('체중 변화를 예측하려면 프로필이 필요해',
                  textAlign: TextAlign.center,
                  style: FoodietText.title
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: 6),
              Text('키 · 생년월일 · 성별 · 활동량 · 현재 체중만 있으면 돼.',
                  textAlign: TextAlign.center,
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
              const SizedBox(height: FoodietShape.sp20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: FoodietColors.coral500),
                  onPressed: () => context.push('/profile/edit'),
                  child: Text('프로필 설정하기',
                      style: FoodietText.title
                          .copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Hero (현재 체중) ────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.proj,
    required this.logs,
    required this.onLog,
  });
  final WeightProjection proj;
  final List<WeightLog> logs;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final current = proj.startWeightKg;
    // 로그가 2개 이상일 때만 "시작점 대비 변화" 를 보여줌.
    // 단 하나뿐이면 시작점 = 현재라 delta 0 이 노이즈.
    final firstLog = logs.length >= 2 ? logs.last : null;
    final delta = firstLog == null ? null : current - firstLog.weightKg;

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
          Text('현재 체중',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(current.toStringAsFixed(1),
                  style: FoodietText.numberLarge
                      .copyWith(color: FoodietColors.coral500)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('kg',
                    style: FoodietText.title.copyWith(
                        color: FoodietColors.coral500,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (delta != null)
                _DeltaPill(delta: delta, goalKind: proj.kind),
            ],
          ),
          if (firstLog != null) ...[
            const SizedBox(height: 4),
            Text(
                '시작점 ${firstLog.weightKg.toStringAsFixed(1)} kg · '
                '${DateFormat('yyyy.M.d').format(firstLog.loggedAt)}',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ] else ...[
            const SizedBox(height: 4),
            Text('아직 기록이 없어. 첫 체중을 찍어보자.',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ],
          const SizedBox(height: FoodietShape.sp16),
          Row(
            children: [
              if (proj.goalWeightKg != null)
                Expanded(
                  child: _GoalPill(
                    goalKg: proj.goalWeightKg!,
                    deadline: proj.deadline,
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              const SizedBox(width: FoodietShape.sp8),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: FoodietColors.coral500,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            FoodietShape.radiusMd)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('기록',
                      style: FoodietText.bodySm.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  onPressed: onLog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.delta, required this.goalKind});
  final double delta;
  final WeightGoalKind goalKind;

  @override
  Widget build(BuildContext context) {
    // cut 이면 감량(음수)이 좋음, bulk 면 증량(양수)이 좋음.
    final good = (goalKind == WeightGoalKind.cut && delta < 0) ||
        (goalKind == WeightGoalKind.bulk && delta > 0);
    final color = good ? FoodietColors.leaf500 : FoodietColors.warm700;
    final sign = delta > 0 ? '+' : '';
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(delta < 0 ? Icons.south : Icons.north,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text('$sign${delta.toStringAsFixed(1)} kg',
              style: FoodietText.bodySm
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GoalPill extends StatelessWidget {
  const _GoalPill({required this.goalKg, required this.deadline});
  final double goalKg;
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final dday = deadline == null
        ? null
        : DateTime(deadline!.year, deadline!.month, deadline!.day)
            .difference(DateTime.now())
            .inDays;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: FoodietShape.sp12, vertical: 10),
      decoration: BoxDecoration(
        color: FoodietColors.cream00,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded,
              color: FoodietColors.leaf500, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('목표',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500)),
                Text('${goalKg.toStringAsFixed(1)} kg',
                    style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (dday != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: dday > 0
                    ? FoodietColors.coral500.withValues(alpha: 0.12)
                    : FoodietColors.warm500.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(FoodietShape.radiusXs),
              ),
              child: Text(
                dday > 0 ? 'D-$dday' : (dday == 0 ? 'D-DAY' : 'D+${-dday}'),
                style: FoodietText.caption.copyWith(
                  color: dday >= 0
                      ? FoodietColors.coral500
                      : FoodietColors.warm700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 투영 차트 ────────────────────────────────────────────────────────────

class _ProjectionChartCard extends StatelessWidget {
  const _ProjectionChartCard({required this.proj, required this.logs});
  final WeightProjection proj;
  final List<WeightLog> logs;

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
          _cardHeader('체중 추이 + 예측',
              '실측 점은 네가 찍은 값, 점선은 현재 섭취 추이로 본 예측'),
          const SizedBox(height: FoodietShape.sp12),
          SizedBox(
            height: 200,
            child: LayoutBuilder(
              builder: (ctx, c) => CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _ProjectionPainter(proj: proj, logs: logs),
              ),
            ),
          ),
          const SizedBox(height: FoodietShape.sp8),
          const _Legend(items: [
            _LegendItem(
                color: FoodietColors.coral500, label: '실측', dot: true),
            _LegendItem(color: FoodietColors.coral500, label: '예측', dashed: true),
            _LegendItem(
                color: FoodietColors.leaf500, label: '목표', dashed: true),
          ]),
        ],
      ),
    );
  }
}

class _ProjectionPainter extends CustomPainter {
  _ProjectionPainter({required this.proj, required this.logs});
  final WeightProjection proj;
  final List<WeightLog> logs;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ─── x 축 범위 ────────────────────────────────────────────────────
    // 가장 이른 기록 or today-14, 가장 늦은 기한 or today+30.
    DateTime xMin;
    if (logs.isNotEmpty) {
      final firstLog = logs.last.loggedAt;
      xMin = DateTime(firstLog.year, firstLog.month, firstLog.day);
    } else {
      xMin = today.subtract(const Duration(days: 14));
    }
    DateTime xMax;
    if (proj.deadline != null) {
      final dl = proj.deadline!;
      xMax = DateTime(dl.year, dl.month, dl.day);
    } else {
      xMax = today.add(const Duration(days: 30));
    }
    if (!xMax.isAfter(xMin)) xMax = xMin.add(const Duration(days: 30));
    final totalDays = xMax.difference(xMin).inDays.toDouble();
    if (totalDays <= 0) return;

    // ─── y 축 범위 ────────────────────────────────────────────────────
    final values = <double>[proj.startWeightKg];
    if (proj.goalWeightKg != null) values.add(proj.goalWeightKg!);
    if (proj.predictedAtDeadlineKg != null) {
      values.add(proj.predictedAtDeadlineKg!);
    }
    for (final l in logs) {
      values.add(l.weightKg);
    }
    double yMin = values.reduce((a, b) => a < b ? a : b);
    double yMax = values.reduce((a, b) => a > b ? a : b);
    final pad = (yMax - yMin).abs() < 2 ? 2.0 : (yMax - yMin) * 0.2;
    yMin -= pad;
    yMax += pad;
    final yRange = yMax - yMin;
    if (yRange <= 0) return;

    // ─── 좌표 변환 ────────────────────────────────────────────────────
    const leftPad = 34.0;
    const bottomPad = 22.0;
    const topPad = 8.0;
    final chartW = size.width - leftPad - 6;
    final chartH = size.height - bottomPad - topPad;

    double xFor(DateTime d) {
      final days = d.difference(xMin).inDays.toDouble();
      return leftPad + (days / totalDays) * chartW;
    }

    double yFor(double kg) {
      final t = (kg - yMin) / yRange;
      return topPad + (1 - t) * chartH;
    }

    // ─── y 축 grid + 라벨 ─────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = FoodietColors.cream100
      ..strokeWidth = 1;
    final labelStyle = FoodietText.caption.copyWith(
      color: FoodietColors.warm500,
      fontSize: 10,
    );
    const ticks = 4;
    for (int i = 0; i <= ticks; i++) {
      final kg = yMin + (yRange * i / ticks);
      final y = yFor(kg);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - 6, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: kg.toStringAsFixed(0), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // ─── 목표 라인 (가로 점선, leaf500) ───────────────────────────────
    if (proj.goalWeightKg != null) {
      final gy = yFor(proj.goalWeightKg!);
      final goalPaint = Paint()
        ..color = FoodietColors.leaf500
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      const dashW = 6.0, dashG = 4.0;
      for (double x = leftPad; x < size.width - 6; x += dashW + dashG) {
        canvas.drawLine(Offset(x, gy),
            Offset((x + dashW).clamp(leftPad, size.width - 6), gy),
            goalPaint);
      }
      // 목표 라벨.
      final tp = TextPainter(
        text: TextSpan(
          text: ' 목표 ${proj.goalWeightKg!.toStringAsFixed(1)}kg ',
          style: FoodietText.caption.copyWith(
            color: FoodietColors.leaf500,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            backgroundColor: FoodietColors.cream50,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(size.width - tp.width - 6, gy - tp.height - 2));
    }

    // ─── 오늘 세로 마커 ───────────────────────────────────────────────
    final todayX = xFor(today);
    if (todayX >= leftPad && todayX <= size.width - 6) {
      final todayPaint = Paint()
        ..color = FoodietColors.warm500.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(todayX, topPad), Offset(todayX, topPad + chartH), todayPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '오늘',
          style: FoodietText.caption
              .copyWith(color: FoodietColors.warm500, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(todayX - tp.width / 2, topPad + 2));
    }

    // ─── 기한 세로 마커 ───────────────────────────────────────────────
    if (proj.deadline != null) {
      final dlX = xFor(proj.deadline!);
      final dlPaint = Paint()
        ..color = FoodietColors.coral500.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(dlX, topPad), Offset(dlX, topPad + chartH), dlPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '기한',
          style: FoodietText.caption.copyWith(
              color: FoodietColors.coral500,
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dlX - tp.width / 2, topPad + 2));
    }

    // ─── 예측 곡선 (점선, 오늘 → 기한 or xMax) ────────────────────────
    // `predictedWeightAt` 가 더 이상 선형이 아니므로 다중 포인트로 샘플링
    // 해서 Path 로 이은 뒤 균일 대시로 그린다.
    final canDrawPrediction = proj.dailyChangeKg != null &&
        (proj.deadline == null || !proj.deadline!.isBefore(today));
    if (canDrawPrediction) {
      final fromDate = today;
      final toDate = proj.deadline ?? xMax;
      final totalDays = toDate.difference(fromDate).inDays;
      final pred = Paint()
        ..color = FoodietColors.coral500.withValues(alpha: 0.7)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (totalDays <= 1) {
        _drawDashedLine(
          canvas,
          Offset(xFor(fromDate), yFor(proj.predictedWeightAt(fromDate))),
          Offset(xFor(toDate), yFor(proj.predictedWeightAt(toDate))),
          pred,
          5,
          4,
        );
      } else {
        // 최대 60 샘플 — 곡선 디테일 충분, 계산 비용 저렴.
        final samples = math.min(totalDays, 60);
        final path = Path();
        for (int i = 0; i <= samples; i++) {
          final day = (totalDays * i / samples).round();
          final date = fromDate.add(Duration(days: day));
          final kg = proj.predictedWeightAt(date);
          final o = Offset(xFor(date), yFor(kg));
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        _drawDashedPath(canvas, path, pred, 5, 4);
      }
    }

    // ─── 실측 — 연결 선 + 점 ──────────────────────────────────────────
    if (logs.isNotEmpty) {
      final sorted = [...logs]
        ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      final linePaint = Paint()
        ..color = FoodietColors.coral500.withValues(alpha: 0.35)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < sorted.length; i++) {
        final l = sorted[i];
        final p = Offset(xFor(l.loggedAt), yFor(l.weightKg));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, linePaint);
      final dotFill = Paint()..color = FoodietColors.coral500;
      final dotRing = Paint()
        ..color = FoodietColors.cream00
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final l in sorted) {
        final p = Offset(xFor(l.loggedAt), yFor(l.weightKg));
        canvas.drawCircle(p, 4, dotFill);
        canvas.drawCircle(p, 4, dotRing);
      }
    }

    // ─── x 축 라벨 — 시작 · 중간 · 오늘 · 기한 ─────────────────────────
    void xLabel(DateTime d, String text, {bool bold = false}) {
      final x = xFor(d);
      if (x < leftPad - 4 || x > size.width + 4) return;
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: FoodietText.caption.copyWith(
            color: FoodietColors.warm500,
            fontSize: 10,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topPad + chartH + 4));
    }

    xLabel(xMin, DateFormat('M/d').format(xMin));
    if (proj.deadline != null) {
      xLabel(proj.deadline!, DateFormat('M/d').format(proj.deadline!),
          bold: true);
    } else {
      xLabel(xMax, DateFormat('M/d').format(xMax));
    }
  }

  void _drawDashedPath(
      Canvas c, Path path, Paint p, double dashW, double gap) {
    for (final metric in path.computeMetrics()) {
      double t = 0;
      while (t < metric.length) {
        final end = math.min(t + dashW, metric.length);
        c.drawPath(metric.extractPath(t, end), p);
        t += dashW + gap;
      }
    }
  }

  void _drawDashedLine(
      Canvas c, Offset a, Offset b, Paint p, double dashW, double gap) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = (dx * dx + dy * dy);
    if (dist == 0) return;
    final len = math.sqrt(dist);
    final stepX = dx / len;
    final stepY = dy / len;
    double traveled = 0;
    while (traveled < len) {
      final segEnd = (traveled + dashW).clamp(0, len).toDouble();
      c.drawLine(
        Offset(a.dx + stepX * traveled, a.dy + stepY * traveled),
        Offset(a.dx + stepX * segEnd, a.dy + stepY * segEnd),
        p,
      );
      traveled += dashW + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectionPainter old) {
    return old.proj != proj || old.logs.length != logs.length;
  }
}

// ─── Verdict 카드 (메인 경로) ────────────────────────────────────────────

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.proj});
  final WeightProjection proj;

  @override
  Widget build(BuildContext context) {
    final data = _verdictDisplay(proj);
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            data.color.withValues(alpha: 0.14),
            FoodietColors.cream50,
          ],
        ),
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: data.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(data.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title,
                        style: FoodietText.title
                            .copyWith(color: data.color)),
                    const SizedBox(height: 2),
                    if (proj.predictedAtDeadlineKg != null &&
                        proj.deadline != null)
                      Text(
                        '예상 ${proj.predictedAtDeadlineKg!.toStringAsFixed(1)} kg '
                        '· ${DateFormat('M/d').format(proj.deadline!)}',
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm700),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp12),
          Container(
            padding: const EdgeInsets.all(FoodietShape.sp12),
            decoration: BoxDecoration(
              color: FoodietColors.cream00,
              borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Text(
              data.advice,
              style: FoodietText.body.copyWith(
                color: FoodietColors.warm900,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictDisplay {
  const _VerdictDisplay({
    required this.emoji,
    required this.title,
    required this.color,
    required this.advice,
  });
  final String emoji;
  final String title;
  final Color color;
  final String advice;
}

_VerdictDisplay _verdictDisplay(WeightProjection p) {
  final isCut = p.kind == WeightGoalKind.cut;
  final gap = p.predictedGapKg;
  switch (p.verdict) {
    case WeightVerdict.onTrack:
      final gapStr = gap == null ? '' : (gap.abs()).toStringAsFixed(1);
      return _VerdictDisplay(
        emoji: '🎯',
        title: '이대로면 도달',
        color: FoodietColors.leaf500,
        advice: '현재 추이로 가면 기한 안에 목표에 닿을 수 있어. '
            '${gapStr.isNotEmpty ? "여유 ${gapStr}kg. " : ""}'
            '이 페이스 유지!',
      );
    case WeightVerdict.tight:
      return _VerdictDisplay(
        emoji: '⚠️',
        title: '아슬아슬',
        color: FoodietColors.warning,
        advice: _tightAdvice(p, isCut),
      );
    case WeightVerdict.offTrack:
      return _VerdictDisplay(
        emoji: '🔴',
        title: '현재 추이로는 어려워',
        color: FoodietColors.danger,
        advice: _offTrackAdvice(p, isCut),
      );
    default:
      return const _VerdictDisplay(
        emoji: '🍓',
        title: '정보가 모자라',
        color: FoodietColors.coral500,
        advice: '섭취 기록과 목표가 갖춰지면 여기에 예측이 나와.',
      );
  }
}

String _tightAdvice(WeightProjection p, bool isCut) {
  final extra = p.requiredExtraDailyDeficitKcal;
  final extraDays = p.extraDaysToReachGoal;
  final verb = isCut ? '줄이면' : '더 먹으면';
  final extraVerb = isCut ? '덜 먹거나' : '더 섭취하거나';
  final parts = <String>[];
  if (extra != null && extra > 0) {
    parts.add('하루 $extra kcal $verb 안정권.');
  }
  if (extraDays != null) {
    parts.add('기한을 $extraDays일 정도 늘리면 여유로움.');
  }
  if (parts.isEmpty) {
    return '거의 다 왔어. 한두 끼만 덜 조심하면 도달해.';
  }
  final suffix = parts.length > 1 ? '' : ' $extraVerb 기간을 늘려도 돼.';
  return '${parts.join(' 또는 ')}$suffix';
}

String _offTrackAdvice(WeightProjection p, bool isCut) {
  final extra = p.requiredExtraDailyDeficitKcal;
  final extraDays = p.extraDaysToReachGoal;
  final verb = isCut ? '줄여야' : '더 섭취해야';
  final parts = <String>[];
  if (extra != null && extra > 0) {
    parts.add('기한 안에 도달하려면 하루 $extra kcal 더 $verb 해.');
  }
  if (extraDays != null) {
    parts.add('또는 기한을 $extraDays일 늦추면 현재 추이로도 가능.');
  }
  if (parts.isEmpty) {
    return '현재 추이로는 기한 안에 어렵겠어. 섭취 조절 또는 기한 조정이 필요해.';
  }
  return parts.join(' ');
}

// ─── 기한 없는 경로의 페이스 카드 ───────────────────────────────────────

class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.proj});
  final WeightProjection proj;

  @override
  Widget build(BuildContext context) {
    final change = proj.dailyChangeKg ?? 0;
    final weekly = change * 7;
    final days = proj.daysToGoalAtCurrentPace;
    final isCut = proj.kind == WeightGoalKind.cut;
    final dir = change < 0 ? '감량' : (change > 0 ? '증량' : '유지');
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
          _cardHeader('현재 페이스', '최근 14일 평균 섭취 기준'),
          const SizedBox(height: FoodietShape.sp12),
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: '주간 $dir',
                  value: '${weekly.abs().toStringAsFixed(2)} kg',
                  color: (isCut && change < 0) || (!isCut && change > 0)
                      ? FoodietColors.leaf500
                      : FoodietColors.warning,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _MetricBox(
                  label: '목표까지',
                  value: days == null ? '—' : '$days일',
                  color: FoodietColors.coral500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AtGoalCard extends StatelessWidget {
  const _AtGoalCard({required this.proj});
  final WeightProjection proj;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FoodietColors.leaf500.withValues(alpha: 0.16),
            FoodietColors.cream50,
          ],
        ),
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(
            color: FoodietColors.leaf500.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 34)),
          const SizedBox(width: FoodietShape.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('목표에 도달했어',
                    style: FoodietText.title
                        .copyWith(color: FoodietColors.leaf500)),
                const SizedBox(height: 2),
                Text(
                    '이제는 유지 단계. TDEE ${proj.tdeeKcal ?? "—"} kcal 근처로 먹으면 지금 체중이 유지돼.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 메트릭 카드 ──────────────────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.proj});
  final WeightProjection proj;

  @override
  Widget build(BuildContext context) {
    final tdee = proj.tdeeKcal;
    final intake = proj.avgIntakeKcal;
    final balance = proj.dailyBalanceKcal;
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
          _cardHeader('지표', '평균 섭취 — TDEE = 하루 칼로리 균형'),
          const SizedBox(height: FoodietShape.sp12),
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: '소비 TDEE',
                  value: tdee == null ? '—' : '$tdee',
                  unit: 'kcal',
                  color: FoodietColors.warm700,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _MetricBox(
                  label: '평균 섭취',
                  value: intake == null ? '—' : '$intake',
                  unit: 'kcal',
                  color: FoodietColors.coral500,
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: _MetricBox(
                  label: balance != null && balance < 0 ? '적자' : '잉여',
                  value: balance == null
                      ? '—'
                      : balance.abs().round().toString(),
                  unit: 'kcal',
                  color: balance == null
                      ? FoodietColors.warm700
                      : (balance < 0
                          ? FoodietColors.leaf500
                          : FoodietColors.warning),
                ),
              ),
            ],
          ),
          if (proj.intakeSampleDays > 0) ...[
            const SizedBox(height: FoodietShape.sp8),
            Text('지난 14일 중 ${proj.intakeSampleDays}일 기록 기준',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ],
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.color,
    this.unit,
  });
  final String label;
  final String value;
  final String? unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: FoodietText.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    style: FoodietText.title.copyWith(
                        color: FoodietColors.warm900,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(unit!,
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500, fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 최근 로그 ────────────────────────────────────────────────────────────

class _RecentLogsCard extends StatelessWidget {
  const _RecentLogsCard({required this.logs, required this.onTap});
  final List<WeightLog> logs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final recent = logs.take(5).toList();
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
          Row(
            children: [
              Expanded(
                child: _cardHeader('최근 기록', '최대 5개'),
              ),
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.add,
                    size: 16, color: FoodietColors.coral500),
                label: Text('추가',
                    style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.coral500,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(recent.length, (i) {
            final l = recent[i];
            // logs 는 최신순. i+1 이 시간상 "이전" 기록.
            final prev = i + 1 < logs.length ? logs[i + 1] : null;
            final delta = prev == null ? null : l.weightKg - prev.weightKg;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                        DateFormat('M/d(EEE)', 'ko').format(l.loggedAt),
                        style: FoodietText.bodySm.copyWith(
                            color: FoodietColors.warm500)),
                  ),
                  Expanded(
                    child: Text('${l.weightKg.toStringAsFixed(1)} kg',
                        style: FoodietText.body.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (delta != null)
                    Text(
                        '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}kg',
                        style: FoodietText.caption.copyWith(
                          color: delta == 0
                              ? FoodietColors.warm500
                              : (delta < 0
                                  ? FoodietColors.leaf500
                                  : FoodietColors.warning),
                          fontWeight: FontWeight.w700,
                        )),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}


// ─── 안내/CTA 카드 ────────────────────────────────────────────────────────

class _SetupPromptCard extends StatelessWidget {
  const _SetupPromptCard({
    required this.emoji,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        color: FoodietColors.coral50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.coral100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: FoodietShape.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: FoodietText.title
                        .copyWith(color: FoodietColors.warm900)),
                const SizedBox(height: 4),
                Text(body,
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm700, height: 1.4)),
                const SizedBox(height: FoodietShape.sp12),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: FoodietColors.coral500,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              FoodietShape.radiusSm)),
                    ),
                    onPressed: onTap,
                    child: Text(cta,
                        style: FoodietText.bodySm.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 디스클레이머 ─────────────────────────────────────────────────────────

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FoodietShape.sp4),
      child: Text(
        '※ 예측은 7,700 kcal ≈ 1 kg 모델 기반 대략적 추정 (Mifflin-St Jeor + ACSM 활동계수). '
        '의학적 조언이 아니며 개인 상태에 따라 다를 수 있어. 수분 변동으로 일일 ±1 kg 정도는 정상.',
        style: FoodietText.caption
            .copyWith(color: FoodietColors.warm500, height: 1.4),
      ),
    );
  }
}

// ─── 공용 ─────────────────────────────────────────────────────────────────

Widget _cardHeader(String title, String sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: FoodietText.title.copyWith(color: FoodietColors.warm900)),
        const SizedBox(height: 2),
        Text(sub,
            style: FoodietText.caption
                .copyWith(color: FoodietColors.warm500)),
      ],
    );

class _LegendItem {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dot = false,
    this.dashed = false,
  });
  final Color color;
  final String label;
  final bool dot;
  final bool dashed;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});
  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: items
          .map((it) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (it.dot)
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: it.color, shape: BoxShape.circle),
                    )
                  else if (it.dashed)
                    CustomPaint(
                      size: const Size(14, 2),
                      painter: _LegendDashPainter(color: it.color),
                    )
                  else
                    Container(width: 12, height: 3, color: it.color),
                  const SizedBox(width: 6),
                  Text(it.label,
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500)),
                ],
              ))
          .toList(),
    );
  }
}

class _LegendDashPainter extends CustomPainter {
  _LegendDashPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + 4).clamp(0, size.width), size.height / 2), p);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _LegendDashPainter old) => old.color != color;
}

