/// 식단 추천 + 물 권장량의 "의학적 조언 아님 / 산출 근거" 모달.
///
/// 홈 코치의 `science_citations_sheet.dart` 패턴을 식단·물 도메인에 맞게
/// 별도로 구현. App Store guideline 1.4.1 대응 — AI 식단 제안은 진단·치료가
/// 아니며, 사용자 입력값과 모델/표준 영양 가이드만으로 만들어졌다는 점을
/// 명시한다.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/meal_plan_service.dart';
import '../../theme/foodiet_tokens.dart';

void showMealPlanCitationsSheet(
  BuildContext context, {
  MealPlan? plan,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MealPlanCitationsSheet(plan: plan),
  );
}

class MealPlanCitationsLink extends StatelessWidget {
  const MealPlanCitationsLink({super.key, this.plan});
  final MealPlan? plan;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showMealPlanCitationsSheet(context, plan: plan),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book_rounded,
                size: 14, color: FoodietColors.warm500),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '의학적 조언이 아니야 · 산출 근거 보기',
                style: FoodietText.caption.copyWith(
                  color: FoodietColors.warm500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealPlanCitationsSheet extends StatelessWidget {
  const _MealPlanCitationsSheet({this.plan});
  final MealPlan? plan;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: FoodietColors.cream00,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FoodietShape.radiusLg)),
        ),
        child: SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
              FoodietShape.sp20, FoodietShape.sp16, FoodietShape.sp20, FoodietShape.sp24),
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
              Text('산출 근거',
                  style: FoodietText.h3
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: FoodietShape.sp16),
              _disclaimer(),
              const SizedBox(height: FoodietShape.sp16),
              _sectionTitle('이 식단/물 권장량은 이렇게 만들어졌어'),
              const SizedBox(height: FoodietShape.sp8),
              ..._sourceBullets(plan),
              const SizedBox(height: FoodietShape.sp16),
              _sectionTitle('참고한 외부 가이드'),
              const SizedBox(height: FoodietShape.sp8),
              _citationCard(
                context,
                title: '한국인 영양섭취기준 (KDRIs, 2020)',
                snippet:
                    '보건복지부·한국영양학회. 성별·연령·활동수준별 일일 에너지 및 매크로 권장 범위.',
                url:
                    'https://www.mohw.go.kr/board.es?mid=a10411010100&bid=0019',
              ),
              _citationCard(
                context,
                title: 'EFSA — Adequate intake of water (2010)',
                snippet:
                    '유럽식품안전청(EFSA) 성인 일일 수분 충분섭취량: 남 2.5L, 여 2.0L (음식 수분 포함).',
                url:
                    'https://www.efsa.europa.eu/en/efsajournal/pub/1459',
              ),
              _citationCard(
                context,
                title: 'USDA FoodData Central',
                snippet:
                    '미국 농무부 식품 영양 데이터베이스. 메뉴별 매크로 추정의 일반 기준.',
                url: 'https://fdc.nal.usda.gov/',
              ),
              const SizedBox(height: FoodietShape.sp16),
              _modelNote(plan?.sourceModel ?? 'gpt-5.4-mini'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.coral50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.coral100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: FoodietColors.coral500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('의료 정보가 아니에요',
                    style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.coral500,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    '이 식단 추천과 물 권장량은 일반 영양 가이드와 사용자가 직접 입력한 정보를 바탕으로 AI 가 제안하는 참고용 정보야. 알레르기·지병·임신/수유·약 복용 등 개인 건강 상태에 따른 식이는 반드시 의사·전문 영양사와 상의해줘.',
                    style: FoodietText.caption.copyWith(
                        color: FoodietColors.warm700, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: FoodietText.title
          .copyWith(color: FoodietColors.warm900, fontWeight: FontWeight.w700));

  List<Widget> _sourceBullets(MealPlan? p) {
    final items = <_Bullet>[];
    items.add(const _Bullet(label: '프로필 입력', value: '성별·키·체중·목표 체중·활동 수준'));
    items.add(const _Bullet(label: '일일 칼로리 목표', value: '내가 설정한 daily_kcal_target 값'));
    if (p != null) {
      items.add(_Bullet(
        label: '폼 입력 — 알레르기',
        value: p.allergies.isEmpty && (p.allergyNotes ?? '').isEmpty
            ? '없음'
            : [...p.allergies, if ((p.allergyNotes ?? '').isNotEmpty) p.allergyNotes!]
                .join(', '),
      ));
      items.add(_Bullet(
        label: '폼 입력 — 냉장고 재료',
        value: p.ingredients.isEmpty && (p.ingredientNotes ?? '').isEmpty
            ? '없음'
            : [...p.ingredients, if ((p.ingredientNotes ?? '').isNotEmpty) p.ingredientNotes!]
                .join(', '),
      ));
      items.add(_Bullet(
          label: '폼 입력 — 식단 스타일',
          value: p.cuisineStyles.isEmpty
              ? '특별한 선호 없음'
              : p.cuisineStyles.join(', ')));
      items.add(_Bullet(
          label: '폼 입력 — 포함 끼니', value: p.mealSlots.join(', ')));
    } else {
      items.add(const _Bullet(
          label: '폼 입력',
          value: '알레르기·냉장고 재료·식단 스타일·포함 끼니 (식단짜기 폼에서 입력)'));
    }
    items.add(const _Bullet(
      label: '물 권장량 계산',
      value:
          '체중 × 32ml 를 기본으로 성별 보정(±5%), 활동도(+200ml/단계), 목표 칼로리(>1600kcal 분 ×0.4ml) 가산. 컵 한 잔 150ml 기준 라운딩.',
    ));
    return items.map((b) => b).toList();
  }

  Widget _citationCard(
    BuildContext ctx, {
    required String title,
    required String snippet,
    required String url,
  }) {
    return Container(
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
              style: FoodietText.caption.copyWith(
                  color: FoodietColors.warm700, height: 1.5)),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              text: url,
              style: FoodietText.caption.copyWith(
                color: FoodietColors.coral500,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelNote(String model) {
    return Text(
      '생성에는 OpenAI $model 모델을 사용했고, 사용자의 프로필·폼 입력 외에는 다른 개인 정보를 모델에 보내지 않아.',
      style: FoodietText.caption
          .copyWith(color: FoodietColors.warm500, height: 1.6),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 5, color: FoodietColors.warm500),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: FoodietText.bodySm.copyWith(
                    color: FoodietColors.warm700, height: 1.5),
                children: [
                  TextSpan(
                      text: '$label · ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
