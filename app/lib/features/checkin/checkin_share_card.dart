/// 주간 체크인 공유 카드 + PNG 공유.
///
/// [DailyShareService] 와 같은 방식: off-screen [OverlayEntry] 에 카드를
/// `RepaintBoundary` 로 붙였다가 `toImage(pixelRatio: 3)` → temp PNG → 공유 시트.
/// 카드에는 kcal·체중 같은 수치를 넣지 않는다 (기록한 날 수·잘한 점·실험만).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// intl 이 TextDirection 을 재정의해 Flutter 의 TextDirection.ltr 을 가리기 때문에 hide.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/weekly_checkin_provider.dart';
import '../../theme/foodiet_tokens.dart';

class CheckinShareData {
  const CheckinShareData({
    required this.weekStart,
    required this.nickname,
    required this.report,
    required this.experiment,
  });

  final DateTime weekStart;
  final String nickname;
  final CheckinReport report;
  final String experiment;
}

/// "M월 d일 ~ M월 d일" (월~일).
String checkinWeekLabel(DateTime weekStart) {
  final end = DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
  final f = DateFormat('M월 d일', 'ko');
  return '${f.format(weekStart)} ~ ${f.format(end)}';
}

class CheckinShareCard extends StatelessWidget {
  const CheckinShareCard({super.key, required this.data});
  final CheckinShareData data;

  static const double cardWidth = 360;

  @override
  Widget build(BuildContext context) {
    final r = data.report;
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: cardWidth,
            padding: const EdgeInsets.all(FoodietShape.sp20),
            decoration: BoxDecoration(
              color: FoodietColors.cream00,
              borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('🍓 foodiet',
                        style: FoodietText.title.copyWith(
                            color: FoodietColors.coral500,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(width: FoodietShape.sp8),
                    Flexible(
                      child: Text(checkinWeekLabel(data.weekStart),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.warm500, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: FoodietShape.sp16),
                Text('${data.nickname}의 한 주 돌아보기',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: FoodietShape.sp8),
                    Expanded(
                      child: Text(r.headline,
                          style: FoodietText.h3.copyWith(
                              color: FoodietColors.warm900,
                              fontWeight: FontWeight.w700,
                              fontSize: 22)),
                    ),
                  ],
                ),
                if (r.daysLogged != null) ...[
                  const SizedBox(height: FoodietShape.sp8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: FoodietColors.leaf100,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('7일 중 ${r.daysLogged}일 기록',
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.leaf700,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                const SizedBox(height: FoodietShape.sp16),
                ...r.wins.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('✓ ',
                              style: TextStyle(
                                  color: FoodietColors.leaf700,
                                  fontWeight: FontWeight.w700)),
                          Expanded(
                            child: Text(w,
                                style: FoodietText.bodySm.copyWith(
                                    color: FoodietColors.warm700)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: FoodietShape.sp12),
                Container(
                  padding: const EdgeInsets.all(FoodietShape.sp16),
                  decoration: BoxDecoration(
                    color: FoodietColors.coral50,
                    border: Border.all(color: FoodietColors.coral100),
                    borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('이번 주 실험',
                          style: FoodietText.caption.copyWith(
                              color: FoodietColors.coral600,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(data.experiment,
                          style: FoodietText.body.copyWith(
                              color: FoodietColors.warm900,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: FoodietShape.sp16),
                Text('푸디랑 매주 2분 돌아보기 — foodiet',
                    textAlign: TextAlign.center,
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── PNG → 공유 시트 ───────────────────────────────────────────────────

bool _sharing = false;

/// 카드를 PNG 로 그려 공유 시트를 연다. 진행 중 재호출은 무시.
/// [context] 는 Overlay·MediaQuery 가 있는 화면 context.
Future<void> shareCheckinCard(BuildContext context, CheckinShareData data) async {
  if (_sharing) return;
  _sharing = true;
  try {
    final bytes = await _renderToPng(context, data);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/foodiet_checkin_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: '${data.nickname}의 이번 주 실험: ${data.experiment}\n— foodiet 🍓',
    ));
  } finally {
    _sharing = false;
  }
}

Future<Uint8List> _renderToPng(
    BuildContext context, CheckinShareData data) async {
  final key = GlobalKey();
  final mq = MediaQuery.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -4000,
      top: -4000,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: mq,
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(
              key: key,
              child: CheckinShareCard(data: data),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('share card not laid out');
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) throw StateError('png encode failed');
    return byteData.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
