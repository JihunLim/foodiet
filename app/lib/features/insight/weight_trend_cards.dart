/// 인사이트 > 체중 탭의 추세 기반 안내 카드.
///
///   - [WeightTrendCards]: 스파이크 / 정체기 / 목표 재계산 제안 중 해당하는 것만.
///   - [MaintainModeAction]: 목표 도달 카드 안 "유지 모드로 전환" 버튼(이미 유지면 배지).
///   - [showTargetRecalcSheet]: 새 목표 미리보기 + 저장(profiles UPDATE + app_events).
///
/// 문구 원칙: 반말, 죄책감·평가 금지, 감량 보장 금지, 하한(여 1200/남 1500) 아래 권장 금지.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/supabase_provider.dart';
import '../../services/app_events.dart';
import '../../services/kcal_calc.dart';
import '../../services/weight_trend.dart';
import '../../theme/foodiet_tokens.dart';

/// 해당하는 추세 카드만 세로로 쌓는다. 없으면 빈 위젯.
class WeightTrendCards extends StatelessWidget {
  const WeightTrendCards({
    super.key,
    required this.series,
    required this.profile,
    this.today,
  });

  final List<TrendPoint> series;
  final AppProfile? profile;

  /// 테스트 주입용. 기본은 오늘.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (series.isEmpty || p == null) return const SizedBox.shrink();
    final now = today ?? DateTime.now();
    final latestTrend = series.last.trendKg;

    // 스파이크 안내는 "방금 찍은 값" 에만 — 마지막 기록이 오늘/어제이고 직전 기록과
    // 3일 이내일 때. 오래된 급등이나 몇 주 간격 비교에 "수분" 안내를 붙이지 않는다.
    final today0 = DateTime(now.year, now.month, now.day);
    final fresh = series.length >= 2 &&
        !series.last.date.isBefore(DateTime(now.year, now.month, now.day - 1)) &&
        series.last.date.difference(series[series.length - 2].date).inDays <= 3;
    final spike = fresh && detectSpike(series);

    final mode = effectiveGoalMode(p.goalMode,
        goalKg: p.goalWeightKg, currentKg: latestTrend);
    final goal = p.goalWeightKg;
    final stillAboveGoal = goal == null || latestTrend - goal >= 0.3;
    final canRecalc =
        recalcTarget(p, weightKg: latestTrend, mode: p.goalMode) != null;
    final plateau =
        mode == 'lose' && stillAboveGoal && detectPlateau(series, now);

    final basis = p.targetWeightBasisKg ?? p.weightKg;
    final recalc = !plateau && canRecalc && needsRecalc(basis, latestTrend);

    final cards = <Widget>[
      if (spike)
        _SpikeCard(
          latest: series.last,
          baseline: series[series.length - 2],
          isToday: !series.last.date.isBefore(today0),
        ),
      if (plateau)
        _PlateauCard(
          onRecalc: canRecalc
              ? () => showTargetRecalcSheet(context,
                  profile: p, weightKg: latestTrend, mode: p.goalMode)
              : null,
        ),
      if (recalc)
        _RecalcSuggestCard(
          basisKg: basis!,
          trendKg: latestTrend,
          onRecalc: () => showTargetRecalcSheet(context,
              profile: p, weightKg: latestTrend, mode: p.goalMode),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    // 카드가 있을 때만 아래 간격까지 포함 — 부모 리스트에 빈 간격을 남기지 않게.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in cards) ...[
          c,
          const SizedBox(height: FoodietShape.sp12),
        ],
      ],
    );
  }
}

// ─── 스파이크 ─────────────────────────────────────────────────────────────

class _SpikeCard extends StatelessWidget {
  const _SpikeCard({
    required this.latest,
    required this.baseline,
    required this.isToday,
  });
  final TrendPoint latest;
  final TrendPoint baseline;

  /// 마지막 기록이 오늘이면 "오늘", 어제면 "어제".
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final jump = latest.kg - baseline.trendKg;
    return _TrendCardShell(
      emoji: '💧',
      tint: FoodietColors.info,
      title: '${isToday ? '오늘' : '어제'} 숫자가 훅 올랐지?',
      body: '추세보다 ${jump.toStringAsFixed(1)}kg 높게 찍혔어. '
          '하루 사이 이 정도 오르는 건 대부분 수분·염분 영향일 가능성이 커. '
          '하루 값보다 차트의 추세선 기준으로 봐줘.',
    );
  }
}

// ─── 정체기 ───────────────────────────────────────────────────────────────

class _PlateauCard extends StatefulWidget {
  const _PlateauCard({required this.onRecalc});
  final VoidCallback? onRecalc;

  @override
  State<_PlateauCard> createState() => _PlateauCardState();
}

class _PlateauCardState extends State<_PlateauCard> {
  @override
  void initState() {
    super.initState();
    // 마운트당 1회만 기록 (build 마다 찍히지 않게).
    AppEvents.log('plateau_card_shown');
  }

  @override
  Widget build(BuildContext context) {
    return _TrendCardShell(
      emoji: '🧭',
      tint: FoodietColors.warning,
      title: '2주째 추세가 거의 그대로야',
      body: '정체기는 감량 중에 흔하게 오는 구간이야. 같이 한번 점검해보자.',
      checklist: const [
        '기록 없이 지나간 끼니나 간식이 있었는지',
        '주말 섭취가 평일과 많이 달랐는지',
        '음료·소스처럼 놓치기 쉬운 칼로리',
      ],
      ctaLabel: widget.onRecalc == null ? null : '목표 다시 계산',
      onCta: widget.onRecalc,
    );
  }
}

// ─── 재계산 제안 ──────────────────────────────────────────────────────────

class _RecalcSuggestCard extends StatelessWidget {
  const _RecalcSuggestCard({
    required this.basisKg,
    required this.trendKg,
    required this.onRecalc,
  });
  final double basisKg;
  final double trendKg;
  final VoidCallback onRecalc;

  @override
  Widget build(BuildContext context) {
    final diff = (trendKg - basisKg).abs();
    return _TrendCardShell(
      emoji: '🔄',
      tint: FoodietColors.coral500,
      title: '목표 칼로리를 다시 맞춰볼까?',
      body: '지금 목표는 ${basisKg.toStringAsFixed(1)}kg 기준으로 계산됐는데, '
          '추세 체중이 ${trendKg.toStringAsFixed(1)}kg 이라 '
          '${diff.toStringAsFixed(1)}kg 차이가 나. 지금 몸에 맞게 다시 계산해보자.',
      ctaLabel: '목표 다시 계산',
      onCta: onRecalc,
    );
  }
}

// ─── 목표 도달 → 유지 모드 ─────────────────────────────────────────────────

/// 목표 도달 카드 안에 붙는 액션. 이미 유지 모드면 작은 배지만.
class MaintainModeAction extends StatelessWidget {
  const MaintainModeAction({
    super.key,
    required this.profile,
    required this.weightKg,
  });

  final AppProfile? profile;

  /// 유지 칼로리 계산에 쓸 체중 (최신 추세 체중 권장).
  final double weightKg;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const SizedBox.shrink();
    if (p.isMaintainMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: FoodietColors.leaf500.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
        ),
        child: Text('유지 모드 중 · 목표 ${p.dailyKcalTarget ?? "—"} kcal',
            style: FoodietText.caption.copyWith(
                color: FoodietColors.leaf700, fontWeight: FontWeight.w700)),
      );
    }
    if (recalcTarget(p, weightKg: weightKg, mode: 'maintain') == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 40,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: FoodietColors.leaf500,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FoodietShape.radiusSm)),
        ),
        onPressed: () => showTargetRecalcSheet(context,
            profile: p, weightKg: weightKg, mode: 'maintain'),
        child: Text('유지 모드로 전환',
            style: FoodietText.bodySm
                .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ─── 재계산 시트 + 저장 ───────────────────────────────────────────────────

/// 새 목표 미리보기 → "이 목표로 바꾸기" 시 profiles 저장.
Future<void> showTargetRecalcSheet(
  BuildContext context, {
  required AppProfile profile,
  required double weightKg,
  required String mode,
}) async {
  final update = recalcTarget(profile, weightKg: weightKg, mode: mode);
  if (update == null) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: FoodietColors.cream00,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusXl)),
    ),
    builder: (_) => _RecalcSheet(profile: profile, update: update),
  );
}

/// profiles 에 새 목표 저장 + 이벤트 기록 + profileProvider 갱신.
Future<void> saveTargetUpdate(WidgetRef ref, TargetUpdate u) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final client = ref.read(supabaseClientProvider);
  // await 동안 시트가 닫히면(바깥 탭·드래그) ref 를 더 못 쓴다 — 컨테이너를 미리 잡아
  // DB 는 바뀌었는데 profileProvider 만 옛 값으로 남는 일을 막는다.
  final container = ProviderScope.containerOf(ref.context, listen: false);
  await client
      .from('profiles')
      .update({
        'daily_kcal_target': u.dailyKcal,
        'goal_mode': u.mode,
        'target_weight_basis_kg': u.basisKg,
        'weight_kg': u.basisKg,
      })
      .eq('user_id', user.id)
      .timeout(const Duration(seconds: 15));
  AppEvents.log('target_recalc', {
    'mode': u.mode,
    'daily_kcal': u.dailyKcal,
  });
  container.invalidate(profileProvider);
}

class _RecalcSheet extends ConsumerStatefulWidget {
  const _RecalcSheet({required this.profile, required this.update});
  final AppProfile profile;
  final TargetUpdate update;

  @override
  ConsumerState<_RecalcSheet> createState() => _RecalcSheetState();
}

class _RecalcSheetState extends ConsumerState<_RecalcSheet> {
  bool _saving = false;
  String? _error;

  /// kcal·모드가 그대로인 경우 (하한에 걸린 프로필 등).
  bool get _isUnchanged {
    final p = widget.profile;
    final u = widget.update;
    return p.dailyKcalTarget != null &&
        p.dailyKcalTarget == u.dailyKcal &&
        p.goalMode == u.mode;
  }

  Future<void> _apply() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final u = widget.update;
    final unchanged = _isUnchanged;
    try {
      await saveTargetUpdate(ref, u);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(unchanged
              ? '기준 체중을 ${u.basisKg.toStringAsFixed(1)}kg 로 맞춰뒀어'
              : u.mode == 'maintain'
                  ? '유지 모드로 바꿨어 · 하루 ${u.dailyKcal} kcal'
                  : '새 목표 ${u.dailyKcal} kcal 로 맞췄어 ✨'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '저장하지 못했어. 잠시 뒤에 다시 해볼래?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final u = widget.update;
    final current = p.dailyKcalTarget;
    final unchanged = _isUnchanged;
    final floor = p.sex == Sex.male ? 1500 : 1200;
    final isMaintain = u.mode == 'maintain';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FoodietShape.sp20, FoodietShape.sp16,
            FoodietShape.sp20, FoodietShape.sp20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FoodietColors.warm200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: FoodietShape.sp16),
            Text(isMaintain ? '유지 모드로 바꿀까?' : '지금 체중으로 다시 계산했어',
                style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
            const SizedBox(height: 6),
            Text(
              isMaintain
                  ? '${u.basisKg.toStringAsFixed(1)}kg 을 지키는 칼로리야. '
                      '덜 먹는 목표 대신 지금 체중을 편하게 유지하는 쪽으로 맞춰줄게.'
                  : '추세 체중 ${u.basisKg.toStringAsFixed(1)}kg 기준이야.',
              style: FoodietText.bodySm
                  .copyWith(color: FoodietColors.warm500, height: 1.4),
            ),
            const SizedBox(height: FoodietShape.sp16),
            Row(
              children: [
                Expanded(
                  child: _KcalBox(
                    label: '지금 목표',
                    value: current?.toString() ?? '—',
                    color: FoodietColors.warm700,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: FoodietColors.warm500, size: 20),
                ),
                Expanded(
                  child: _KcalBox(
                    label: isMaintain ? '유지 목표' : '새 목표',
                    value: '${u.dailyKcal}',
                    color: FoodietColors.coral500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp12),
            Text(
              unchanged
                  ? '지금 체중으로 계산해도 목표가 그대로야. 지금 목표 그대로 가도 괜찮아.'
                  : '안전을 위해 하루 $floor kcal 아래로는 잡지 않아. '
                      '목표는 언제든 프로필에서 바꿀 수 있어.',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: FoodietShape.sp8),
              Text(_error!,
                  style:
                      FoodietText.bodySm.copyWith(color: FoodietColors.danger)),
            ],
            const SizedBox(height: FoodietShape.sp16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: FoodietColors.coral500,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd)),
                ),
                // 그대로여도 기준 체중(target_weight_basis_kg)은 저장해야
                // 재계산 제안 카드가 계속 남지 않는다.
                onPressed: _saving ? null : _apply,
                child: Text(
                  _saving
                      ? '저장 중…'
                      : (unchanged
                          ? '알겠어'
                          : (isMaintain ? '유지 모드로 바꾸기' : '이 목표로 바꾸기')),
                  style: FoodietText.title.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KcalBox extends StatelessWidget {
  const _KcalBox({
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: FoodietText.caption.copyWith(
                  color: color, fontWeight: FontWeight.w700, fontSize: 11)),
          const SizedBox(height: 2),
          Text('$value kcal',
              style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── 공용 카드 셸 ─────────────────────────────────────────────────────────

class _TrendCardShell extends StatelessWidget {
  const _TrendCardShell({
    required this.emoji,
    required this.tint,
    required this.title,
    required this.body,
    this.checklist = const [],
    this.ctaLabel,
    this.onCta,
  });

  final String emoji;
  final Color tint;
  final String title;
  final String body;
  final List<String> checklist;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.14), FoodietColors.cream50],
        ),
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
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
                        .copyWith(color: FoodietColors.warm700, height: 1.45)),
                if (checklist.isNotEmpty) ...[
                  const SizedBox(height: FoodietShape.sp8),
                  for (final c in checklist)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.check_box_outline_blank_rounded,
                                size: 14, color: FoodietColors.warm500),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(c,
                                style: FoodietText.bodySm
                                    .copyWith(color: FoodietColors.warm700)),
                          ),
                        ],
                      ),
                    ),
                ],
                if (ctaLabel != null && onCta != null) ...[
                  const SizedBox(height: FoodietShape.sp12),
                  SizedBox(
                    height: 38,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FoodietColors.coral600,
                        side: const BorderSide(color: FoodietColors.coral300),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(FoodietShape.radiusSm)),
                      ),
                      onPressed: onCta,
                      child: Text(ctaLabel!,
                          style: FoodietText.bodySm.copyWith(
                              color: FoodietColors.coral600,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
