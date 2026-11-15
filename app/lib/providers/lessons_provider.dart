/// 2분 마이크로 레슨 — 모델·선택 로직·프로바이더.
///
/// 레슨 원고는 DB `lessons` (시드: 0018_lessons_seed.sql) 에 있고, 열람 기록은
/// `lesson_reads(user_id, lesson_id)`. 앱 릴리스 없이 원고를 고치고 열람을 측정한다.
///
/// 노출 규칙(spec F7): 안 읽은 레슨 중 (home-coach focus 매칭 태그) >
/// (패턴 플래그 매칭 태그) > sort 순. 전부 읽었으면 아무것도 보여주지 않는다.
///
/// 0017 미적용·오프라인이면 빈 목록으로 degrade — 홈/상세 화면에서 카드만 숨는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_events.dart';
import 'auth_provider.dart';
import 'supabase_provider.dart';

// ── 모델 ─────────────────────────────────────────────────────────────

/// 본문 블록. `t`: 'h'(소제목) | 'p'(문단) | 'tip'(푸디 팁) | 'list'(목록).
class LessonBlock {
  const LessonBlock({required this.t, this.text = '', this.items = const []});

  final String t;
  final String text;
  final List<String> items;

  static const kinds = {'h', 'p', 'tip', 'list'};

  /// 알 수 없는 형태면 null (렌더에서 건너뜀).
  static LessonBlock? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['t'];
    if (t is! String || !kinds.contains(t)) return null;
    if (t == 'list') {
      final items = _stringList(raw['items']);
      if (items.isEmpty) return null;
      return LessonBlock(t: t, items: items);
    }
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    return LessonBlock(t: t, text: text.trim());
  }
}

class LessonSource {
  const LessonSource({required this.label, required this.url});
  final String label;
  final String url;

  static LessonSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final url = raw['url'];
    if (label is! String || url is! String) return null;
    if (label.trim().isEmpty || !url.startsWith('http')) return null;
    return LessonSource(label: label.trim(), url: url.trim());
  }
}

class Lesson {
  const Lesson({
    required this.id,
    required this.slug,
    required this.title,
    required this.summary,
    required this.blocks,
    required this.tags,
    required this.readMinutes,
    required this.sources,
    required this.sort,
  });

  final String id;
  final String slug;
  final String title;
  final String summary;

  /// DB 컬럼 `body` (jsonb 배열).
  final List<LessonBlock> blocks;
  final List<String> tags;
  final int readMinutes;
  final List<LessonSource> sources;
  final int sort;

  /// 잘못된 형태의 블록/출처는 건너뛰고, id·slug·title 이 없으면 null.
  static Lesson? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final slug = j['slug'];
    final title = j['title'];
    if (id is! String || slug is! String || title is! String) return null;
    if (id.isEmpty || slug.isEmpty) return null;

    final body = j['body'];
    final blocks = body is List
        ? body.map(LessonBlock.fromJson).whereType<LessonBlock>().toList()
        : const <LessonBlock>[];
    final src = j['sources'];
    final sources = src is List
        ? src.map(LessonSource.fromJson).whereType<LessonSource>().toList()
        : const <LessonSource>[];

    return Lesson(
      id: id,
      slug: slug,
      title: title,
      summary: j['summary'] is String ? j['summary'] as String : '',
      blocks: blocks,
      tags: _stringList(j['tags']),
      readMinutes: _int(j['read_minutes']) ?? 2,
      sources: sources,
      sort: _int(j['sort']) ?? 100,
    );
  }
}

List<String> _stringList(Object? raw) => raw is List
    ? [
        for (final v in raw)
          if (v is String && v.trim().isNotEmpty) v.trim(),
      ]
    : const [];

int? _int(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

// ── 선택 로직 (순수 함수) ─────────────────────────────────────────────

/// 인사이트 패턴 키 → 레슨 태그.
const kPatternLessonTags = <String, String>{
  'late_night': '야식',
  'weekend_gap': '주말',
  'snack_share': '간식',
  'sodium_high': '나트륨',
  'partial_days': '기록',
};

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// coachFocus(공백 제거)와 태그가 부분 일치하면 true.
/// focus 가 태그를 포함("단백질챙기기" ⊃ "단백질")하거나, 태그가 2자 이상 focus 를 포함.
bool _focusMatches(String focus, String tag) {
  final t = _squash(tag);
  if (t.isEmpty) return false;
  if (focus.contains(t)) return true;
  return focus.length >= 2 && t.contains(focus);
}

/// 안 읽은 레슨 하나를 고른다. 없으면 null.
///
/// 우선순위: tags 가 coachFocus 와 부분 일치 > patternKeys 매핑 태그 포함 > 없음,
/// 같은 순위 안에서는 sort 오름차순.
/// [readIds] 는 `lesson_reads.lesson_id` (레슨 uuid).
Lesson? pickLesson({
  required List<Lesson> all,
  required Set<String> readIds,
  String? coachFocus,
  List<String> patternKeys = const [],
}) {
  final unread = all.where((l) => !readIds.contains(l.id)).toList();
  if (unread.isEmpty) return null;

  final focus = _squash(coachFocus ?? '');
  final patternTags =
      patternKeys.map((k) => kPatternLessonTags[k]).whereType<String>().toSet();

  int tier(Lesson l) {
    if (focus.isNotEmpty && l.tags.any((t) => _focusMatches(focus, t))) {
      return 0;
    }
    if (l.tags.any(patternTags.contains)) return 1;
    return 2;
  }

  unread.sort((a, b) {
    final c = tier(a).compareTo(tier(b));
    return c != 0 ? c : a.sort.compareTo(b.sort);
  });
  return unread.first;
}

// ── 프로바이더 ───────────────────────────────────────────────────────

const _lessonSelect =
    'id, slug, title, summary, body, tags, read_minutes, sources, sort';

/// 공개된 레슨 전체 (sort 순). 오류 시 빈 목록.
final FutureProvider<List<Lesson>> lessonsProvider =
    FutureProvider<List<Lesson>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('lessons')
        .select(_lessonSelect)
        .eq('published', true)
        .order('sort', ascending: true);
    return (rows as List)
        .map((r) => Lesson.fromJson(Map<String, dynamic>.from(r as Map)))
        .whereType<Lesson>()
        .toList();
  } catch (e) {
    if (kDebugMode) debugPrint('[lessons] load skipped: $e');
    return const [];
  }
});

/// 내가 읽은 레슨 id 집합. 오류 시 빈 집합.
final FutureProvider<Set<String>> lessonReadsProvider =
    FutureProvider<Set<String>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const {};
  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('lesson_reads')
        .select('lesson_id')
        .eq('user_id', user.id);
    return {
      for (final r in rows as List)
        if ((r as Map)['lesson_id'] is String) r['lesson_id'] as String,
    };
  } catch (e) {
    if (kDebugMode) debugPrint('[lesson-reads] load skipped: $e');
    return const {};
  }
});

/// slug 로 레슨 하나. 목록에서 찾는다(12편 규모라 별도 쿼리 불필요).
final lessonBySlugProvider =
    Provider.family<AsyncValue<Lesson?>, String>((ref, slug) {
  return ref.watch(lessonsProvider).whenData((all) {
    for (final l in all) {
      if (l.slug == slug) return l;
    }
    return null;
  });
});

/// [pickLesson] 입력. family 키로 쓰므로 값 비교.
@immutable
class LessonPickArgs {
  const LessonPickArgs({this.coachFocus, this.patternKeys = const []});
  final String? coachFocus;
  final List<String> patternKeys;

  @override
  bool operator ==(Object other) =>
      other is LessonPickArgs &&
      other.coachFocus == coachFocus &&
      listEquals(other.patternKeys, patternKeys);

  @override
  int get hashCode => Object.hash(coachFocus, Object.hashAll(patternKeys));
}

/// 지금 보여줄 레슨 1편 (없으면 null). 로딩·오류 중에도 null.
final suggestedLessonProvider =
    Provider.family<Lesson?, LessonPickArgs>((ref, args) {
  final all = ref.watch(lessonsProvider).valueOrNull;
  final reads = ref.watch(lessonReadsProvider).valueOrNull;
  if (all == null || reads == null) return null;
  return pickLesson(
    all: all,
    readIds: reads,
    coachFocus: args.coachFocus,
    patternKeys: args.patternKeys,
  );
});

/// 레슨을 열었을 때 호출 — lesson_reads upsert + `lesson_opened` 이벤트.
/// 오류는 조용히 무시(읽기를 막으면 안 된다).
Future<void> markLessonRead(WidgetRef ref, Lesson lesson) async {
  final client = ref.read(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) return;
  // await 사이에 화면을 나가면 WidgetRef 는 StateError 를 던진다 → 컨테이너를 미리 잡아
  // 읽음 목록 무효화가 항상 일어나게 한다(안 그러면 홈 카드가 방금 읽은 레슨을 계속 추천).
  final ProviderContainer? container = ref is BuildContext
      ? ProviderScope.containerOf(ref as BuildContext, listen: false)
      : null;
  try {
    await client.from('lesson_reads').upsert(
      {'user_id': uid, 'lesson_id': lesson.id},
      onConflict: 'user_id,lesson_id',
      ignoreDuplicates: true,
    );
    if (container != null) {
      container.invalidate(lessonReadsProvider);
    } else {
      ref.invalidate(lessonReadsProvider);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[lesson-reads] upsert failed: $e');
  }
  AppEvents.log('lesson_opened', {'slug': lesson.slug});
}
