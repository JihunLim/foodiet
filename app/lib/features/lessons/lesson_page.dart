/// 레슨 본문 화면 — `/lesson/:slug`.
///
/// 블록(h/p/tip/list) 렌더 + 하단 출처(url_launcher) + "의학적 조언이 아니야" 고지.
/// 처음 데이터가 보이는 순간 한 번 `markLessonRead` (lesson_reads upsert + 이벤트).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/lessons_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/foodie_bubble.dart';

class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends ConsumerState<LessonPage> {
  bool _marked = false;

  void _markOnce(Lesson lesson) {
    if (_marked) return;
    _marked = true;
    // 빌드 중 provider invalidate 를 피하려고 프레임 뒤로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) markLessonRead(ref, lesson);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lessonBySlugProvider(widget.slug));

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('2분 읽기',
            style: FoodietText.title.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: FoodietColors.coral500),
          ),
          error: (_, __) => const _Missing(),
          data: (lesson) {
            if (lesson == null) return const _Missing();
            _markOnce(lesson);
            return _LessonBody(lesson: lesson);
          },
        ),
      ),
    );
  }
}

class _LessonBody extends StatelessWidget {
  const _LessonBody({required this.lesson});
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FoodietShape.sp20, FoodietShape.sp8, FoodietShape.sp20, FoodietShape.sp40),
      children: [
        Text('📖 ${lesson.readMinutes}분',
            style: FoodietText.caption.copyWith(
              color: FoodietColors.leaf700,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: FoodietShape.sp4),
        Text(lesson.title,
            style: FoodietText.h3.copyWith(
              color: FoodietColors.warm900,
              fontWeight: FontWeight.w700,
            )),
        if (lesson.summary.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp8),
          Text(lesson.summary,
              style: FoodietText.body.copyWith(color: FoodietColors.warm500)),
        ],
        const SizedBox(height: FoodietShape.sp20),
        for (final b in lesson.blocks) ...[
          _BlockView(block: b),
          const SizedBox(height: FoodietShape.sp16),
        ],
        const SizedBox(height: FoodietShape.sp8),
        const _Disclaimer(),
        if (lesson.sources.isNotEmpty) ...[
          const SizedBox(height: FoodietShape.sp20),
          Text('참고 자료',
              style: FoodietText.bodySm.copyWith(
                color: FoodietColors.warm700,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: FoodietShape.sp8),
          for (final s in lesson.sources) _SourceRow(source: s),
        ],
      ],
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});
  final LessonBlock block;

  @override
  Widget build(BuildContext context) {
    switch (block.t) {
      case 'h':
        return Padding(
          padding: const EdgeInsets.only(top: FoodietShape.sp4),
          child: Text(block.text,
              style: FoodietText.title.copyWith(
                color: FoodietColors.warm900,
                fontWeight: FontWeight.w700,
              )),
        );
      case 'tip':
        return FoodieBubble(headline: block.text);
      case 'list':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in block.items)
              Padding(
                padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9, right: 10),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: FoodietColors.coral500,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(item,
                          style: FoodietText.body
                              .copyWith(color: FoodietColors.warm700)),
                    ),
                  ],
                ),
              ),
          ],
        );
      default: // 'p'
        return Text(block.text,
            style: FoodietText.body.copyWith(color: FoodietColors.warm700));
    }
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Text(
        '의학적 조언이 아니야. 일반적인 정보라서 사람마다 맞는 방법이 달라. '
        '질환이 있거나 약을 쓰고 있다면 의료진과 먼저 이야기해줘.',
        style: FoodietText.caption.copyWith(color: FoodietColors.warm500),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final LessonSource source;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('링크를 열지 못했어')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 6),
              child: Icon(Icons.open_in_new_rounded,
                  size: 14, color: FoodietColors.coral600),
            ),
            Expanded(
              child: Text(source.label,
                  style: FoodietText.bodySm.copyWith(
                    color: FoodietColors.warm500,
                    decoration: TextDecoration.underline,
                    decorationColor: FoodietColors.warm200,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _Missing extends ConsumerWidget {
  const _Missing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FoodietShape.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('이 글을 찾지 못했어.\n연결을 확인하고 다시 불러와 줘.',
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
