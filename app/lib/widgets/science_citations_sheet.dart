/// 인사이트 화면의 산출 근거 + 의료 면책 시트.
///
/// 기획안 §4.5 / §4.7 의 칼로리·체중 계산은 모두 검증된 공식·문헌에 기반하지만,
/// 의학 조언이 아니라 일반 정보임을 분명히 해야 한다.
///
/// 노출 위치:
///   - 인사이트 탭 (체중 / 영양) 하단 "📚 참고 자료" 링크
/// 표시 내용:
///   - 의료 면책 한 줄
///   - 4개 산출 근거 + 출처 URL (Mifflin-St Jeor, ACSM, NIH, AND)
///
/// App Store 1.4.1 (Physical Harm) — health/medical recommendation 에는 인용
/// 출처가 명시돼야 한다는 가이드라인 대응.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/foodiet_tokens.dart';

class _Citation {
  const _Citation({
    required this.title,
    required this.snippet,
    required this.source,
    required this.url,
  });
  final String title;
  final String snippet;
  final String source;
  final String url;
}

const _citations = <_Citation>[
  _Citation(
    title: '기초대사량 (BMR) 공식',
    snippet:
        '체중·키·나이·성별로 휴식 시 에너지 소비량을 추정. foodiet 의 일일 권장 칼로리 계산의 출발점.',
    source:
        'Mifflin MD et al. "A new predictive equation for resting energy expenditure in healthy individuals." Am J Clin Nutr 1990;51(2):241–7.',
    url: 'https://pubmed.ncbi.nlm.nih.gov/2305711/',
  ),
  _Citation(
    title: '활동계수 (TDEE multiplier)',
    snippet:
        'BMR 에 1.2 (앉아서) ~ 1.9 (매우 활동적) 의 계수를 곱해 총 일일 에너지 소비량(TDEE) 을 추정.',
    source:
        'American College of Sports Medicine (ACSM). ACSM\'s Guidelines for Exercise Testing and Prescription, 11th ed., 2021.',
    url: 'https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription',
  ),
  _Citation(
    title: '체지방 1kg ≈ 7,700 kcal',
    snippet: '체중 변화 예측에 쓰이는 표준 환산. 1주 0.5–1kg 감량을 안전 범위로 본다.',
    source:
        'NIH National Heart, Lung, and Blood Institute. "Aim for a Healthy Weight" (2013).',
    url: 'https://www.nhlbi.nih.gov/health/educational/lose_wt/',
  ),
  _Citation(
    title: '안전 최저 칼로리 (남 1500 / 여 1200 kcal/일)',
    snippet:
        '의학적 감독 없이 임의로 더 낮추면 영양 결핍 위험. 앱은 사용자가 설정한 적자가 이 선을 넘으면 자동으로 잘라준다.',
    source:
        'Academy of Nutrition and Dietetics. Position on Adult Weight Management.',
    url: 'https://www.eatrightpro.org/practice/position-and-practice-papers',
  ),
];

Future<void> showScienceCitationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: FoodietColors.cream00,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(FoodietShape.radiusLg),
      ),
    ),
    builder: (_) => const _ScienceCitationsSheet(),
  );
}

class _ScienceCitationsSheet extends StatelessWidget {
  const _ScienceCitationsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(
              FoodietShape.sp20, FoodietShape.sp8, FoodietShape.sp20, 80),
          child: ListView(
            controller: scroll,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: FoodietShape.sp12),
                  decoration: BoxDecoration(
                    color: FoodietColors.cream100,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('산출 근거 · 참고 자료',
                  style: FoodietText.h3
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: FoodietShape.sp4),
              Text(
                'foodiet 의 칼로리·체중 계산이 어떤 공식과 문헌에 기반했는지.',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500),
              ),
              const SizedBox(height: FoodietShape.sp16),
              const _DisclaimerBox(),
              const SizedBox(height: FoodietShape.sp16),
              for (final c in _citations) ...[
                _CitationCard(citation: c),
                const SizedBox(height: FoodietShape.sp12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclaimerBox extends StatelessWidget {
  const _DisclaimerBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.coral50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.coral100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: FoodietColors.coral700, size: 18),
              const SizedBox(width: 8),
              Text('의료 정보가 아니에요',
                  style: FoodietText.body.copyWith(
                    color: FoodietColors.coral700,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '여기 표시되는 칼로리 · 체중 예측 · TDEE 는 일반적인 공식과 평균값에 기반한 '
            '추정치야. 개인의 건강 상태나 의학적 조언을 대체하지 않으니 다이어트 · '
            '운동 계획을 세울 땐 주치의나 영양사와 상담하길 권해.',
            style: FoodietText.bodySm
                .copyWith(color: FoodietColors.warm700, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _CitationCard extends StatelessWidget {
  const _CitationCard({required this.citation});
  final _Citation citation;

  Future<void> _open() async {
    final uri = Uri.parse(citation.url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(FoodietShape.sp16),
        decoration: BoxDecoration(
          color: FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.cream100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(citation.title,
                style: FoodietText.body.copyWith(
                  color: FoodietColors.warm900,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(citation.snippet,
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm700, height: 1.4)),
            const SizedBox(height: FoodietShape.sp8),
            Text(citation.source,
                style: FoodietText.caption.copyWith(
                  color: FoodietColors.warm500,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                )),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.open_in_new_rounded,
                    color: FoodietColors.coral500, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    citation.url,
                    style: FoodietText.caption.copyWith(
                      color: FoodietColors.coral500,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 인사이트 페이지 하단에 노출되는 작은 trigger 버튼.
class ScienceCitationsLink extends StatelessWidget {
  const ScienceCitationsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => showScienceCitationsSheet(context),
        icon: const Icon(Icons.menu_book_rounded,
            color: FoodietColors.warm500, size: 16),
        label: Text(
          '📚 산출 근거 · 참고 자료',
          style: FoodietText.bodySm.copyWith(
            color: FoodietColors.warm500,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
