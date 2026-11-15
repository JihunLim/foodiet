import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/providers/lessons_provider.dart';

Lesson _l(String id, String slug, List<String> tags, int sort) => Lesson(
      id: id,
      slug: slug,
      title: slug,
      summary: '',
      blocks: const [],
      tags: tags,
      readMinutes: 2,
      sources: const [],
      sort: sort,
    );

void main() {
  // protein·late-night 은 일부러 sort 가 뒤쪽 — focus/패턴 우선순위가 sort 를 이기는지 확인.
  final all = <Lesson>[
    _l('id-fiber', 'fiber', ['식이섬유', '채소'], 10),
    _l('id-energy', 'energy-density', ['포만감', '간식'], 20),
    _l('id-weight', 'weight-trend', ['체중변동', '기록'], 30),
    _l('id-plateau', 'plateau', ['정체기', '기록'], 40),
    _l('id-protein', 'protein', ['단백질'], 50),
    _l('id-late', 'late-night', ['야식'], 60),
  ];

  group('pickLesson', () {
    test('focus 단백질 → protein (sort 보다 우선)', () {
      final l = pickLesson(all: all, readIds: {}, coachFocus: '단백질');
      expect(l?.slug, 'protein');
    });

    test('focus 공백 제거 + 부분 일치 ("단백질 챙기기")', () {
      final l = pickLesson(all: all, readIds: {}, coachFocus: ' 단백질 챙기기 ');
      expect(l?.slug, 'protein');
    });

    test('읽은 레슨은 제외', () {
      final l = pickLesson(
          all: all, readIds: {'id-protein'}, coachFocus: '단백질');
      expect(l?.slug, 'fiber'); // focus 매칭이 없으니 sort 순
    });

    test('전부 읽었으면 null', () {
      final l = pickLesson(
          all: all, readIds: all.map((e) => e.id).toSet(), coachFocus: '단백질');
      expect(l, isNull);
    });

    test('patternKeys late_night → late-night', () {
      final l = pickLesson(
          all: all, readIds: {}, patternKeys: const ['late_night']);
      expect(l?.slug, 'late-night');
    });

    test('focus 매칭이 패턴 매칭보다 우선', () {
      final l = pickLesson(
          all: all,
          readIds: {},
          coachFocus: '단백질',
          patternKeys: const ['late_night']);
      expect(l?.slug, 'protein');
    });

    test('partial_days → 기록 태그 중 sort 가 앞선 weight-trend', () {
      final l = pickLesson(
          all: all, readIds: {}, patternKeys: const ['partial_days']);
      expect(l?.slug, 'weight-trend');
    });

    test('focus·패턴 없음 → sort 오름차순 첫 번째', () {
      expect(pickLesson(all: all, readIds: {})?.slug, 'fiber');
      expect(pickLesson(all: all, readIds: {}, coachFocus: '  ')?.slug,
          'fiber');
    });

    test('빈 목록 → null', () {
      expect(pickLesson(all: const [], readIds: {}), isNull);
    });
  });

  group('Lesson.fromJson', () {
    test('정상 행 — body 를 blocks 로, sources 파싱', () {
      final l = Lesson.fromJson({
        'id': 'u1',
        'slug': 'protein',
        'title': '단백질',
        'summary': '요약',
        'body': [
          {'t': 'h', 'text': '제목'},
          {'t': 'p', 'text': '본문'},
          {'t': 'list', 'items': ['a', 'b']},
          {'t': 'tip', 'text': '팁'},
        ],
        'tags': ['단백질'],
        'read_minutes': 2,
        'sources': [
          {'label': 'Leidy 2015', 'url': 'https://pubmed.ncbi.nlm.nih.gov/25926512/'}
        ],
        'sort': 10,
      });
      expect(l, isNotNull);
      expect(l!.blocks.length, 4);
      expect(l.blocks[2].items, ['a', 'b']);
      expect(l.sources.single.url, contains('25926512'));
      expect(l.readMinutes, 2);
    });

    test('잘못된 형태 — 예외 없이 알 수 없는 블록·소스는 건너뜀', () {
      final l = Lesson.fromJson({
        'id': 'u2',
        'slug': 'x',
        'title': 'x',
        'body': [
          {'t': 'video', 'text': '?'},
          'oops',
          {'t': 'p', 'text': 3},
          {'t': 'list', 'items': 'notalist'},
          {'t': 'p', 'text': 'ok'},
        ],
        'tags': 'notalist',
        'sources': [
          {'label': 1},
          {'label': 'ok', 'url': 'https://example.org'}
        ],
        'read_minutes': '2',
        'sort': null,
      });
      expect(l, isNotNull);
      expect(l!.blocks.map((b) => b.text), ['ok']);
      expect(l.tags, isEmpty);
      expect(l.sources.length, 1);
      expect(l.readMinutes, 2);
    });

    test('id/slug 없음 → null', () {
      expect(Lesson.fromJson({'title': 'x'}), isNull);
    });
  });
}
