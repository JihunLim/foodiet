/// GLP-1 투약 관리 — `/medication`.
///
/// - 미설정/꺼짐: 소개 + "시작하기" (설정 시트).
/// - 켜짐: 다음 투약일 D-day 카드, "오늘 맞았어"(기록 시트), 기록 목록(스와이프 삭제),
///   "계획 수정", "투약 관리 끄기".
/// - 하단 고정 [kMedicationDisclaimer]. 예정일이 지나도 처리 방법은 안내하지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/medication_provider.dart';
import '../../services/medication_schedule.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/foodie_bubble.dart';
import '../../widgets/primary_button.dart';
import 'medication_log_sheet.dart';
import 'medication_setup_sheet.dart';
import 'medication_widgets.dart';

class MedicationPage extends ConsumerStatefulWidget {
  const MedicationPage({super.key});

  @override
  ConsumerState<MedicationPage> createState() => _MedicationPageState();
}

class _MedicationPageState extends ConsumerState<MedicationPage> {
  /// 스와이프로 지운 기록 — 목록이 다시 로드되기 전까지 화면에서 숨긴다
  /// (Dismissible 이 dismiss 된 뒤에도 트리에 남으면 에러).
  final Set<String> _removed = {};
  bool _busy = false;

  Future<void> _openSetup(MedicationPlan? initial) async {
    final saved = await showMedicationSetupSheet(context, initial: initial);
    if (saved && mounted) showMedSnack(context, '저장했어. 일정은 푸디가 같이 챙길게 💉');
  }

  Future<void> _openLog(MedicationPlan plan) async {
    final saved = await showMedicationLogSheet(context, plan: plan);
    if (saved && mounted) showMedSnack(context, '기록했어 ✓');
  }

  Future<void> _turnOff() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoodietColors.cream00,
        title: const Text('투약 관리를 끌까?'),
        content: const Text('알림이 멈추고 홈에서도 안 보여.\n지금까지의 기록은 그대로 남아.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('끄기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(medicationRepoProvider).setActive(false);
    } catch (_) {
      if (mounted) {
        showMedSnack(context, '변경하지 못했어. 잠시 후 다시 해볼래?', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDelete(MedicationLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoodietColors.cream00,
        title: const Text('이 기록을 지울까?'),
        content: Text(
            '${medDateTimeLabel(log.takenAt)} · ${formatDose(log.doseMg)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: FoodietColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await ref.read(medicationRepoProvider).deleteLog(log.id);
      return true;
    } catch (_) {
      if (mounted) {
        showMedSnack(context, '지우지 못했어. 잠시 후 다시 해볼래?', error: true);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(medicationPlanProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('GLP-1 투약 관리',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(FoodietShape.sp20, FoodietShape.sp8,
              FoodietShape.sp20, FoodietShape.sp12),
          child: MedDisclaimer(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: planAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: FoodietColors.coral500),
          ),
          // 조회 실패를 '미설정'으로 보이면 이미 쓰는 사람에게 시작하기가 뜬다 → 재시도.
          error: (_, __) => _LoadError(
            onRetry: () {
              ref.invalidate(medicationPlanProvider);
              ref.invalidate(medicationLogsProvider);
            },
          ),
          data: (plan) {
            if (plan == null || !plan.active) {
              return _Intro(
                existing: plan,
                onStart: () => _openSetup(plan),
              );
            }
            return _ActiveBody(
              plan: plan,
              removed: _removed,
              busy: _busy,
              onLog: () => _openLog(plan),
              onEdit: () => _openSetup(plan),
              onTurnOff: _turnOff,
              confirmDelete: _confirmDelete,
              onDismissed: (id) => setState(() => _removed.add(id)),
            );
          },
        ),
      ),
    );
  }
}

// ─── 불러오기 실패 ───────────────────────────────────────────────────

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FoodietShape.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('투약 정보를 불러오지 못했어.',
                textAlign: TextAlign.center,
                style: FoodietText.body.copyWith(color: FoodietColors.warm700)),
            const SizedBox(height: FoodietShape.sp12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('다시 불러오기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FoodietColors.warm700,
                side: const BorderSide(color: FoodietColors.cream100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 소개 (미설정/꺼짐) ─────────────────────────────────────────────────

class _Intro extends StatelessWidget {
  const _Intro({required this.existing, required this.onStart});
  final MedicationPlan? existing;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        const FoodieBubble(
          headline: '투약 일정, 같이 챙겨볼까?',
          why: '맞은 날을 기록하면 다음 투약일을 계산하고 그날 알려줄게.',
        ),
        const SizedBox(height: FoodietShape.sp20),
        const _Bullet(icon: '📅', text: '다음 투약일과 D-day를 한눈에'),
        const _Bullet(icon: '🔔', text: '예정일 정한 시각에 알림 한 번'),
        const _Bullet(icon: '📝', text: '날짜·용량·부위·메모 기록'),
        const _Bullet(icon: '🔒', text: '투약 기록·용량은 AI 조언에 쓰지 않아'),
        const SizedBox(height: FoodietShape.sp24),
        PrimaryButton(
          label: existing == null ? '시작하기' : '다시 켜기',
          icon: Icons.vaccines_outlined,
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});
  final String icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style:
                    FoodietText.body.copyWith(color: FoodietColors.warm700)),
          ),
        ],
      ),
    );
  }
}

// ─── 켜짐 ─────────────────────────────────────────────────────────────

class _ActiveBody extends ConsumerWidget {
  const _ActiveBody({
    required this.plan,
    required this.removed,
    required this.busy,
    required this.onLog,
    required this.onEdit,
    required this.onTurnOff,
    required this.confirmDelete,
    required this.onDismissed,
  });
  final MedicationPlan plan;
  final Set<String> removed;
  final bool busy;
  final VoidCallback onLog;
  final VoidCallback onEdit;
  final VoidCallback onTurnOff;
  final Future<bool> Function(MedicationLog) confirmDelete;
  final void Function(String id) onDismissed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(medicationLogsProvider);
    final loaded = logsAsync.valueOrNull;
    // 기록을 아직 못 불러왔으면 D-day 를 시작일로 잘못 계산하지 않는다.
    if (loaded == null) {
      if (logsAsync.hasError) {
        return _LoadError(
          onRetry: () => ref.invalidate(medicationLogsProvider),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: FoodietColors.coral500),
      );
    }
    final logs = loaded.where((l) => !removed.contains(l.id)).toList();
    final last = logs.isEmpty ? null : logs.first;
    final due = computeMedicationDue(plan, last?.takenAt, DateTime.now());

    return RefreshIndicator(
      color: FoodietColors.coral500,
      onRefresh: () async {
        ref.invalidate(medicationPlanProvider);
        ref.invalidate(medicationLogsProvider);
        try {
          await ref.read(medicationLogsProvider.future);
        } catch (_) {/* 실패 상태는 화면이 재시도 버튼으로 보여준다 */}
      },
      child: ListView(
        padding: const EdgeInsets.all(FoodietShape.sp20),
        children: [
          _DueCard(plan: plan, due: due, last: last),
          const SizedBox(height: FoodietShape.sp16),
          PrimaryButton(
            label: '오늘 맞았어',
            icon: Icons.check_rounded,
            onPressed: onLog,
          ),
          const SizedBox(height: FoodietShape.sp24),
          Text('투약 기록',
              style: FoodietText.title.copyWith(
                color: FoodietColors.warm900,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: FoodietShape.sp8),
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text("아직 기록이 없어. 맞고 나면 '오늘 맞았어'를 눌러줘.",
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
            )
          else ...[
            for (final log in logs) ...[
              Dismissible(
                key: ValueKey('med-log-${log.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => confirmDelete(log),
                onDismissed: (_) => onDismissed(log.id),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: FoodietColors.danger.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: FoodietColors.danger),
                ),
                child: _LogRow(log: log),
              ),
              const SizedBox(height: FoodietShape.sp8),
            ],
            Text('왼쪽으로 밀면 기록을 지울 수 있어.',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ],
          const SizedBox(height: FoodietShape.sp24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('계획 수정'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FoodietColors.warm700,
                    side: const BorderSide(color: FoodietColors.cream100),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onTurnOff,
                  icon: const Icon(Icons.power_settings_new_rounded,
                      size: 18),
                  label: const Text('투약 관리 끄기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FoodietColors.warm500,
                    side: const BorderSide(color: FoodietColors.cream100),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp16),
        ],
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.plan, required this.due, required this.last});
  final MedicationPlan plan;
  final MedicationDue due;
  final MedicationLog? last;

  @override
  Widget build(BuildContext context) {
    final d = due.days;
    final isToday = d == 0;
    final overdue = d != null && d < 0;
    final bg = isToday ? FoodietColors.coral50 : FoodietColors.cream50;
    final border = isToday ? FoodietColors.coral100 : FoodietColors.cream100;
    final bigColor = isToday
        ? FoodietColors.coral600
        : overdue
            ? FoodietColors.warm700
            : FoodietColors.warm900;

    final sub = <String>[
      if (due.due != null) '예정일 ${medDateLabel(due.due!)}',
      if (plan.reminderEnabled && due.due != null)
        '${medHourLabel(plan.reminderHour)} 알림',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: border),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '💉 ${plan.displayName} · ${formatDose(plan.currentDoseMg)} · '
              '${plan.intervalDays == 7 ? '매주' : '${plan.intervalDays}일마다'}',
              style: FoodietText.bodySm.copyWith(
                color: FoodietColors.warm500,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: FoodietShape.sp12),
          Text('다음 투약',
              style:
                  FoodietText.caption.copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: 2),
          Text(
            due.due == null ? '시작일을 정해줘' : due.label,
            style: (due.due == null ? FoodietText.h3 : FoodietText.numberLarge)
                .copyWith(color: bigColor),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: FoodietShape.sp8),
            Text(sub.join(' · '),
                style:
                    FoodietText.body.copyWith(color: FoodietColors.warm700)),
          ],
          if (last != null) ...[
            const SizedBox(height: 4),
            Text(
                '마지막 기록 ${medDateTimeLabel(last!.takenAt)} · ${formatDose(last!.doseMg)}',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500)),
          ],
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});
  final MedicationLog log;

  @override
  Widget build(BuildContext context) {
    final site = kInjectionSites[log.site];
    final meta = <String>[
      formatDose(log.doseMg),
      log.displayName,
      if (site != null) site,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('💉', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(medDateTimeLabel(log.takenAt),
                    style: FoodietText.body.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700,
                    )),
                Text(meta.join(' · '),
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                if (log.note != null && log.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(log.note!,
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm700)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
