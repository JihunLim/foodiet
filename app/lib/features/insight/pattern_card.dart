/// 인사이트 영양 탭 — "푸디가 찾은 패턴" 카드.
///
/// `InsightSummary.patternFlags` 중 임계값을 넘은 항목만 한 줄씩 보여준다.
/// 기록이 적으면(3일 미만) 결론을 내지 않고 안내 문구만 둔다.
library;

import 'package:flutter/material.dart';

import '../../providers/insight_provider.dart';
import '../../theme/foodiet_tokens.dart';

class PatternCard extends StatelessWidget {
  const PatternCard({super.key, required this.summary});
  final InsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final flags = summary.patternFlags;
    final sparse = summary.recordDays < kPatternMinRecordDays;

    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🍓', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('푸디가 찾은 패턴',
                    style: FoodietText.title
                        .copyWith(color: FoodietColors.warm900)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${summary.window.label} 기록 기준',
              style:
                  FoodietText.caption.copyWith(color: FoodietColors.warm500)),
          const SizedBox(height: FoodietShape.sp12),
          if (flags.isEmpty)
            _EmptyLine(
              text: sparse
                  ? '기록이 $kPatternMinRecordDays일 이상 쌓이면 패턴을 찾아볼게.'
                  : '아직 뚜렷한 패턴이 없어. 지금처럼 기록해줘 🌱',
            )
          else
            for (int i = 0; i < flags.length; i++) ...[
              if (i > 0) const SizedBox(height: FoodietShape.sp8),
              _FlagRow(flag: flags[i]),
            ],
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.flag});
  final PatternFlag flag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: FoodietShape.sp12, vertical: 10),
      decoration: BoxDecoration(
        color: FoodietColors.coral50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.coral100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(flag.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: FoodietShape.sp8),
          Expanded(
            child: Text(flag.text,
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm700, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: FoodietShape.sp12, vertical: 10),
      decoration: BoxDecoration(
        color: FoodietColors.cream00,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Text(text,
          style: FoodietText.bodySm.copyWith(color: FoodietColors.warm500)),
    );
  }
}
