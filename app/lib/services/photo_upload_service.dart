/// 사진 업로드 파이프라인.
///
/// 기획안 §4.1 / §8.2 / §11 / §18.1 #13.
/// 순서:
///   1. XFile 받음 (image_picker)
///   2. 1600px 긴변 리사이즈 + JPEG q80 로 재인코딩 (HEIC 는 현재 fallback=JPEG)
///   3. Storage `food-photos/{user_id}/{entry_id}.jpg` 업로드
///   4. `entries` 테이블에 status='pending' 행 INSERT
///   5. TODO Track 3D — `analyze-entry` Edge Function 호출 트리거
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../supabase/client.dart';

class PhotoUploadResult {
  const PhotoUploadResult({
    required this.entryId,
    required this.imagePath,
  });
  final String entryId;
  final String imagePath;
}

enum PhotoSource { camera, gallery }

class PhotoUploadFailure implements Exception {
  PhotoUploadFailure(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'PhotoUploadFailure($message)';
}

class PhotoUploadService {
  PhotoUploadService(this._sb);
  final SupabaseClient _sb;

  static const _uuid = Uuid();
  static const _maxLongEdgePx = 1600; // §8.2
  static const _jpegQuality = 80; // §8.2 / §18.1 #13

  /// 카메라/갤러리에서 사진 1장을 가져온다. 취소 시 null.
  Future<XFile?> pick({required PhotoSource source}) async {
    final picker = ImagePicker();
    return picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 95, // 압축은 이후 단계에서. 과도한 중복 압축 방지.
      maxWidth: 3000, // 극단적으로 큰 원본 방지 (메모리)
    );
  }

  /// 파일을 읽어 리사이즈 + q80 JPEG 로 재인코딩.
  Future<Uint8List> _transcode(XFile file) async {
    final bytes = await file.readAsBytes();
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: _maxLongEdgePx,
      minHeight: _maxLongEdgePx,
      quality: _jpegQuality,
      format: CompressFormat.jpeg,
    );
    return result;
  }

  /// 전체 파이프라인: 리사이즈 → 업로드 → entries 행 INSERT.
  ///
  /// 호출자는 미리 `image_picker` 로 사진을 고른 뒤 [file] 을 전달한다.
  /// 로그인이 되어 있어야 한다 (RLS 때문에).
  Future<PhotoUploadResult> upload({
    required XFile file,
    required PhotoSource source,
    DateTime? capturedAt,
    String? locale,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw PhotoUploadFailure('로그인이 필요해');
    }

    final entryId = _uuid.v4();
    const ext = 'jpg'; // HEIC→JPEG 로 통일
    final path = '${user.id}/$entryId.$ext';

    // 1. 리사이즈 + q80 JPEG 재인코딩.
    final Uint8List encoded;
    try {
      encoded = await _transcode(file);
    } catch (e) {
      throw PhotoUploadFailure('사진 처리 실패', cause: e);
    }

    if (kDebugMode) {
      debugPrint('[upload] $entryId → ${encoded.lengthInBytes ~/ 1024} KiB');
    }

    // 2. Storage 업로드.
    try {
      await _sb.storage.from(FoodietSupabase.foodPhotosBucket).uploadBinary(
            path,
            encoded,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
              cacheControl: '31536000', // 1년
            ),
          );
    } on StorageException catch (e) {
      throw PhotoUploadFailure('Storage 업로드 실패: ${e.message}', cause: e);
    } catch (e) {
      throw PhotoUploadFailure('Storage 업로드 실패', cause: e);
    }

    // 3. entries row INSERT (status=pending, LLM 필드는 Edge Function 이 채움).
    try {
      await _sb.from('entries').insert({
        'id': entryId,
        'user_id': user.id,
        'captured_at': (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'image_path': path,
        'source': source == PhotoSource.camera ? 'camera' : 'gallery',
        'status': 'pending',
        'locale': locale,
      });
    } catch (e) {
      // Storage 는 업로드됐는데 DB 실패 — 고아 파일 방지를 위해 best-effort 삭제.
      try {
        await _sb.storage
            .from(FoodietSupabase.foodPhotosBucket)
            .remove([path]);
      } catch (_) {/* ignore cleanup failure */}
      throw PhotoUploadFailure('entries 레코드 생성 실패', cause: e);
    }

    // 4. (Track 3D) analyze-entry 트리거.
    // 여기선 fire-and-forget. 실패해도 entries 행은 pending 으로 남아 retry 가능.
    unawaited(_maybeAnalyze(entryId));

    return PhotoUploadResult(entryId: entryId, imagePath: path);
  }

  Future<void> _maybeAnalyze(String entryId) async {
    try {
      await _sb.functions.invoke(
        'analyze-entry',
        body: {'entry_id': entryId},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[upload] analyze-entry skipped: $e');
      // 아직 배포 안 됐거나 실패 — entries 는 pending 으로 남는다.
    }
  }

  /// Storage 경로를 서명 URL 로 변환. (UI 렌더용)
  Future<String> signedUrl(String path, {int expiresIn = 60 * 60}) async {
    return _sb.storage
        .from(FoodietSupabase.foodPhotosBucket)
        .createSignedUrl(path, expiresIn);
  }
}

/// 파일 바이트를 직접 받는 경우 (오프라인 큐 재시도 등).
extension PhotoUploadServiceBytes on PhotoUploadService {
  Future<PhotoUploadResult> uploadBytes({
    required Uint8List bytes,
    required PhotoSource source,
    DateTime? capturedAt,
    String? locale,
  }) async {
    final tmp = await _writeTempFile(bytes);
    try {
      return await upload(
        file: XFile(tmp.path),
        source: source,
        capturedAt: capturedAt,
        locale: locale,
      );
    } finally {
      try {
        await tmp.delete();
      } catch (_) {/* ignore */}
    }
  }

  Future<File> _writeTempFile(Uint8List bytes) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/foodiet_${DateTime.now().microsecondsSinceEpoch}.bin');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
