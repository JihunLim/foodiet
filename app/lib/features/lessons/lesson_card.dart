/// "오늘의 2분 읽기" 카드 — 홈 콘텐츠 슬롯·기록 상세에서 레슨 1편을 소개.
///
/// 탭 → `/lesson/:slug`. 어떤 레슨을 보여줄지는 호출 쪽이 [pickLesson] /
/// `suggestedLessonProvider` 로 정한다.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../providers/lessons_provider.dart';
import '../../theme/foodiet_tokens.dart';

class LessonCard extends StatelessWidget {
  const LessonCard({super.key, required this.lesson, this.label = '오늘의 2분 읽기'});

  final Lesson lesson;

  /// 카드 상단 작은 라벨.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        onTap: () => context.push('/lesson/${lesson.slug}'),
        child: Ink(
          padding: const EdgeInsets.all(FoodietShape.sp16),
          decoration: BoxDecoration(
            color: FoodietColors.cream50,
            borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            border: Border.all(color: FoodietColors.cream100),
            boxShadow: FoodietShape.shadowCard,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FoodietColors.leaf100,
                  borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                ),
                alignment: Alignment.center,
                child: const Text('📖', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label · ${lesson.readMinutes}분',
                      style: FoodietText.caption.copyWith(
                        color: FoodietColors.leaf700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lesson.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FoodietText.body.copyWith(
                        color: FoodietColors.warm900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (lesson.summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        lesson.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FoodietText.bodySm
                            .copyWith(color: FoodietColors.warm500),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              const Icon(Icons.chevron_right_rounded,
                  color: FoodietColors.warm500),
            ],
          ),
        ),
      ),
    );
  }
}
