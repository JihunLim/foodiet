/// 엔트리 상세 — 음식 사진 + 분석 결과 + 수정/삭제.
///
/// Phase E (MVP 완성도 개선):
///   - 음식 이름, 품목 리스트, 끼니 라벨, 시각, 공유 인원, 메모.
///   - 수정: 끼니·시간·공유 인원·메모 변경 후 저장.
///   - 삭제: 확인 다이얼로그 + DB 행 삭제 + Storage 파일 삭제.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/entries_provider.dart';
import '../../providers/supabase_provider.dart';
import '../../supabase/client.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';

class EntryDetailPage extends ConsumerWidget {
  const EntryDetailPage({super.key, required this.entryId});
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entryDetailProvider(entryId));
    // pending 동안 3초마다 자동 새로고침 (Realtime 폴백).
    ref.watch(pendingEntryDetailPollProvider(entryId));

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('기록',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: FoodietColors.warm900, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          async.when(
            data: (d) => d == null
                ? const SizedBox.shrink()
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: FoodietColors.warm900),
                    onSelected: (v) async {
                      if (v == 'delete') {
                        await _confirmAndDelete(context, ref, d.entry);
                      } else if (v == 'edit') {
                        await _openEditSheet(context, ref, d.entry);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('수정'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: FoodietColors.danger),
                          SizedBox(width: 10),
                          Text('삭제',
                              style: TextStyle(color: FoodietColors.danger)),
                        ]),
                      ),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: FoodietColors.coral500),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(FoodietShape.sp20),
              child: Text('기록을 불러오지 못했어: $e',
                  textAlign: TextAlign.center,
                  style: FoodietText.body
                      .copyWith(color: FoodietColors.warm700)),
            ),
          ),
          data: (d) {
            if (d == null) {
              return const Center(child: Text('기록을 찾을 수 없어'));
            }
            return _Body(detail: d);
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});
  final EntryDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = detail.entry;
    final items = detail.items;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final w = weekdays[entry.capturedAt.weekday - 1];
    final dateLabel = '${entry.capturedAt.year}년 '
        '${entry.capturedAt.month}월 ${entry.capturedAt.day}일 ($w) '
        '${DateFormat('HH:mm').format(entry.capturedAt)}';
    final mealLabel = _mealSlotLabel(entry.mealSlot);
    final mealColor = _mealSlotColor(entry.mealSlot);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp20, 0, FoodietShape.sp20, FoodietShape.sp40),
      children: [
        // 사진 — 전체가 보이도록 BoxFit.contain 으로 표시하고 탭하면
        // 풀스크린 확대 뷰어를 연다. 배경은 cream100 으로 letterbox.
        // 네트워크/CDN 일시 실패 시 SignedNetworkImage 가 새 URL 로 자동 재시도.
        GestureDetector(
          onTap: () => _openFullscreenPhoto(
              context, entry.imagePath, 'entry-photo-${entry.id}'),
          child: Hero(
            tag: 'entry-photo-${entry.id}',
            child: Container(
              width: double.infinity,
              height: 320,
              decoration: BoxDecoration(
                color: FoodietColors.cream100,
                borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SignedNetworkImage(
                    path: entry.imagePath,
                    fit: BoxFit.contain,
                    errorBuilder: (_) => Container(
                      color: FoodietColors.cream100,
                      alignment: Alignment.center,
                      child: const Text('🍽️', style: TextStyle(fontSize: 48)),
                    ),
                  ),
                  // 확대 힌트 아이콘 — 우하단.
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius:
                            BorderRadius.circular(FoodietShape.radiusSm),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded,
                              size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('크게 보기',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: FoodietShape.sp16),

        // 제목 + 끼니 배지
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: mealColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
              ),
              child: Text(mealLabel,
                  style: FoodietText.caption.copyWith(
                    color: mealColor,
                    fontWeight: FontWeight.w700,
                  )),
            ),
            if (entry.sharedWithCount > 1) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: FoodietColors.leaf100,
                  borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group_rounded,
                        size: 12, color: FoodietColors.leaf700),
                    const SizedBox(width: 4),
                    Text('${entry.sharedWithCount}명과 나눔',
                        style: FoodietText.caption.copyWith(
                          color: FoodietColors.leaf700,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: FoodietShape.sp8),
        Text(entry.title?.trim().isNotEmpty == true ? entry.title! : '식사 기록',
            style: FoodietText.h2.copyWith(color: FoodietColors.warm900)),
        const SizedBox(height: 2),
        Text(dateLabel,
            style:
                FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),

        const SizedBox(height: FoodietShape.sp20),

        // kcal 요약 카드
        _KcalCard(entry: entry),

        const SizedBox(height: FoodietShape.sp20),

        // 상태 안내 (분석 중 / 실패)
        if (entry.status == 'pending')
          _statusBanner(
            icon: Icons.hourglass_top_rounded,
            text: '푸디가 분석 중이야. 곧 결과가 떠!',
            color: FoodietColors.coral500,
          )
        else if (entry.status == 'failed')
          _statusBanner(
            icon: Icons.error_outline_rounded,
            text: '분석에 실패했어. 네트워크 확인 후 다시 찍어줘.',
            color: FoodietColors.danger,
          ),

        if (entry.status == 'done' && items.isNotEmpty) ...[
          Text('품목',
              style:
                  FoodietText.title.copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: FoodietShape.sp8),
          ...items.map((it) => _ItemRow(item: it)),
        ],

        if (entry.status == 'done' && entry.macros != null) ...[
          const SizedBox(height: FoodietShape.sp20),
          Text('영양소',
              style:
                  FoodietText.title.copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: FoodietShape.sp8),
          _MacrosCard(macros: entry.macros!),
        ],

        if (entry.note?.trim().isNotEmpty == true) ...[
          const SizedBox(height: FoodietShape.sp20),
          Text('메모',
              style:
                  FoodietText.title.copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: FoodietShape.sp8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(FoodietShape.sp12),
            decoration: BoxDecoration(
              color: FoodietColors.cream50,
              borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Text(entry.note!,
                style: FoodietText.body
                    .copyWith(color: FoodietColors.warm700)),
          ),
        ],

        const SizedBox(height: FoodietShape.sp24),

        // 수정 버튼
        FilledButton.icon(
          onPressed: () => _openEditSheet(context, ref, entry),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('수정하기'),
          style: FilledButton.styleFrom(
            backgroundColor: FoodietColors.coral500,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            ),
          ),
        ),
        const SizedBox(height: FoodietShape.sp8),
        OutlinedButton.icon(
          onPressed: () => _confirmAndDelete(context, ref, entry),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('삭제하기'),
          style: OutlinedButton.styleFrom(
            foregroundColor: FoodietColors.danger,
            side: const BorderSide(color: FoodietColors.danger),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp12),
      margin: const EdgeInsets.only(bottom: FoodietShape.sp20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: FoodietText.bodySm.copyWith(color: color)),
          ),
        ],
      ),
    );
  }

  String _mealSlotLabel(String? slot) => switch (slot) {
        'breakfast' => '아침',
        'lunch' => '점심',
        'dinner' => '저녁',
        'late_night' => '야식',
        _ => '분석중',
      };

  Color _mealSlotColor(String? slot) => switch (slot) {
        'breakfast' => FoodietColors.mealBreakfast,
        'lunch' => FoodietColors.mealLunch,
        'dinner' => FoodietColors.mealDinner,
        'late_night' => FoodietColors.warm700,
        _ => FoodietColors.warm500,
      };
}

class _KcalCard extends StatelessWidget {
  const _KcalCard({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final per = entry.kcalPerPerson ?? 0;
    final total = entry.kcalTotal ?? 0;
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.sharedWithCount > 1 ? '내 몫 (1인분)' : '칼로리',
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$per',
                        style: FoodietText.numberLarge
                            .copyWith(color: FoodietColors.coral500)),
                    const SizedBox(width: 4),
                    Text('kcal',
                        style: FoodietText.body.copyWith(
                            color: FoodietColors.warm500)),
                  ],
                ),
                if (entry.sharedWithCount > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '전체 $total kcal ÷ ${entry.sharedWithCount}명',
                      style: FoodietText.caption
                          .copyWith(color: FoodietColors.warm500),
                    ),
                  ),
              ],
            ),
          ),
          if (entry.confidence != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('신뢰도',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: 4),
                Text('${(entry.confidence! * 100).round()}%',
                    style: FoodietText.title.copyWith(
                      color: entry.confidence! >= 0.7
                          ? FoodietColors.leaf700
                          : FoodietColors.warning,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final EntryItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: FoodietShape.sp12, vertical: FoodietShape.sp8),
        decoration: BoxDecoration(
          color: FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.cream100),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700,
                      )),
                  if (item.qtyG != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('약 ${item.qtyG!.toStringAsFixed(0)}g',
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.warm500)),
                    ),
                ],
              ),
            ),
            Text('${item.kcal ?? 0} kcal',
                style: FoodietText.body.copyWith(
                  color: FoodietColors.coral500,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

class _MacrosCard extends StatelessWidget {
  const _MacrosCard({required this.macros});
  final Map<String, dynamic> macros;

  @override
  Widget build(BuildContext context) {
    final carb = (macros['carb_g'] as num?)?.toDouble() ?? 0;
    final protein = (macros['protein_g'] as num?)?.toDouble() ?? 0;
    final fat = (macros['fat_g'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MacroCell(
                label: '탄수화물',
                valueG: carb,
                color: FoodietColors.mealBreakfast),
          ),
          Expanded(
            child: _MacroCell(
                label: '단백질',
                valueG: protein,
                color: FoodietColors.leaf500),
          ),
          Expanded(
            child: _MacroCell(
                label: '지방',
                valueG: fat,
                color: FoodietColors.mealBeverage),
          ),
        ],
      ),
    );
  }
}

class _MacroCell extends StatelessWidget {
  const _MacroCell({
    required this.label,
    required this.valueG,
    required this.color,
  });
  final String label;
  final double valueG;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: FoodietText.caption
                .copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: 2),
        Text('${valueG.toStringAsFixed(1)}g',
            style: FoodietText.body.copyWith(
              color: FoodietColors.warm900,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

// ── 수정 sheet ────────────────────────────────────────────────────────

Future<void> _openEditSheet(
    BuildContext context, WidgetRef ref, Entry entry) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FoodietColors.cream00,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusXl)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + FoodietShape.sp20,
          top: FoodietShape.sp8),
      child: _EditEntrySheet(entry: entry),
    ),
  );
}

class _EditEntrySheet extends ConsumerStatefulWidget {
  const _EditEntrySheet({required this.entry});
  final Entry entry;

  @override
  ConsumerState<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends ConsumerState<_EditEntrySheet> {
  late String? _mealSlot = widget.entry.mealSlot;
  late DateTime _capturedAt = widget.entry.capturedAt;
  late int _sharedCount = widget.entry.sharedWithCount;
  late final _noteCtrl =
      TextEditingController(text: widget.entry.note ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _capturedAt,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_capturedAt),
    );
    if (time == null) return;
    setState(() {
      _capturedAt = DateTime(
          picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseClientProvider);
      await client.from('entries').update({
        'meal_slot': _mealSlot,
        'captured_at': _capturedAt.toUtc().toIso8601String(),
        'shared_with_count': _sharedCount,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      }).eq('id', widget.entry.id);

      // realtime 이 못 받아도 즉시 반영되도록 수동 invalidate.
      ref.invalidate(entryDetailProvider(widget.entry.id));
      ref.invalidate(todayEntriesProvider);
      ref.invalidate(recentEntriesProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '저장 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: FoodietShape.sp20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: FoodietShape.sp16),
              decoration: BoxDecoration(
                color: FoodietColors.cream100,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('기록 수정',
              style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
          const SizedBox(height: FoodietShape.sp16),

          // 끼니 라벨
          Text('끼니',
              style: FoodietText.caption.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: const [
              ('breakfast', '아침'),
              ('lunch', '점심'),
              ('dinner', '저녁'),
              ('late_night', '야식'),
            ].map((e) {
              final selected = _mealSlot == e.$1;
              return GestureDetector(
                onTap: () => setState(() => _mealSlot = e.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? FoodietColors.coral500
                        : FoodietColors.cream50,
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusMd),
                    border: Border.all(
                      color: selected
                          ? FoodietColors.coral500
                          : FoodietColors.cream100,
                    ),
                  ),
                  child: Text(
                    e.$2,
                    style: FoodietText.body.copyWith(
                      color:
                          selected ? Colors.white : FoodietColors.warm900,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: FoodietShape.sp16),

          // 시각
          Text('시각',
              style: FoodietText.caption.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 6),
          InkWell(
            onTap: _saving ? null : _pickTime,
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: FoodietColors.cream50,
                borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                border: Border.all(color: FoodietColors.cream100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 18, color: FoodietColors.warm500),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('yyyy.MM.dd HH:mm').format(_capturedAt),
                    style: FoodietText.body
                        .copyWith(color: FoodietColors.warm900),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: FoodietShape.sp16),

          // 공유 식사 인원
          Text('누구랑 먹었어?',
              style: FoodietText.caption.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 2),
          Text('나눠먹은 인원 수를 고르면 그만큼 나눈 칼로리로 계산해.',
              style: FoodietText.caption
                  .copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: 6),
          _SharedCountStepper(
            value: _sharedCount,
            onChanged: (v) => setState(() => _sharedCount = v),
          ),

          const SizedBox(height: FoodietShape.sp16),

          // 메모
          Text('메모 (선택)',
              style: FoodietText.caption.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: '오늘은 친구랑 같이 🍱',
              filled: true,
              fillColor: FoodietColors.cream50,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(FoodietShape.radiusMd),
                borderSide:
                    const BorderSide(color: FoodietColors.cream100),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(FoodietShape.radiusMd),
                borderSide:
                    const BorderSide(color: FoodietColors.cream100),
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: FoodietShape.sp8),
              child: Text(_error!,
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.danger)),
            ),

          const SizedBox(height: FoodietShape.sp16),

          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: FoodietColors.coral500,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('저장'),
          ),
          const SizedBox(height: FoodietShape.sp8),
        ],
      ),
    );
  }
}

class _SharedCountStepper extends StatelessWidget {
  const _SharedCountStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const min = 1;
    const max = 10;
    return Row(
      children: [
        _StepBtn(
          icon: Icons.remove,
          enabled: value > min,
          onTap: () => onChanged((value - 1).clamp(min, max)),
        ),
        Expanded(
          child: Center(
            child: Column(
              children: [
                Text('$value 명',
                    style: FoodietText.h3
                        .copyWith(color: FoodietColors.warm900)),
                const SizedBox(height: 2),
                Text(
                  value == 1 ? '혼자 먹음' : '$value 명이 같이 나눔',
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500),
                ),
              ],
            ),
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChanged((value + 1).clamp(min, max)),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? FoodietColors.coral500
              : FoodietColors.cream100,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 22,
            color: enabled ? Colors.white : FoodietColors.warm500),
      ),
    );
  }
}

// ── 삭제 ────────────────────────────────────────────────────────────

Future<void> _confirmAndDelete(
    BuildContext context, WidgetRef ref, Entry entry) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: FoodietColors.cream00,
      title: const Text('기록 삭제'),
      content: const Text('이 기록을 삭제하면 되돌릴 수 없어. 진짜 삭제할까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소',
              style: TextStyle(color: FoodietColors.warm500)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제',
              style: TextStyle(color: FoodietColors.danger)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final client = ref.read(supabaseClientProvider);
    // 1) entry_items 는 ON DELETE CASCADE 로 자동 삭제.
    await client.from('entries').delete().eq('id', entry.id);

    // 2) Storage 파일 제거 (best-effort).
    try {
      await client.storage
          .from(FoodietSupabase.foodPhotosBucket)
          .remove([entry.imagePath]);
    } catch (_) {
      // storage 삭제 실패해도 UI 는 계속 진행 — cron 청소에 맡긴다.
    }

    ref.invalidate(todayEntriesProvider);
    ref.invalidate(recentEntriesProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('삭제했어'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: FoodietColors.warm700,
    ));
    // 상세 페이지 pop.
    context.pop();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('삭제 실패: $e'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: FoodietColors.danger,
    ));
  }
}

// ── 풀스크린 사진 뷰어 ────────────────────────────────────────────────

/// [imagePath] 의 signed URL 을 큰 화면으로 띄운다. Hero 애니메이션으로
/// 상세 페이지의 사진과 이어지고, InteractiveViewer 로 핀치 줌·팬이 된다.
void _openFullscreenPhoto(
    BuildContext context, String imagePath, String heroTag) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          _FullscreenPhotoViewer(imagePath: imagePath, heroTag: heroTag),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _FullscreenPhotoViewer extends StatelessWidget {
  const _FullscreenPhotoViewer({
    required this.imagePath,
    required this.heroTag,
  });
  final String imagePath;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 바깥 탭 → 닫기 (사진 위 탭은 InteractiveViewer 가 먹음).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
          Center(
            child: Hero(
              tag: heroTag,
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: SignedNetworkImage(
                  path: imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (_) => Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: const Text(
                      '🍽️',
                      style: TextStyle(fontSize: 64),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 닫기 버튼 — 우상단 SafeArea.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(FoodietShape.sp12),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
