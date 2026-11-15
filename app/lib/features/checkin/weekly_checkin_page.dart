/// 주간 체크인 화면 — 라우트 `/weekly-checkin` (등록은 통합 단계에서).
///
/// 흐름: 한 주 요약(잘한 점·패턴) → 다음 주 실험 3개 중 1개 선택(또는 직접 입력)
/// → "이번 주 이걸로 해볼게" → 공유. 이미 고른 주면 고른 실험 + 공유 + 바꾸기.
/// 기록이 2일 미만이면 서버가 결정적 문구만 준다 → 억지 결론 없이 안내만.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/profile_provider.dart';
import '../../providers/weekly_checkin_provider.dart';
import '../../services/app_events.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/foodie_bubble.dart';
import '../../widgets/primary_button.dart';
import 'checkin_share_card.dart';

class WeeklyCheckinPage extends ConsumerStatefulWidget {
  const WeeklyCheckinPage({super.key});

  @override
  ConsumerState<WeeklyCheckinPage> createState() => _WeeklyCheckinPageState();
}

class _WeeklyCheckinPageState extends ConsumerState<WeeklyCheckinPage> {
  /// 0~2 = 제안 실험, 3 = 직접 입력, null = 미선택.
  int? _selected;
  final _custom = TextEditingController();
  bool _saving = false;
  bool _editing = false;
  bool _sharing = false;

  static const int _customIndex = 3;

  @override
  void initState() {
    super.initState();
    AppEvents.log('checkin_opened');
    _custom.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String? _pickedText(CheckinReport r) {
    final s = _selected;
    if (s == null) return null;
    if (s == _customIndex) {
      final t = _custom.text.trim();
      return t.isEmpty ? null : t;
    }
    return s < r.experiments.length ? r.experiments[s].ifThen : null;
  }

  void _startEditing(WeeklyCheckin c) {
    final r = c.report!;
    final chosen = c.chosenExperiment;
    final idx = r.experiments.indexWhere((e) => e.ifThen == chosen);
    setState(() {
      _editing = true;
      if (idx >= 0) {
        _selected = idx;
      } else if (chosen != null) {
        _selected = _customIndex;
        _custom.text = chosen;
      }
    });
  }

  Future<void> _complete(WeeklyCheckin c) async {
    final text = _pickedText(c.report!);
    if (text == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(weeklyCheckinRepoProvider).complete(c.weekStart, text);
      if (!mounted) return;
      setState(() => _editing = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('좋아, 이번 주 실험으로 정했어 🌱 홈에서 푸디가 가끔 챙겨줄게.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('저장하지 못했어. 잠시 뒤에 다시 해볼래?')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share(WeeklyCheckin c, String experiment) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = await ref.read(profileProvider.future);
      if (!mounted) return;
      await shareCheckinCard(
        context,
        CheckinShareData(
          weekStart: c.weekStart,
          nickname: profile?.nickname ?? '나',
          report: c.report!,
          experiment: experiment,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('공유 이미지를 만들지 못했어. 다시 해볼래?')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(weeklyCheckinProvider);
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: FoodietColors.warm900, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('이번 주 돌아보기',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => const _Loading(),
          error: (_, __) => _ErrorView(
              onRetry: () => ref.invalidate(weeklyCheckinProvider)),
          data: (c) => c.insufficient || c.report == null
              ? _Insufficient(checkin: c)
              : _buildReport(c),
        ),
      ),
    );
  }

  Widget _buildReport(WeeklyCheckin c) {
    final r = c.report!;
    final showPicker = !c.isCompleted || _editing;
    return ListView(
      padding: const EdgeInsets.fromLTRB(FoodietShape.sp20, FoodietShape.sp8,
          FoodietShape.sp20, FoodietShape.sp40),
      children: [
        _SummaryCard(checkin: c, report: r),
        if (r.wins.isNotEmpty) ...[
          const _SectionTitle('잘한 점'),
          ...r.wins.map((w) => _WinRow(text: w)),
        ],
        if (r.pattern.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp20),
          FoodieBubble(headline: '푸디가 본 패턴', why: r.pattern),
        ],
        if (showPicker) ..._picker(c, r) else ..._chosen(c),
        if (r.note.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp24),
          Text(r.note,
              textAlign: TextAlign.center,
              style: FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
        ],
      ],
    );
  }

  List<Widget> _picker(WeeklyCheckin c, CheckinReport r) {
    final canSubmit = _pickedText(r) != null && !_saving;
    return [
      const _SectionTitle('다음 주에 해볼 실험 하나 골라봐'),
      for (var i = 0; i < r.experiments.length; i++)
        _OptionTile(
          selected: _selected == i,
          title: r.experiments[i].ifThen,
          subtitle: r.experiments[i].why,
          onTap: () => setState(() => _selected = i),
        ),
      _OptionTile(
        selected: _selected == _customIndex,
        title: '직접 정할래',
        subtitle: _selected == _customIndex ? null : '내 상황에 맞는 실험을 써봐',
        onTap: () => setState(() => _selected = _customIndex),
        child: _selected == _customIndex
            ? Padding(
                padding: const EdgeInsets.only(top: FoodietShape.sp8),
                child: TextField(
                  controller: _custom,
                  autofocus: true,
                  maxLength: 60,
                  style: FoodietText.body.copyWith(color: FoodietColors.warm900),
                  decoration: InputDecoration(
                    hintText: '예: 저녁 먹고 출출하면 따뜻한 차 마시기',
                    hintStyle: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500),
                    filled: true,
                    fillColor: FoodietColors.cream00,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusSm),
                      borderSide:
                          const BorderSide(color: FoodietColors.cream100),
                    ),
                  ),
                ),
              )
            : null,
      ),
      const SizedBox(height: FoodietShape.sp16),
      PrimaryButton(
        label: _saving ? '저장하는 중…' : '이번 주 이걸로 해볼게',
        onPressed: canSubmit ? () => _complete(c) : null,
      ),
      if (_editing) ...[
        const SizedBox(height: FoodietShape.sp8),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _editing = false),
            child: Text('그대로 둘래',
                style:
                    FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
          ),
        ),
      ],
    ];
  }

  List<Widget> _chosen(WeeklyCheckin c) {
    final exp = c.chosenExperiment ?? '';
    return [
      const _SectionTitle('이번 주 실험'),
      Container(
        padding: const EdgeInsets.all(FoodietShape.sp16),
        decoration: BoxDecoration(
          color: FoodietColors.coral50,
          border: Border.all(color: FoodietColors.coral100),
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        ),
        child: Row(
          children: [
            const Text('🧪', style: TextStyle(fontSize: 22)),
            const SizedBox(width: FoodietShape.sp12),
            Expanded(
              child: Text(exp,
                  style: FoodietText.title.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      const SizedBox(height: FoodietShape.sp16),
      PrimaryButton(
        label: _sharing ? '이미지 만드는 중…' : '친구에게 공유하기',
        icon: Icons.ios_share,
        onPressed: _sharing || exp.isEmpty ? null : () => _share(c, exp),
      ),
      const SizedBox(height: FoodietShape.sp8),
      Center(
        child: TextButton(
          onPressed: () => _startEditing(c),
          child: Text('실험 바꾸기',
              style: FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
        ),
      ),
    ];
  }
}

// ── 조각 위젯 ─────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.checkin, required this.report});
  final WeeklyCheckin checkin;
  final CheckinReport report;

  @override
  Widget build(BuildContext context) {
    final days = report.daysLogged ?? checkin.daysLogged;
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
          Text(checkinWeekLabel(checkin.weekStart),
              style:
                  FoodietText.caption.copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: FoodietShape.sp8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Text(report.headline,
                    style: FoodietText.h3.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (days != null) ...[
            const SizedBox(height: FoodietShape.sp12),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Container(
                    width: 18,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: i < days
                          ? FoodietColors.leaf500
                          : FoodietColors.warm200,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                const SizedBox(width: FoodietShape.sp4),
                Flexible(
                  child: Text('7일 중 $days일 기록',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoodietText.caption.copyWith(
                          color: FoodietColors.leaf700,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
            top: FoodietShape.sp24, bottom: FoodietShape.sp8),
        child: Text(text,
            style: FoodietText.title.copyWith(
                color: FoodietColors.warm900, fontWeight: FontWeight.w700)),
      );
}

class _WinRow extends StatelessWidget {
  const _WinRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: FoodietShape.sp8, top: 1),
              decoration: const BoxDecoration(
                  color: FoodietColors.leaf100, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.check,
                  size: 14, color: FoodietColors.leaf700),
            ),
            Expanded(
              child: Text(text,
                  style:
                      FoodietText.body.copyWith(color: FoodietColors.warm700)),
            ),
          ],
        ),
      );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.child,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(FoodietShape.sp16),
          decoration: BoxDecoration(
            color: selected ? FoodietColors.coral50 : FoodietColors.cream50,
            border: Border.all(
              color: selected ? FoodietColors.coral500 : FoodietColors.cream100,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? FoodietColors.coral500 : FoodietColors.warm500,
              ),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: FoodietText.body.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: FoodietText.bodySm
                              .copyWith(color: FoodietColors.warm500)),
                    ],
                    if (child != null) child!,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🍓', style: TextStyle(fontSize: 40)),
            const SizedBox(height: FoodietShape.sp12),
            Text('푸디가 한 주를 돌아보는 중이야…',
                style:
                    FoodietText.body.copyWith(color: FoodietColors.warm700)),
            const SizedBox(height: FoodietShape.sp16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: FoodietColors.coral500),
            ),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(FoodietShape.sp24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌧️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: FoodietShape.sp12),
              Text('지금은 돌아보기를 불러오지 못했어',
                  textAlign: TextAlign.center,
                  style: FoodietText.title.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('네트워크를 확인하고 다시 해보자.',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
              const SizedBox(height: FoodietShape.sp20),
              PrimaryButton(
                  label: '다시 시도', fullWidth: false, onPressed: onRetry),
            ],
          ),
        ),
      );
}

class _Insufficient extends StatelessWidget {
  const _Insufficient({required this.checkin});
  final WeeklyCheckin checkin;

  @override
  Widget build(BuildContext context) {
    final days = checkin.daysLogged ?? 0;
    return ListView(
      padding: const EdgeInsets.all(FoodietShape.sp20),
      children: [
        Text(checkinWeekLabel(checkin.weekStart),
            style: FoodietText.caption.copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: FoodietShape.sp12),
        FoodieBubble(
          headline: checkin.headline ?? '기록이 쌓이면 같이 돌아보자',
          // 돌아보는 주는 보통 "지난 주"(일 17시 전) → '이번 주' 라고 하지 않는다.
          why: days > 0
              ? '이 주에는 $days일 기록이 있어. 한 주를 돌아보려면 이틀 이상 기록이 필요해. '
                  '끼니마다 기록을 남겨두면 다음 돌아보기 땐 푸디가 정리해줄게.'
              : '이 주에는 아직 기록이 없어. 끼니마다 기록을 남겨두면 '
                  '다음 돌아보기 땐 푸디가 한 주를 정리해줄게.',
        ),
      ],
    );
  }
}
