/// 식단짜기 폼 — 알레르기 · 냉장고 재료 · 식단 스타일 · 포함 끼니 입력 후
/// `generate-meal-plan` Edge Function 호출.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/meal_plan_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

Future<void> showMealPlanFormSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _MealPlanFormSheet(),
  );
}

const _allergyOptions = <String>[
  '견과류', '갑각류', '우유', '글루텐', '콩', '계란', '생선', '복숭아', '돼지고기', '소고기',
];
const _ingredientOptions = <String>[
  '닭가슴살', '계란', '두부', '연어', '돼지고기', '소고기', '양배추', '시금치', '브로콜리',
  '토마토', '양파', '마늘', '쌀', '귀리', '고구마', '바나나', '사과', '치즈', '요거트',
];
const _styleOptions = <Map<String, String>>[
  {'value': 'korean', 'label': '한식'},
  {'value': 'western', 'label': '양식'},
  {'value': 'japanese', 'label': '일식'},
  {'value': 'simple', 'label': '간단식'},
  {'value': 'salad', 'label': '샐러드 위주'},
  {'value': 'low_carb', 'label': '저탄수'},
];
const _slotOptions = <Map<String, String>>[
  {'value': 'breakfast', 'label': '아침'},
  {'value': 'lunch', 'label': '점심'},
  {'value': 'dinner', 'label': '저녁'},
  {'value': 'snack', 'label': '간식'},
];

class _MealPlanFormSheet extends ConsumerStatefulWidget {
  const _MealPlanFormSheet();

  @override
  ConsumerState<_MealPlanFormSheet> createState() => _MealPlanFormSheetState();
}

class _MealPlanFormSheetState extends ConsumerState<_MealPlanFormSheet> {
  final Set<String> _allergies = <String>{};
  final _allergyNotes = TextEditingController();
  final Set<String> _ingredients = <String>{};
  final _ingredientNotes = TextEditingController();
  final Set<String> _styles = <String>{};
  final Set<String> _slots = {'breakfast', 'lunch', 'dinner'};
  String? _error;

  @override
  void dispose() {
    _allergyNotes.dispose();
    _ingredientNotes.dispose();
    super.dispose();
  }

  void _submit() {
    if (_slots.isEmpty) {
      setState(() => _error = '포함할 끼니를 1개 이상 골라줘.');
      return;
    }
    // 백그라운드 생성 시작 후 시트를 바로 닫는다. 진행 상태("푸디가 만들고
    // 있어요")는 식단추천 탭이 mealPlanGeneratorProvider 로 보여준다.
    ref.read(mealPlanGeneratorProvider.notifier).start(
          allergies: _allergies.toList(),
          allergyNotes: _allergyNotes.text.trim(),
          ingredients: _ingredients.toList(),
          ingredientNotes: _ingredientNotes.text.trim(),
          cuisineStyles: _styles.toList(),
          mealSlots: _slots.toList(),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: FoodietColors.cream00,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusLg)),
        ),
        child: SingleChildScrollView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            FoodietShape.sp20,
            FoodietShape.sp16,
            FoodietShape.sp20,
            MediaQuery.of(ctx).viewInsets.bottom + FoodietShape.sp24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FoodietColors.cream100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: FoodietShape.sp16),
              Text('이번 주 식단 짜기',
                  style: FoodietText.h3
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: 4),
              Text(
                '입력 정보로 AI 가 7일치 식단을 만들어줘. 만드는 데 30초 정도 걸려.',
                style: FoodietText.caption
                    .copyWith(color: FoodietColors.warm500),
              ),
              const SizedBox(height: FoodietShape.sp20),

              _section('포함할 끼니'),
              const SizedBox(height: 6),
              _chipWrap(
                options:
                    _slotOptions.map((m) => _ChipOpt(m['value']!, m['label']!)).toList(),
                selected: _slots,
              ),
              const SizedBox(height: FoodietShape.sp16),

              _section('알레르기·피하고 싶은 음식'),
              const SizedBox(height: 6),
              _chipWrap(
                options:
                    _allergyOptions.map((s) => _ChipOpt(s, s)).toList(),
                selected: _allergies,
              ),
              const SizedBox(height: 8),
              _notesField(_allergyNotes, '기타 알레르기·기피 음식 (예: 고수, 매운 음식)'),
              const SizedBox(height: FoodietShape.sp16),

              _section('냉장고 재료'),
              const SizedBox(height: 6),
              _chipWrap(
                options:
                    _ingredientOptions.map((s) => _ChipOpt(s, s)).toList(),
                selected: _ingredients,
              ),
              const SizedBox(height: 8),
              _notesField(_ingredientNotes, '기타 보유 재료 (예: 닭다리살 300g, 김치)'),
              const SizedBox(height: FoodietShape.sp16),

              _section('선호 식단 스타일 (선택)'),
              const SizedBox(height: 6),
              _chipWrap(
                options:
                    _styleOptions.map((m) => _ChipOpt(m['value']!, m['label']!)).toList(),
                selected: _styles,
              ),
              const SizedBox(height: FoodietShape.sp24),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FoodietColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: FoodietColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: FoodietText.bodySm.copyWith(
                                color: FoodietColors.warm900)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FoodietShape.sp12),
              ],

              PrimaryButton(
                label: '식단 만들기',
                onPressed: _submit,
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '만들기를 누르면 닫히고, 식단추천 화면에서 푸디가 만드는 동안 기다리면 돼.',
                  textAlign: TextAlign.center,
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String text) => Text(text,
      style: FoodietText.bodySm.copyWith(
          color: FoodietColors.warm700, fontWeight: FontWeight.w700));

  Widget _chipWrap({
    required List<_ChipOpt> options,
    required Set<String> selected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final on = selected.contains(opt.value);
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            setState(() {
              if (on) {
                selected.remove(opt.value);
              } else {
                selected.add(opt.value);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on
                  ? FoodietColors.coral500
                  : FoodietColors.cream50,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: on
                    ? FoodietColors.coral500
                    : FoodietColors.cream100,
              ),
            ),
            child: Text(
              opt.label,
              style: FoodietText.bodySm.copyWith(
                color: on ? Colors.white : FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _notesField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      maxLength: 200,
      maxLines: 2,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: FoodietText.bodySm
            .copyWith(color: FoodietColors.warm500.withValues(alpha: 0.6)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          borderSide: const BorderSide(color: FoodietColors.cream100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          borderSide: const BorderSide(color: FoodietColors.cream100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          borderSide:
              const BorderSide(color: FoodietColors.coral500, width: 1.4),
        ),
      ),
    );
  }
}

class _ChipOpt {
  const _ChipOpt(this.value, this.label);
  final String value;
  final String label;
}
