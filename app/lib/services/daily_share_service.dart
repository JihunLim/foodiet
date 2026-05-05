/// 일자별 식단 → 이미지 → 공유 시트.
///
/// 기획안 §4.7 확장 — PT 친구에게 오늘(또는 과거) 먹은 것을 한 장의 이미지로 전달.
///
/// 흐름:
///   1. 지정 일자 `done` 상태 엔트리만 모아서 signed URL 목록을 만든다.
///   2. `precacheImage` 로 모든 썸네일을 디코드 → ImageCache 에 올린다.
///      (안 올리면 toImage 시점에 네트워크 이미지가 빈 채로 렌더된다.)
///   3. Off-screen [OverlayEntry] 에 [DailyShareCard] 를 `RepaintBoundary` 로
///      붙인다.
///   4. 다음 프레임에 `RenderRepaintBoundary.toImage(pixelRatio: 3.0)` 로 PNG.
///   5. temp 파일로 저장 → `Share.shareXFiles([XFile(path)])`.
///   6. 항상 overlay 제거.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl 이 TextDirection 를 재정의해 Flutter 의 TextDirection.ltr 을 가리기 때문에 hide.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../features/home/daily_share_card.dart';
import '../providers/entries_provider.dart';
import '../providers/profile_provider.dart';

class DailyShareService {
  DailyShareService(this._ref);
  final Ref _ref;

  /// 진행 중이면 중복 실행 방지.
  bool _running = false;

  /// 오늘 카드를 만들어 공유 시트를 연다.
  ///
  /// [context] 는 MaterialApp 이 살아 있는 루트 context 여야 한다 (Overlay + MediaQuery).
  /// 실패하면 [DailyShareException] 을 던진다.
  Future<void> shareToday(BuildContext context) async {
    final entries = await _ref.read(todayEntriesProvider.future);
    if (!context.mounted) return;
    return shareDay(context, DateTime.now(), entries);
  }

  /// 특정 일자의 기록을 공유한다. [entries] 는 상태 무관하게 넘겨도 된다 —
  /// 내부에서 `status == 'done'` 만 필터링한다.
  Future<void> shareDay(
    BuildContext context,
    DateTime date,
    List<Entry> entries,
  ) async {
    if (_running) return;
    _running = true;
    try {
      final doneEntries = entries.where((e) => e.status == 'done').toList()
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      if (doneEntries.isEmpty) {
        // 아예 기록이 없는 경우와 분석 진행 중인 경우를 구분해서 안내.
        throw DailyShareException(entries.isEmpty
            ? '공유할 식사 기록이 없어요. 먼저 사진으로 한 장 남겨보자!'
            : '분석이 아직 진행 중이에요. 조금만 기다렸다가 다시 시도해보세요.');
      }

      final profile = await _ref.read(profileProvider.future);
      final nickname = profile?.nickname ?? '나';
      final target = profile?.dailyKcalTarget ?? 1800;

      // signed URL map (병렬 페칭).
      final photoUrls = <String, String>{};
      await Future.wait(doneEntries.map((e) async {
        try {
          final url = await _ref.read(signedUrlProvider(e.imagePath).future);
          photoUrls[e.imagePath] = url;
        } catch (_) {/* 썸네일 하나 실패해도 나머지는 공유한다 */}
      }));

      if (!context.mounted) {
        throw const DailyShareException('화면이 사라졌어요. 다시 시도해주세요.');
      }

      // 썸네일을 ImageCache 에 올려둔다 (toImage 는 이미 디코드된 것만 그린다).
      await _precacheAll(context, photoUrls.values.toList());

      if (!context.mounted) {
        throw const DailyShareException('화면이 사라졌어요. 다시 시도해주세요.');
      }

      final data = DailyShareCardData(
        date: date,
        nickname: nickname,
        targetKcal: target,
        entries: doneEntries,
        photoUrls: photoUrls,
      );

      final pngBytes = await _renderToPng(context, data);
      final file = await _writeTempPng(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: _buildShareText(date, doneEntries, target, nickname),
        ),
      );
    } finally {
      _running = false;
    }
  }

  String _buildShareText(
    DateTime date,
    List<Entry> entries,
    int target,
    String nickname,
  ) {
    final consumed = entries.fold<int>(
      0,
      (acc, e) => acc + (e.kcalPerPerson ?? 0),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target0 = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target0).inDays;
    final label = diff == 0
        ? '오늘'
        : diff == 1
            ? '어제'
            : DateFormat('M월 d일').format(date);
    return '$label $nickname 식단 · $consumed / $target kcal\n— foodiet 🍓';
  }

  // ─── precache ─────────────────────────────────────────────────────────

  Future<void> _precacheAll(BuildContext context, List<String> urls) async {
    await Future.wait(urls.map((u) async {
      try {
        await precacheImage(NetworkImage(u), context);
      } catch (_) {/* skip broken thumbnails */}
    }));
  }

  // ─── widget → png ─────────────────────────────────────────────────────

  Future<Uint8List> _renderToPng(
      BuildContext context, DailyShareCardData data) async {
    final repaintKey = GlobalKey();
    final completer = Completer<Uint8List>();

    // MediaQuery 상속 — 루트에서 가져온다. off-screen 이지만 MediaQuery 가
    // 없으면 TextField 등 일부 위젯이 assert 를 때린다.
    final mq = MediaQuery.of(context);

    final overlay = Overlay.of(context, rootOverlay: true);

    final entry = OverlayEntry(
      builder: (_) {
        // 화면 바깥에 배치. 음수 좌표 + IgnorePointer + Visibility.maintain… 대신
        // Offstage 는 paint 자체를 스킵하기 때문에 쓸 수 없다. 그래서
        // Transform.translate 로 멀리 옮긴다.
        return Positioned(
          left: -4000,
          top: -4000,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: mq,
              child: Material(
                type: MaterialType.transparency,
                child: RepaintBoundary(
                  key: repaintKey,
                  child: DailyShareCard(data: data),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    try {
      // 두 프레임 기다림:
      //   · 첫 프레임 — 레이아웃 + 페인트.
      //   · 두 번째 — 이미지 디코더가 방금 올라온 캐시를 실제로 그리도록.
      await _waitFrames(3);

      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw const DailyShareException('이미지를 그릴 준비가 안 됐어요.');
      }

      // pixelRatio 3 → 360pt * 3 = 1080px 너비. 카톡/인스타 공유에 충분.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw const DailyShareException('이미지 인코딩에 실패했어요.');
      }
      completer.complete(byteData.buffer.asUint8List());
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    } finally {
      entry.remove();
    }
    return completer.future;
  }

  Future<void> _waitFrames(int count) async {
    for (var i = 0; i < count; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<File> _writeTempPng(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final name = 'foodiet_day_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

class DailyShareException implements Exception {
  const DailyShareException(this.message);
  final String message;
  @override
  String toString() => 'DailyShareException($message)';
}

final dailyShareServiceProvider = Provider<DailyShareService>((ref) {
  return DailyShareService(ref);
});
