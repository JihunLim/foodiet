/// 즐겨찾기 + 1탭 재기록 (업그레이드 로드맵 [Q2]).
///
/// 자주 먹는 음식을 즐겨찾기로 고정해두면, 홈 화면 "빠른 기록" 칩에서 한 번
/// 탭하는 것만으로 사진/AI 분석 없이 entry 를 즉시 생성한다.
///   - [Favorite] 은 음식명 + 매크로 스냅샷 + 대표 사진 경로를 들고 있다.
///     원본 entry 가 삭제돼도 살아남도록 FK 가 아닌 스냅샷으로 보관한다.
///   - 재기록 entry 는 `source='favorite'`, `status='done'` 으로 만든다.
///   - 사진은 entry 삭제가 storage 파일을 지우므로 경로를 공유하지 않고
///     매번 새 entry 경로(`{uid}/{entryId}.jpg`)로 복사한다.
///
/// DB 의존: `0016_favorites.sql` (favorites 테이블 + entries.source CHECK 확장).
/// 마이그레이션이 아직 적용되지 않았으면 [favoritesProvider] 는 조용히 빈
/// 목록을 반환해 홈 칩이 숨겨질 뿐 크래시는 나지 않는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../supabase/client.dart';
import 'auth_provider.dart';
import 'entries_provider.dart';
import 'supabase_provider.dart';

class Favorite {
  const Favorite({
    required this.id,
    required this.userId,
    required this.name,
    this.imagePath,
    this.kcalTotal,
    this.macros,
    this.mealSlot,
    this.eatingType,
    required this.pinnedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? imagePath;
  final int? kcalTotal;
  final Map<String, dynamic>? macros;
  final String? mealSlot;
  final String? eatingType;
  final DateTime pinnedAt;

  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String,
        imagePath: j['image_path'] as String?,
        kcalTotal: j['kcal_total'] as int?,
        macros: j['macros'] == null
            ? null
            : Map<String, dynamic>.from(j['macros'] as Map),
        mealSlot: j['meal_slot'] as String?,
        eatingType: j['eating_type'] as String?,
        pinnedAt: DateTime.parse(j['pinned_at'] as String).toLocal(),
      );
}

class FavoriteException implements Exception {
  FavoriteException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'FavoriteException($message)';
}

/// 재기록 결과 — 스낵바 "실행취소" 가 새로 만든 entry 를 되돌리는 데 쓴다.
class RecordedFavorite {
  const RecordedFavorite({
    required this.entryId,
    required this.imagePath,
    required this.name,
  });
  final String entryId;
  final String imagePath;
  final String name;
}

const _favSelect =
    'id, user_id, name, image_path, kcal_total, macros, meal_slot, '
    'eating_type, pinned_at';

/// 사용자의 즐겨찾기 목록 (고정 시각 역순). 홈 칩 / 엔트리 상세 토글이 구독.
///
/// 마이그레이션 미적용·일시 오류 시 빈 목록으로 degrade — 홈에서 칩만 숨겨진다.
final AutoDisposeFutureProvider<List<Favorite>> favoritesProvider =
    FutureProvider.autoDispose<List<Favorite>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('favorites')
        .select(_favSelect)
        .eq('user_id', user.id)
        .order('pinned_at', ascending: false)
        .limit(30);
    return (rows as List)
        .map((r) => Favorite.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  } catch (e) {
    // 0016 마이그레이션 미적용(테이블 없음) 또는 일시 네트워크 오류.
    if (kDebugMode) debugPrint('[favorites] load skipped: $e');
    return const [];
  }
});

final favoritesServiceProvider = Provider<FavoritesService>((ref) {
  return FavoritesService(ref.watch(supabaseClientProvider));
});

class FavoritesService {
  FavoritesService(this._sb);
  final SupabaseClient _sb;

  static const _uuid = Uuid();

  /// 엔트리를 즐겨찾기로 고정. 대표 사진을 favorites 경로로 복사해 보관한다.
  Future<Favorite> addFromEntry(Entry entry) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw FavoriteException('로그인이 필요해');

    final name = (entry.title ?? '').trim();
    if (name.isEmpty) {
      throw FavoriteException('아직 이름이 없는 기록은 즐겨찾기할 수 없어');
    }

    final favId = _uuid.v4();
    final favPath = '${user.id}/favorites/$favId.jpg';

    // 1) 대표 사진 스냅샷 복사 (entry 삭제와 수명을 분리).
    await _copyImage(entry.imagePath, favPath);

    // 2) favorites 행 INSERT.
    try {
      final row = await _sb
          .from('favorites')
          .insert({
            'id': favId,
            'user_id': user.id,
            'name': name,
            'image_path': favPath,
            'kcal_total': entry.kcalTotal,
            'macros': entry.macros,
            'meal_slot': entry.mealSlot,
            'eating_type': entry.eatingType,
            'source_entry_id': entry.id,
          })
          .select(_favSelect)
          .single();
      return Favorite.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      // INSERT 실패(고아 사진 방지) — best-effort 삭제 후 rethrow.
      try {
        await _sb.storage
            .from(FoodietSupabase.foodPhotosBucket)
            .remove([favPath]);
      } catch (_) {/* ignore */}
      throw FavoriteException('즐겨찾기 추가에 실패했어', cause: e);
    }
  }

  /// 즐겨찾기 해제 — 행 삭제 + 스냅샷 사진 제거(best-effort).
  Future<void> removeById(String id, {String? imagePath}) async {
    await _sb.from('favorites').delete().eq('id', id);
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        await _sb.storage
            .from(FoodietSupabase.foodPhotosBucket)
            .remove([imagePath]);
      } catch (_) {/* storage 삭제 실패는 무시 — cron 청소에 맡긴다 */}
    }
  }

  /// 즐겨찾기에서 1탭 재기록 — 사진/분석 없이 done 상태 entry 를 즉시 생성.
  ///
  /// 끼니(meal_slot)는 즐겨찾기에 저장된 값이 아니라 **현재 시각**으로 재추론한다
  /// (점심에 고정한 커피를 저녁에 마실 수 있으므로).
  Future<RecordedFavorite> recordFromFavorite(Favorite fav) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw FavoriteException('로그인이 필요해');
    final srcPath = fav.imagePath;
    if (srcPath == null || srcPath.isEmpty) {
      throw FavoriteException('이 즐겨찾기에는 사진이 없어 다시 기록할 수 없어');
    }

    final now = DateTime.now();
    final entryId = _uuid.v4();
    final newPath = '${user.id}/$entryId.jpg';

    // 1) 즐겨찾기 사진을 새 entry 전용 경로로 복사 (경로 공유 금지).
    await _copyImage(srcPath, newPath);

    // 2) entries 행 INSERT — source='favorite', status='done', 매크로 그대로.
    try {
      await _sb.from('entries').insert({
        'id': entryId,
        'user_id': user.id,
        'captured_at': now.toUtc().toIso8601String(),
        'image_path': newPath,
        'source': 'favorite',
        'status': 'done',
        'title': fav.name,
        'kcal_total': fav.kcalTotal,
        'macros': fav.macros,
        'meal_slot': _inferMealSlot(now),
        'eating_type': fav.eatingType,
        'shared_with_count': 1,
      });
    } catch (e) {
      try {
        await _sb.storage
            .from(FoodietSupabase.foodPhotosBucket)
            .remove([newPath]);
      } catch (_) {/* ignore */}
      throw FavoriteException('기록에 실패했어', cause: e);
    }

    return RecordedFavorite(
        entryId: entryId, imagePath: newPath, name: fav.name);
  }

  /// id 로 즐겨찾기를 조회해 재기록 — 위젯 딥링크(`foodiet://widget/log?fav=id`)
  /// 처럼 [Favorite] 객체 없이 id 만 있을 때 쓴다.
  Future<RecordedFavorite> recordFavoriteById(String favId) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw FavoriteException('로그인이 필요해');
    final row = await _sb
        .from('favorites')
        .select(_favSelect)
        .eq('id', favId)
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) throw FavoriteException('즐겨찾기를 찾을 수 없어');
    return recordFromFavorite(
        Favorite.fromJson(Map<String, dynamic>.from(row)));
  }

  /// 재기록 실행취소 — entry 삭제 + 사진 제거. (entry_detail 삭제 흐름과 동일.)
  Future<void> deleteEntry(String entryId, String imagePath) async {
    await _sb.from('entries').delete().eq('id', entryId);
    try {
      await _sb.storage
          .from(FoodietSupabase.foodPhotosBucket)
          .remove([imagePath]);
    } catch (_) {/* ignore */}
  }

  /// storage 서버측 copy. 일부 환경에서 실패하면 download→upload 로 폴백.
  Future<void> _copyImage(String from, String to) async {
    final bucket = _sb.storage.from(FoodietSupabase.foodPhotosBucket);
    try {
      await bucket.copy(from, to);
      return;
    } catch (_) {
      // 폴백: 바이트 다운로드 후 재업로드.
      final bytes = await bucket.download(from);
      await bucket.uploadBinary(
        to,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
          cacheControl: '31536000',
        ),
      );
    }
  }

  /// 현재 시각 기준 끼니 추론 (재기록용 간단 휴리스틱).
  static String _inferMealSlot(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 11) return 'breakfast';
    if (h >= 11 && h < 16) return 'lunch';
    if (h >= 16 && h < 22) return 'dinner';
    return 'late_night';
  }
}
