/// 물 마시기 트래커 카드.
///
/// - 권장 컵 수는 사용자 프로필 기반 RPC(`recommended_water_cups`)로 산출.
/// - 컵 1개 = 150ml 가 기본.
/// - 달성 시 컵 아이콘이 채워지고 카드 전체에 강조 색 + scale pulse 애니메이션.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/water_provider.dart';
import '../../services/water_service.dart';
import '../../theme/foodiet_tokens.dart';

class WaterTrackerCard extends ConsumerStatefulWidget {
  const WaterTrackerCard({super.key});

  @override
  ConsumerState<WaterTrackerCard> createState() => _WaterTrackerCardState();
}

class _WaterTrackerCardState extends ConsumerState<WaterTrackerCard>
    with SingleTickerProviderStateMixin {
  WaterLog? _local;       // 낙관적 업데이트용
  bool _wasAchieved = false; // 달성 → 미달성 전환 감지로 애니메이션 트리거
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _maybeBounce(bool achievedNow) {
    if (achievedNow && !_wasAchieved) {
      _pulse
        ..reset()
        ..forward();
    }
    _wasAchieved = achievedNow;
  }

  Future<void> _setCups(int next) async {
    final log = _local;
    if (log == null) return;
    final clamped = next.clamp(0, log.targetCups + 4);
    setState(() {
      _local = WaterLog(
        logDate: log.logDate,
        cups: clamped,
        targetCups: log.targetCups,
        cupMl: log.cupMl,
      );
    });
    try {
      await ref.read(waterServiceProvider).setCups(
            cups: clamped,
            targetCups: log.targetCups,
            cupMl: log.cupMl,
          );
    } catch (_) {
      if (!mounted) return;
      ref.invalidate(todayWaterLogProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(todayWaterLogProvider);
    return async.when(
      loading: () => _shell(child: _loading()),
      error: (e, _) => _shell(child: _errorPlaceholder()),
      data: (server) {
        // 서버 값이 도착했고 로컬 캐시가 없으면 채움.
        _local ??= server;
        final shown = _local!;
        final achieved = shown.achieved;
        _maybeBounce(achieved);
        return _shell(
          achieved: achieved,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final t = _pulse.value;
              final scale = 1 + 0.06 * (t < 0.5 ? t * 2 : (1 - t) * 2);
              return Transform.scale(scale: scale, child: child);
            },
            child: _body(shown, achieved),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child, bool achieved = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        gradient: achieved
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFCCE9FF), Color(0xFFE6F4FF)],
              )
            : null,
        color: achieved ? null : FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(
          color: achieved
              ? const Color(0xFF4FB3FF)
              : FoodietColors.cream100,
        ),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: child,
    );
  }

  Widget _loading() => const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(color: FoodietColors.coral500),
        ),
      );

  Widget _errorPlaceholder() => Text('물 기록을 불러오지 못했어.',
      style: FoodietText.bodySm.copyWith(color: FoodietColors.warm500));

  Widget _body(WaterLog log, bool achieved) {
    final Color accent =
        achieved ? const Color(0xFF1F8FE3) : const Color(0xFF4FB3FF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              achieved ? Icons.local_drink : Icons.local_drink_outlined,
              color: accent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text('오늘 마신 물',
                style: FoodietText.title.copyWith(
                    color: FoodietColors.warm900,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(
              '${log.cups}/${log.targetCups}컵',
              style: FoodietText.title.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${log.currentMl}/${log.targetMl}ml · 컵 한 잔 ${log.cupMl}ml',
          style:
              FoodietText.caption.copyWith(color: FoodietColors.warm500),
        ),
        const SizedBox(height: FoodietShape.sp12),
        _cupGrid(log, accent, achieved),
        const SizedBox(height: FoodietShape.sp12),
        Row(
          children: [
            _stepBtn(
              icon: Icons.remove_rounded,
              label: '되돌리기',
              onTap: log.cups <= 0
                  ? null
                  : () => _setCups(log.cups - 1),
            ),
            const SizedBox(width: FoodietShape.sp8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _setCups(log.cups + 1),
                icon: const Icon(Icons.water_drop_rounded, size: 18),
                label: const Text('한 잔 마셨어'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                  ),
                  textStyle: FoodietText.body
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (achieved) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                  log.cups > log.targetCups
                      ? '오늘 목표 +${log.cups - log.targetCups}컵! 멋져.'
                      : '오늘 물 목표 달성! 굿잡 🥤',
                  style: FoodietText.bodySm.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cupGrid(WaterLog log, Color accent, bool achieved) {
    final cells = <Widget>[];
    final total = log.targetCups;
    for (int i = 0; i < total; i++) {
      final filled = i < log.cups;
      cells.add(_CupCell(
        index: i,
        filled: filled,
        accent: accent,
        achieved: achieved,
        onTap: () => _setCups(i + 1),
      ));
    }
    // 초과 컵 (target 보다 더 마신 분) 은 별표 표시로 끝에 추가.
    final extra = (log.cups - total).clamp(0, 4);
    for (int i = 0; i < extra; i++) {
      cells.add(_BonusCupCell(accent: accent));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: cells,
    );
  }

  Widget _stepBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        side: BorderSide(
          color: onTap == null
              ? FoodietColors.cream100
              : FoodietColors.warm500.withValues(alpha: 0.3),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: onTap == null
                  ? FoodietColors.warm500.withValues(alpha: 0.4)
                  : FoodietColors.warm700),
          const SizedBox(width: 4),
          Text(label,
              style: FoodietText.caption.copyWith(
                color: onTap == null
                    ? FoodietColors.warm500.withValues(alpha: 0.4)
                    : FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _CupCell extends StatelessWidget {
  const _CupCell({
    required this.index,
    required this.filled,
    required this.accent,
    required this.achieved,
    required this.onTap,
  });
  final int index;
  final bool filled;
  final Color accent;
  final bool achieved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 38,
        height: 44,
        decoration: BoxDecoration(
          color: filled
              ? (achieved ? accent : accent.withValues(alpha: 0.85))
              : FoodietColors.cream100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled
                ? accent
                : FoodietColors.warm500.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(
          filled ? Icons.local_drink : Icons.local_drink_outlined,
          color: filled ? Colors.white : FoodietColors.warm500,
          size: 20,
        ),
      ),
    );
  }
}

class _BonusCupCell extends StatelessWidget {
  const _BonusCupCell({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.6)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.star_rounded, color: Colors.white, size: 20),
    );
  }
}
