/// 요리 상세 — 식단의 한 끼니를 탭하면 진입.
///
/// 상단: 음식 이미지(없으면 스타일 헤더). 하단: 재료(수량) · 만드는 방법 ·
/// 쇼핑 구매리스트(쿠팡·이마트·컬리 검색) · 참고리스트.
/// 모든 상세는 식단 생성 시 함께 만들어져 plan_json 에 저장된 값이다.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/meal_plan_service.dart';
import '../../theme/foodiet_tokens.dart';
import 'meal_plan_citations_sheet.dart';

class MealDetailPage extends StatelessWidget {
  const MealDetailPage({super.key, required this.meal, this.plan});
  final MealPlanMeal meal;
  final MealPlan? plan;

  @override
  Widget build(BuildContext context) {
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
        title: Text(meal.name.isEmpty ? '요리 상세' : meal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: FoodietShape.sp40),
        children: [
          _imageHeader(),
          Padding(
            padding: const EdgeInsets.all(FoodietShape.sp20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _slotKcalRow(),
                const SizedBox(height: FoodietShape.sp8),
                Text(meal.name,
                    style: FoodietText.h3.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    '탄 ${meal.carbG}g · 단 ${meal.proteinG}g · 지 ${meal.fatG}g',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                if (meal.recipeBrief.isNotEmpty) ...[
                  const SizedBox(height: FoodietShape.sp12),
                  Text(meal.recipeBrief,
                      style: FoodietText.body.copyWith(
                          color: FoodietColors.warm700, height: 1.5)),
                ],
                _ingredientsSection(),
                _stepsSection(),
                _shoppingSection(),
                _referencesSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageHeader() {
    final url = meal.imageUrl;
    if (url == null || url.isEmpty) return _styledHeader();
    return Image.network(
      url,
      height: 240,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _styledHeader(),
      loadingBuilder: (ctx, child, progress) =>
          progress == null ? child : _styledHeader(loading: true),
    );
  }

  Widget _styledHeader({bool loading = false}) {
    final c = _slotColor(meal.slot);
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.25), FoodietColors.cream50],
        ),
      ),
      alignment: Alignment.center,
      child: loading
          ? const CircularProgressIndicator(color: FoodietColors.coral500)
          : const Text('🍽️', style: TextStyle(fontSize: 64)),
    );
  }

  Widget _slotKcalRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: _slotColor(meal.slot).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
          ),
          child: Text(_slotLabel(meal.slot),
              style: FoodietText.caption.copyWith(
                  color: _slotColor(meal.slot),
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Text('${meal.kcal} kcal',
            style: FoodietText.bodySm.copyWith(
                color: FoodietColors.coral500, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.only(
            top: FoodietShape.sp20, bottom: FoodietShape.sp8),
        child: Text(t,
            style: FoodietText.title.copyWith(
                color: FoodietColors.warm900, fontWeight: FontWeight.w700)),
      );

  Widget _ingredientsSection() {
    final items = meal.shopping;
    if (items.isEmpty && meal.ingredients.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('재료'),
        if (items.isNotEmpty)
          ...items.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Text('· ',
                        style: TextStyle(color: FoodietColors.warm500)),
                    Expanded(
                      child: Text(s.name,
                          style: FoodietText.body
                              .copyWith(color: FoodietColors.warm900)),
                    ),
                    Text(s.qty,
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm500)),
                  ],
                ),
              ))
        else
          Text(meal.ingredients.join(' · '),
              style: FoodietText.body
                  .copyWith(color: FoodietColors.warm700, height: 1.5)),
      ],
    );
  }

  Widget _stepsSection() {
    final steps = meal.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('만드는 방법'),
        ...List.generate(
          steps.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: FoodietColors.coral100, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: FoodietText.caption.copyWith(
                          color: FoodietColors.coral500,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(steps[i],
                      style: FoodietText.body.copyWith(
                          color: FoodietColors.warm900, height: 1.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _shoppingSection() {
    final items = meal.shopping;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('쇼핑 구매리스트'),
        Text('재료별로 쇼핑몰 검색으로 이동해.',
            style: FoodietText.caption.copyWith(color: FoodietColors.warm500)),
        const SizedBox(height: FoodietShape.sp8),
        ...items.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(FoodietShape.sp12),
              decoration: BoxDecoration(
                color: FoodietColors.cream50,
                borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                border: Border.all(color: FoodietColors.cream100),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        s.qty.isEmpty ? s.name : '${s.name}  ${s.qty}',
                        style: FoodietText.bodySm.copyWith(
                            color: FoodietColors.warm900,
                            fontWeight: FontWeight.w700)),
                  ),
                  _storeBtn('쿠팡', _coupang(s.name)),
                  const SizedBox(width: 4),
                  _storeBtn('이마트', _emart(s.name)),
                  const SizedBox(width: 4),
                  _storeBtn('컬리', _kurly(s.name)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _storeBtn(String label, String url) => Material(
        color: FoodietColors.coral50,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _launch(url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(label,
                style: FoodietText.caption.copyWith(
                    color: FoodietColors.coral500,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _referencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('참고리스트'),
        _refCard(
            '한국인 영양섭취기준 (KDRIs, 2020)',
            '보건복지부·한국영양학회. 성별·연령·활동수준별 일일 에너지·매크로 권장 범위.',
            'https://www.mohw.go.kr/board.es?mid=a10411010100&bid=0019'),
        _refCard('USDA FoodData Central',
            '미국 농무부 식품 영양 데이터베이스. 메뉴별 매크로 추정 기준.',
            'https://fdc.nal.usda.gov/'),
        _refCard('EFSA — Adequate intake of water (2010)',
            '유럽식품안전청 성인 수분 충분섭취량 기준.',
            'https://www.efsa.europa.eu/en/efsajournal/pub/1459'),
        const SizedBox(height: FoodietShape.sp8),
        Center(child: MealPlanCitationsLink(plan: plan)),
      ],
    );
  }

  Widget _refCard(String title, String snippet, String url) => InkWell(
        onTap: () => _launch(url),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(FoodietShape.sp12),
          decoration: BoxDecoration(
            color: FoodietColors.cream50,
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(snippet,
                  style: FoodietText.caption
                      .copyWith(color: FoodietColors.warm700, height: 1.5)),
              const SizedBox(height: 4),
              Text(url,
                  style: FoodietText.caption.copyWith(
                      color: FoodietColors.coral500,
                      decoration: TextDecoration.underline)),
            ],
          ),
        ),
      );

  void _launch(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _coupang(String q) =>
      'https://www.coupang.com/np/search?q=${Uri.encodeComponent(q)}';
  String _emart(String q) =>
      'https://emart.ssg.com/search.ssg?query=${Uri.encodeComponent(q)}';
  String _kurly(String q) =>
      'https://www.kurly.com/search?sword=${Uri.encodeComponent(q)}';
}

String _slotLabel(String slot) {
  switch (slot) {
    case 'breakfast':
      return '아침';
    case 'lunch':
      return '점심';
    case 'dinner':
      return '저녁';
    case 'snack':
      return '간식';
    default:
      return slot;
  }
}

Color _slotColor(String slot) {
  switch (slot) {
    case 'breakfast':
      return FoodietColors.mealBreakfast;
    case 'lunch':
      return FoodietColors.mealLunch;
    case 'dinner':
      return FoodietColors.mealDinner;
    case 'snack':
      return FoodietColors.warm700;
    default:
      return FoodietColors.warm500;
  }
}
