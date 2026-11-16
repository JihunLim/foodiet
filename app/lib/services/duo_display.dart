/// iPhone Duo(폴더블) 디스플레이 정보 — 네이티브 `FoodietDuoBridge` 와 짝.
///
/// iOS 27.1 의 `UIHingeInteraction` · `UIView.reservedRegions` 를 EventChannel
/// `foodiet/duo` 로 받는다. 힌지가 없는 기기 · iOS 27.1 미만 · Android 는
/// 항상 [DuoDisplayState.none] (hasHinge = false).
///
/// Flutter 의 `MediaQuery.displayFeatures` 는 iOS 에서 비어 있어서
/// (Flutter 3.41 기준) 직접 브리지한다.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 힌지 상태 — `UIHinge.Status` 와 같은 값.
enum DuoHingeStatus { unknown, closed, partiallyOpen, fullyOpen }

class DuoDisplayState {
  const DuoDisplayState({
    required this.hasHinge,
    this.hingeStatus = DuoHingeStatus.unknown,
    this.hingeAngle,
    this.occlusions = const [],
    this.divisions = const [],
  });

  static const none = DuoDisplayState(hasHinge: false);

  /// 힌지가 있는 기기(= iPhone Duo) 인지.
  final bool hasHinge;
  final DuoHingeStatus hingeStatus;
  final double? hingeAngle;

  /// 카메라 · 상태바처럼 콘텐츠를 가리는 예약 영역 (Flutter 뷰 좌표).
  final List<Rect> occlusions;

  /// 접히는 선 — 반쯤 접혔을 때만 활성.
  final List<Rect> divisions;

  factory DuoDisplayState.fromMap(Map<Object?, Object?> m) {
    List<Rect> rects(Object? raw) => [
          for (final r in (raw as List<Object?>? ?? const []))
            if (r is Map && r['active'] != false)
              Rect.fromLTWH(
                (r['x'] as num).toDouble(),
                (r['y'] as num).toDouble(),
                (r['w'] as num).toDouble(),
                (r['h'] as num).toDouble(),
              ),
        ];
    final status = (m['hingeStatus'] as num?)?.toInt() ?? 0;
    return DuoDisplayState(
      hasHinge: m['hasHinge'] == true,
      hingeStatus: DuoHingeStatus.values[
          status.clamp(0, DuoHingeStatus.values.length - 1)],
      hingeAngle: (m['hingeAngle'] as num?)?.toDouble(),
      occlusions: rects(m['occlusions']),
      divisions: rects(m['divisions']),
    );
  }

  @override
  String toString() => 'DuoDisplayState(hasHinge: $hasHinge, '
      'hinge: $hingeStatus/$hingeAngle, occlusions: $occlusions, '
      'divisions: $divisions)';
}

const _channel = EventChannel('foodiet/duo');

final duoDisplayProvider = StreamProvider<DuoDisplayState>((ref) {
  if (!Platform.isIOS) return Stream.value(DuoDisplayState.none);
  return _channel
      .receiveBroadcastStream()
      .map((e) => DuoDisplayState.fromMap(e as Map<Object?, Object?>))
      .handleError((Object _) {});
});
