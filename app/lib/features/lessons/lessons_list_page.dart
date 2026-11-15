/// 레슨 목록 — `/lessons`. 인사이트 영양 탭 하단 "읽을거리" 링크에서 진입.
///
/// sort 순으로 전부 보여주고, 읽은 레슨은 ✓ 표시.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/lessons_provider.dart';
import '../../theme/foodiet_tokens.dart';

class LessonsListPage extends ConsumerWidget {
  const LessonsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lessonsProvider);
    final reads = ref.watch(lessonReadsProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('읽을거리',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: FoodietColors.coral500),
          ),
          error: (_, __) => const _Empty(),
          data: (lessons) {
            if (lessons.isEmpty) return const _Empty();
            final readCount = lessons.where((l) => reads.contains(l.id)).length;
            return ListView.separated(
              padding: const EdgeInsets.all(FoodietShape.sp20),
              itemCount: lessons.length + 1,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: FoodietShape.sp12),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Text(
                    '2분이면 읽는 짧은 글이야. ${lessons.length}편 중 $readCount편 읽었어.',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500),
                  );
                }
                final l = lessons[i - 1];
                return _LessonRow(lesson: l, read: reads.contains(l.id));
              },
            );
          },
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.read});
  final Lesson lesson;
  final bool read;

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
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.title,
                        style: FoodietText.body.copyWith(
                          color: FoodietColors.warm900,
                          fontWeight: FontWeight.w700,
                        )),
                    if (lesson.summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(lesson.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FoodietText.bodySm
                              .copyWith(color: FoodietColors.warm500)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FoodietShape.sp12),
              if (read)
                const Icon(Icons.check_circle_rounded,
                    color: FoodietColors.leaf500, size: 22)
              else
                Text('${lesson.readMinutes}분',
                    style: FoodietText.caption.copyWith(
                      color: FoodietColors.leaf700,
                      fontWeight: FontWeight.w700,
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FoodietShape.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('아직 읽을거리를 불러오지 못했어.\n연결을 확인하고 다시 불러와 줘.',
                textAlign: TextAlign.center,
                style:
                    FoodietText.body.copyWith(color: FoodietColors.warm500)),
            const SizedBox(height: FoodietShape.sp12),
            TextButton(
              // lessonsProvider 는 오류 시 빈 목록을 캐시하므로 명시적으로 다시 읽는다.
              onPressed: () {
                ref.invalidate(lessonsProvider);
                ref.invalidate(lessonReadsProvider);
              },
              child: Text('다시 불러오기',
                  style: FoodietText.body.copyWith(
                    color: FoodietColors.coral600,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
