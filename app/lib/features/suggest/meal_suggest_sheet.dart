/// "뭐 먹지?" 바텀시트 — 상황 고르기 → 남은 kcal 에 맞는 메뉴 3개(회식은 가이드).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/entries_provider.dart';
import '../../providers/supabase_provider.dart';
import '../../services/app_events.dart';
import '../../services/manual_entry_service.dart';
import '../../services/meal_suggest_service.dart';
import '../../theme/foodiet_tokens.dart';

final mealSuggestServiceProvider = Provider<MealSuggestService>(
    (ref) => MealSuggestService(ref.watch(supabaseClientProvider)));

Future<void> showMealSuggestSheet(BuildContext context) {
  AppEvents.log('suggest_opened');
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: FoodietColors.cream00,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusLg)),
    ),
    builder: (_) => const MealSuggestSheet(),
  );
}

class MealSuggestSheet extends ConsumerStatefulWidget {
  const MealSuggestSheet({super.key});

  @override
  ConsumerState<MealSuggestSheet> createState() => _MealSuggestSheetState();
}

class _MealSuggestSheetState extends ConsumerState<MealSuggestSheet> {
  SuggestSituation? _situation;
  SuggestResult? _result;
  String? _error;
  bool _loading = false;
  final Set<String> _logged = {};
  String? _logging;

  Future<void> _ask(SuggestSituation s) async {
    if (_loading) return;
    setState(() {
      _situation = s;
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await ref.read(mealSuggestServiceProvider).suggest(s);
      if (!mounted) return;
      setState(() => _result = r);
    } on SuggestRateLimited {
      if (!mounted) return;
      setState(() => _error = '오늘은 여기까지 물어볼 수 있어. 내일 또 같이 고르자 🌙');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '지금은 추천을 못 불러왔어. 잠깐 뒤에 다시 해볼래?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ate(SuggestOption o) async {
    if (_logging != null || _logged.contains(o.name)) return;
    setState(() => _logging = o.name);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context);
    final service = ref.read(manualEntryServiceProvider);
    try {
      final id = await service.record(
        source: 'suggestion',
        title: o.name,
        kcal: o.kcal,
        carbG: o.carbG,
        proteinG: o.proteinG,
        fatG: o.fatG,
      );
      container.invalidate(todayEntriesProvider);
      container.invalidate(recentEntriesProvider);
      AppEvents.log('suggest_logged',
          {'situation': _situation?.key, 'kcal': o.kcal});
      if (mounted) setState(() => _logged.add(o.name));
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('기록했어 · ${o.name} ${o.kcal} kcal'),
          action: SnackBarAction(
            label: '실행취소',
            onPressed: () async {
              await service.undo(id);
              container.invalidate(todayEntriesProvider);
              container.invalidate(recentEntriesProvider);
            },
          ),
        ));
    } on ManualEntryException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('기록 못 했어. 잠깐 뒤에 다시 해볼래?')));
    } finally {
      if (mounted) setState(() => _logging = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(FoodietShape.sp20, FoodietShape.sp16,
            FoodietShape.sp20, FoodietShape.sp40),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: FoodietColors.cream100,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: FoodietShape.sp16),
          Text('뭐 먹지? 🍽️',
              style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
          const SizedBox(height: 4),
          Text('지금 어디서 먹어? 남은 칼로리에 맞춰 골라줄게.',
              style:
                  FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: FoodietShape.sp16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SuggestSituation.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _situation == s,
                  onSelected: _loading ? null : (_) => _ask(s),
                  selectedColor: FoodietColors.coral100,
                  backgroundColor: FoodietColors.cream50,
                  side: const BorderSide(color: FoodietColors.cream100),
                ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(FoodietShape.sp24),
              child: Center(
                child: CircularProgressIndicator(color: FoodietColors.coral500),
              ),
            )
          else if (_error != null)
            Text(_error!,
                style: FoodietText.body.copyWith(color: FoodietColors.warm700))
          else if (_result != null)
            ..._buildResult(_result!),
          const SizedBox(height: FoodietShape.sp20),
          Text('일반적인 식사 가이드야. 질환이 있거나 치료 중이면 전문가와 상의해줘.',
              style:
                  FoodietText.caption.copyWith(color: FoodietColors.warm500)),
        ],
      ),
    );
  }

  List<Widget> _buildResult(SuggestResult r) {
    final widgets = <Widget>[
      if (r.intro.isNotEmpty)
        Text(r.intro,
            style: FoodietText.body.copyWith(color: FoodietColors.warm900)),
      const SizedBox(height: FoodietShape.sp12),
    ];
    final h = r.hoesik;
    if (h != null) {
      void section(String title, List<String> items) {
        if (items.isEmpty) return;
        widgets.add(_GuideSection(title: title, items: items));
      }

      section('🕐 미리 챙길 것', h.before);
      section('🍖 안주 고르기', h.orderTips);
      section('🍺 술 마실 때', h.drinkTips);
      section('🌅 다음 날', h.nextDay);
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: FoodietShape.sp8),
        child: Text('먹은 건 평소처럼 사진으로 남겨줘. 푸디가 분석할게.',
            style:
                FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
      ));
      return widgets;
    }
    for (final o in r.options) {
      widgets.add(_OptionCard(
        option: o,
        logged: _logged.contains(o.name),
        busy: _logging == o.name,
        onAte: () => _ate(o),
      ));
    }
    return widgets;
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FoodietShape.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: FoodietText.title.copyWith(color: FoodietColors.warm700)),
          const SizedBox(height: 4),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· $i',
                  style: FoodietText.body
                      .copyWith(color: FoodietColors.warm900)),
            ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.logged,
    required this.busy,
    required this.onAte,
  });
  final SuggestOption option;
  final bool logged;
  final bool busy;
  final VoidCallback onAte;

  @override
  Widget build(BuildContext context) {
    final o = option;
    return Container(
      margin: const EdgeInsets.only(bottom: FoodietShape.sp12),
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(o.name,
                    style: FoodietText.title
                        .copyWith(color: FoodietColors.warm900)),
              ),
              const SizedBox(width: FoodietShape.sp8),
              Text('${o.kcal} kcal',
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.coral500,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '단백질 ${o.proteinG.round()}g · 탄수 ${o.carbG.round()}g · 지방 ${o.fatG.round()}g',
              style:
                  FoodietText.caption.copyWith(color: FoodietColors.warm500)),
          if (o.why.isNotEmpty) ...[
            const SizedBox(height: FoodietShape.sp8),
            Text(o.why,
                style:
                    FoodietText.bodySm.copyWith(color: FoodietColors.warm700)),
          ],
          if (o.tip.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('💡 ${o.tip}',
                style:
                    FoodietText.bodySm.copyWith(color: FoodietColors.warm700)),
          ],
          const SizedBox(height: FoodietShape.sp12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: logged || busy ? null : onAte,
              style: OutlinedButton.styleFrom(
                foregroundColor: FoodietColors.coral500,
                side: const BorderSide(color: FoodietColors.coral100),
              ),
              child: Text(logged
                  ? '기록했어 ✓'
                  : busy
                      ? '기록 중…'
                      : '이거 먹었어'),
            ),
          ),
        ],
      ),
    );
  }
}
