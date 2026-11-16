/// 화면 크기 적응 레이아웃 (iPhone Duo · iPad · 가로 모드).
///
/// Apple HIG "Designing for iPhone Duo" 원칙을 Flutter 쪽에서 따르기 위한 공용 헬퍼.
///   - 화면 크기 고정값 · 레터박스 대신 **사용 가능한 폭에 맞춰 늘어나는** 레이아웃.
///   - 바깥 디스플레이 = compact width, 안쪽 디스플레이 = regular width.
///     같은 화면이 Split View · 접힘 · 회전에 따라 수시로 크기가 바뀐다.
///   - 배경 · 앱바 · 하단 바는 화면 끝까지, 스크롤 콘텐츠만 읽기 좋은 폭으로 inset.
///   - 좌우 safe area 는 비대칭일 수 있다 (바깥 디스플레이의 카메라 / 세로 상태바,
///     Split View). 한쪽 inset 을 두 배 하지 말고 좌우를 각각 쓴다.
///
/// 참고로 iOS 27.1 Duo 시뮬레이터 실측: 바깥 466×678pt, 안쪽 669×951pt
/// (안쪽 가로 951×669 에서 safe area 는 오른쪽 세로 상태바 84 · 아래 34).
/// 아래 상수는 이 값들에 맞춘 게 아니라 기기와 무관하게 폭 기준으로만 동작한다.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'foodiet_tokens.dart';

class FoodietLayout {
  FoodietLayout._();

  /// compact ↔ regular 폭 경계 (Material/Apple 공통 관례 600).
  static const double regularWidth = 600;

  /// 한 줄 컬럼의 최대 콘텐츠 폭. 이보다 넓으면 좌우 여백이 늘어난다.
  static const double readableMaxWidth = 640;

  /// 2단 레이아웃이 켜지는 최소 콘텐츠 폭 (안쪽 디스플레이 가로, iPad).
  static const double twoColumnMinWidth = 720;

  /// 2단 레이아웃의 최대 콘텐츠 폭.
  static const double twoColumnMaxWidth = 960;

  /// 2단 레이아웃 컬럼 사이 간격.
  static const double columnGap = FoodietShape.sp24;

  /// [width] 영역 안에서 콘텐츠를 [maxContent] 폭으로 가운데 정렬할 때의
  /// 좌우 여백. 최소 [min] 은 항상 보장.
  static double gutter(
    double width, {
    double min = FoodietShape.sp20,
    double maxContent = readableMaxWidth,
  }) =>
      math.max(min, (width - maxContent) / 2);

  /// 여백 [min] 을 뺀 콘텐츠 폭이 2단을 쓸 만큼 넓은지.
  static bool useTwoColumns(double width, {double min = FoodietShape.sp20}) =>
      width - min * 2 >= twoColumnMinWidth;

  /// 폭 [width] 화면에서 좌우 safe area([insetLeft] / [insetRight]) 를 뺀
  /// 영역의 가운데에 [childWidth] 짜리 요소를 놓을 때의 x 좌표(왼쪽 끝).
  ///
  /// 좌우 inset 이 같으면 화면 정중앙과 같다. 다르면 (Duo 바깥 디스플레이,
  /// Split View) safe area 안쪽 영역의 중앙으로 옮겨간다.
  static double centerOffsetWithin({
    required double width,
    required double childWidth,
    double insetLeft = 0,
    double insetRight = 0,
  }) =>
      insetLeft + (width - insetLeft - insetRight - childWidth) / 2;
}

/// iPhone Duo 의 상태바 · 카메라 띠가 붙은 쪽.
enum DuoStripSide { none, left, right }

/// iPhone Duo 에서 화면 좌/우 가장자리에 붙은 예약 영역(상태바 · 카메라 띠).
///
/// 실측(iOS 27.1): 접은 바깥 화면 457×678 에선 오른쪽 (373, 0, 84×174),
/// 펼친 가로 951×669 에선 (867, 0, 84×124). 그런데 safe area 는 이 띠 폭(84)을
/// **화면 전체 높이**에 걸쳐 오른쪽 inset 으로 잡아서, 띠 아래쪽이 통째로 빈다.
/// 값은 기기 · 자세마다 다르므로 상수 대신 매번 예약 영역에서 계산한다.
class DuoStrip {
  const DuoStrip(this.side, this.rect);

  static const none = DuoStrip(DuoStripSide.none, null);

  final DuoStripSide side;
  final Rect? rect;

  double get width => rect?.width ?? 0;

  /// [occlusions] 중 좌/우 가장자리에 닿는 가장 큰 영역을 띠로 본다.
  /// 위 가장자리에만 붙은 영역(예: 펼친 세로의 상태바)은 띠가 아니다.
  static DuoStrip from({required Size size, required List<Rect> occlusions}) {
    var best = none;
    var bestArea = 0.0;
    for (final r in occlusions) {
      final DuoStripSide side;
      if (r.right >= size.width - 1 && r.left > size.width / 2) {
        side = DuoStripSide.right;
      } else if (r.left <= 1 && r.right < size.width / 2) {
        side = DuoStripSide.left;
      } else {
        continue;
      }
      // 가로로 넓적한(위쪽 상태바 같은) 영역은 제외 — 세로 띠만.
      if (r.height < r.width) continue;
      final area = r.width * r.height;
      if (area > bestArea) {
        bestArea = area;
        best = DuoStrip(side, r);
      }
    }
    return best;
  }

  /// 띠 쪽 safe area 를 띠 폭만큼 걷어낸 padding — 본문이 화면 끝까지 쓰도록.
  EdgeInsets bodyPadding(EdgeInsets p) {
    switch (side) {
      case DuoStripSide.right:
        return p.copyWith(right: math.max(0.0, p.right - width));
      case DuoStripSide.left:
        return p.copyWith(left: math.max(0.0, p.left - width));
      case DuoStripSide.none:
        return p;
    }
  }
}

/// iPhone Duo 플로팅 메뉴 모드에서 탭 화면들이 비켜야 할 여백.
///
/// 하단 바 모드(일반 기기)에선 위젯 트리에 없으므로 모두 0.
class DuoChromeInsets extends InheritedWidget {
  const DuoChromeInsets({
    super.key,
    this.appBarLeft = 0,
    this.appBarRight = 0,
    this.scrollBottom = 0,
    required super.child,
  });

  /// 앱바 액션 · 탭이 상태바 띠를 피하도록 줄 좌/우 여백.
  final double appBarLeft;
  final double appBarRight;

  /// 스크롤 끝에서 마지막 항목이 플로팅 메뉴 위로 올라올 수 있게 더할 아래 여백.
  final double scrollBottom;

  static DuoChromeInsets? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DuoChromeInsets>();

  static double appBarLeftOf(BuildContext context) =>
      _of(context)?.appBarLeft ?? 0;

  static double appBarRightOf(BuildContext context) =>
      _of(context)?.appBarRight ?? 0;

  static double scrollBottomOf(BuildContext context) =>
      _of(context)?.scrollBottom ?? 0;

  @override
  bool updateShouldNotify(DuoChromeInsets oldWidget) =>
      appBarLeft != oldWidget.appBarLeft ||
      appBarRight != oldWidget.appBarRight ||
      scrollBottom != oldWidget.scrollBottom;
}

/// 부모 폭에 맞춘 좌우 여백을 [builder] 에 넘겨준다.
///
/// 스크롤 뷰 자체는 화면 끝까지 두고 `padding` 으로만 가운데 정렬하므로,
/// 넓은 화면의 좌우 여백에서도 스크롤 제스처가 그대로 먹는다.
class ReadableGutter extends StatelessWidget {
  const ReadableGutter({
    super.key,
    this.min = FoodietShape.sp20,
    this.maxContent = FoodietLayout.readableMaxWidth,
    required this.builder,
  });

  final double min;
  final double maxContent;
  final Widget Function(BuildContext context, double gutter) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => builder(
        context,
        FoodietLayout.gutter(
          constraints.maxWidth,
          min: min,
          maxContent: maxContent,
        ),
      ),
    );
  }
}

/// 스크롤 밖에 고정된 요소(하단 버튼 · 입력창 등)를 읽기 폭으로 제한.
///
/// 배경은 부모가 칠하고, 자식만 가운데 [maxWidth] 폭으로 놓인다.
/// 부모 폭이 [maxWidth] 이하(일반 iPhone, Duo 세로)면 자식을 그대로 돌려줘
/// 기존 레이아웃 제약(tight 폭)이 전혀 바뀌지 않는다.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    this.maxWidth = FoodietLayout.readableMaxWidth + FoodietShape.sp20 * 2,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) return child;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}
