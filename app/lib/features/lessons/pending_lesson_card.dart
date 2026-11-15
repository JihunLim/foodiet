/// 분석 대기 중 기록 상세(pending 배너 아래) 에 띄우는 레슨 1장.
///
/// 안 읽은 레슨이 없거나 로딩·오류면 아무것도 그리지 않는다(SizedBox.shrink).
/// home-coach 를 새로 호출하지 않도록 focus·패턴은 호출 쪽이 넘겨줄 때만 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/lessons_provider.dart';
import '../../theme/foodiet_tokens.dart';
import 'lesson_card.dart';

class PendingLessonCard extends ConsumerWidget {
  const PendingLessonCard({
    super.key,
    this.coachFocus,
    this.patternKeys = const [],
    this.padding = const EdgeInsets.only(top: FoodietShape.sp12),
  });

  final String? coachFocus;
  final List<String> patternKeys;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = ref.watch(suggestedLessonProvider(
      LessonPickArgs(coachFocus: coachFocus, patternKeys: patternKeys),
    ));
    if (lesson == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: LessonCard(lesson: lesson, label: '기다리는 동안 2분 읽기'),
    );
  }
}
