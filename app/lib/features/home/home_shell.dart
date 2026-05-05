/// 홈 5-탭 Shell — 하단 TabBar + 중앙 FAB(카메라 반달 아치).
///
/// 기획안 §6 IA. StatefulShellRoute.indexedStack 으로 탭 별 네비게이션 스택 유지.
///
/// Phase G-2 (MVP UX 개선):
///   - 중앙 FAB 를 누르면 위쪽 반달(top-half donut) 이 피어난다.
///     왼쪽 절반 = 카메라, 오른쪽 절반 = 앨범.
///   - 두 가지 선택 방법:
///       1) 탭: FAB → 아치 펼쳐짐 → 원하는 반쪽을 탭 → 선택
///       2) 드래그: FAB 누른 채 왼쪽/오른쪽 대각선으로 슬라이드 → 손 떼면 즉시 선택
///   - 드래그 중엔 해당 반쪽이 코랄 틴트로 강조되고 selectionClick 햅틱.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/entries_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/photo_upload_service.dart';
import '../../theme/foodiet_tokens.dart';

// ─── 아치 도형 파라미터 ────────────────────────────────────────────────
// 원본 사이즈 복귀 — 아이콘 + 라벨이 함께 들어가는 충분한 두께.
const double _kArcOuterR = 92.0;
const double _kArcInnerR = 38.0;
const Offset _kArcCenter = Offset(_kArcOuterR, _kArcOuterR);

// 아이콘/라벨 크기.
const double _kArcIconSize = 26.0;
const double _kArcLabelFontSize = 10.0;
const double _kArcLabelBoxW = 56.0;
const double _kArcLabelBoxH = 48.0;

enum _Side { left, right }

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  final GlobalKey _fabKey = GlobalKey();
  OverlayEntry? _overlay;

  /// 드래그 중 highlight 되는 반쪽. null = 강조 없음.
  final ValueNotifier<_Side?> _hoverSide = ValueNotifier<_Side?>(null);

  Offset? _dragStartGlobal;
  bool _dragActive = false;
  bool _picking = false; // image_picker 동시 실행 방지

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _anim = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _ctrl.dispose();
    _hoverSide.dispose();
    super.dispose();
  }

  void _go(int i) {
    widget.navigationShell.goBranch(
      i,
      initialLocation: i == widget.navigationShell.currentIndex,
    );
  }

  // ─── pointer events on main FAB ───────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _dragStartGlobal = e.position;
    _dragActive = false;
    if (_overlay == null) _open();
  }

  void _onPointerMove(PointerMoveEvent e) {
    final start = _dragStartGlobal;
    if (start == null) return;
    final delta = e.position - start;
    if (!_dragActive && delta.distance > 6) {
      _dragActive = true;
    }
    if (_dragActive) {
      final next = _sideForDelta(delta);
      if (next != _hoverSide.value) {
        _hoverSide.value = next;
        if (next != null) HapticFeedback.selectionClick();
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final start = _dragStartGlobal;
    _dragStartGlobal = null;
    if (start == null) return;
    final delta = e.position - start;
    final wasDragging = _dragActive;
    _dragActive = false;

    _Side? chosen;
    // 드래그 거리가 충분하고 방향이 유효하면 즉시 선택.
    if (wasDragging && delta.distance > 28) {
      chosen = _sideForDelta(delta);
    }
    _hoverSide.value = null;

    if (chosen != null) {
      _pick(chosen == _Side.left ? PhotoSource.camera : PhotoSource.gallery);
      return;
    }
    // 단순 탭 → 아치는 열린 채로 유지. 사용자가 반쪽을 탭하거나 scrim 을 탭할 때까지.
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _dragStartGlobal = null;
    _dragActive = false;
    _hoverSide.value = null;
  }

  /// 드래그 벡터 방향으로 어느 쪽 반쪽을 가리키는지 판정.
  _Side? _sideForDelta(Offset delta) {
    if (delta.distance < 16) return null;
    if (delta.dy > 20) return null; // FAB 아래로 빠짐 → 선택 아님
    if (delta.dx.abs() < 12) return null; // 거의 수직 → dead zone
    return delta.dx < 0 ? _Side.left : _Side.right;
  }

  // ─── open / close ─────────────────────────────────────────────────────

  void _open() {
    if (_overlay != null) return;
    HapticFeedback.selectionClick();
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
    _ctrl.forward();
  }

  Future<void> _close() async {
    if (_overlay == null) return;
    await _ctrl.reverse();
    _removeOverlay();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  // ─── pick + upload ────────────────────────────────────────────────────

  Future<void> _pick(PhotoSource source) async {
    if (_picking) return;
    _picking = true;
    HapticFeedback.mediumImpact();
    // 아치는 백그라운드로 닫고, picker 를 바로 띄운다.
    unawaited(_close());

    final svc = ref.read(photoUploadServiceProvider);
    final profile = ref.read(profileProvider).valueOrNull;
    final locale = profile?.locale ?? 'ko';

    try {
      final file = await svc.pick(source: source);
      if (file == null || !mounted) return;

      _showSnack('기록 중이야, 곧 분석 결과가 떠 ✨');

      unawaited(
        svc
            .upload(file: file, source: source, locale: locale)
            .then((_) {
              if (!mounted) return;
              ref.invalidate(todayEntriesProvider);
              ref.invalidate(recentEntriesProvider);
            })
            .catchError((Object e) {
              if (!mounted) return;
              _showSnack('업로드 실패: ${_shortError(e)}');
            }),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'camera_access_denied' ||
              e.code == 'photo_access_denied'
          ? '사진 접근 권한을 켜줘'
          : '사진 선택 실패: ${e.code}';
      _showSnack(msg);
    } catch (e) {
      if (!mounted) return;
      _showSnack('문제가 생겼어: ${_shortError(e)}');
    } finally {
      _picking = false;
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      );
  }

  // ─── overlay ──────────────────────────────────────────────────────────

  Widget _buildOverlay(BuildContext overlayCtx) {
    final fabCtx = _fabKey.currentContext;
    if (fabCtx == null) return const SizedBox.shrink();
    final rb = fabCtx.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached) return const SizedBox.shrink();
    final origin = rb.localToGlobal(Offset.zero);
    final size = rb.size;
    final center =
        Offset(origin.dx + size.width / 2, origin.dy + size.height / 2);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final raw = _anim.value;
        final t = raw.clamp(0.0, 1.0);
        return Stack(
          children: [
            // Scrim — 바깥 탭하면 닫힘.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.26 * t),
                ),
              ),
            ),
            // 반달 아치. bottomCenter 기준 scale 로 FAB 에서 피어나는 모션.
            Positioned(
              left: center.dx - _kArcOuterR,
              top: center.dy - _kArcOuterR,
              width: _kArcOuterR * 2,
              height: _kArcOuterR,
              child: IgnorePointer(
                ignoring: t < 0.5,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.45 + 0.55 * raw,
                    alignment: Alignment.bottomCenter,
                    child: ValueListenableBuilder<_Side?>(
                      valueListenable: _hoverSide,
                      builder: (_, hover, __) => _buildArc(hover),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArc(_Side? hover) {
    // 각 반쪽의 가운데 각도.
    const leftMid = math.pi + math.pi / 4; // 5π/4 = 상-좌
    const rightMid = 3 * math.pi / 2 + math.pi / 4; // 7π/4 = 상-우
    const midR = (_kArcInnerR + _kArcOuterR) / 2;
    final leftIcon = _kArcCenter +
        Offset(midR * math.cos(leftMid), midR * math.sin(leftMid));
    final rightIcon = _kArcCenter +
        Offset(midR * math.cos(rightMid), midR * math.sin(rightMid));

    final leftColor = hover == _Side.left
        ? FoodietColors.coral100
        : FoodietColors.cream50;
    final rightColor = hover == _Side.right
        ? FoodietColors.coral100
        : FoodietColors.cream50;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 왼쪽 반쪽 (카메라) — 9시→12시 도넛 조각.
        Positioned.fill(
          child: PhysicalShape(
            clipper: const _DonutSliceClipper(
              arcCenter: _kArcCenter,
              innerR: _kArcInnerR,
              outerR: _kArcOuterR,
              startAngle: math.pi,
              sweepAngle: math.pi / 2,
            ),
            color: leftColor,
            elevation: 6,
            shadowColor: FoodietColors.warm900.withValues(alpha: 0.28),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pick(PhotoSource.camera),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // 오른쪽 반쪽 (앨범) — 12시→3시 도넛 조각.
        Positioned.fill(
          child: PhysicalShape(
            clipper: const _DonutSliceClipper(
              arcCenter: _kArcCenter,
              innerR: _kArcInnerR,
              outerR: _kArcOuterR,
              startAngle: 3 * math.pi / 2,
              sweepAngle: math.pi / 2,
            ),
            color: rightColor,
            elevation: 6,
            shadowColor: FoodietColors.warm900.withValues(alpha: 0.28),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pick(PhotoSource.gallery),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // 아이콘 + 라벨.
        _centerLabel(
          position: leftIcon,
          icon: Icons.photo_camera_rounded,
          label: '카메라',
          emphasized: hover == _Side.left,
        ),
        _centerLabel(
          position: rightIcon,
          icon: Icons.photo_library_rounded,
          label: '앨범',
          emphasized: hover == _Side.right,
        ),
      ],
    );
  }

  Widget _centerLabel({
    required Offset position,
    required IconData icon,
    required String label,
    required bool emphasized,
  }) {
    final fg =
        emphasized ? FoodietColors.coral700 : FoodietColors.coral500;
    return Positioned(
      left: position.dx - _kArcLabelBoxW / 2,
      top: position.dy - _kArcLabelBoxH / 2,
      width: _kArcLabelBoxW,
      height: _kArcLabelBoxH,
      child: IgnorePointer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: _kArcIconSize),
            const SizedBox(height: 2),
            Text(
              label,
              style: FoodietText.caption.copyWith(
                color: fg,
                fontSize: _kArcLabelFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      body: widget.navigationShell,
      floatingActionButton: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: _GlassCameraFab(
          fabKey: _fabKey,
          anim: _anim,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: FoodietColors.cream50,
        elevation: 4,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Tab(
                icon: Icons.home_outlined,
                active: Icons.home_rounded,
                label: '홈',
                index: 0,
                shell: widget.navigationShell,
                onTap: _go,
              ),
              _Tab(
                icon: Icons.calendar_month_outlined,
                active: Icons.calendar_month,
                label: '기록',
                index: 1,
                shell: widget.navigationShell,
                onTap: _go,
              ),
              const SizedBox(width: 56), // FAB 공간
              _Tab(
                icon: Icons.insights_outlined,
                active: Icons.insights,
                label: '인사이트',
                index: 2,
                shell: widget.navigationShell,
                onTap: _go,
              ),
              _Tab(
                icon: Icons.person_outline,
                active: Icons.person,
                label: '마이',
                index: 3,
                shell: widget.navigationShell,
                onTap: _go,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 도넛 조각(pie slice of annulus) Path clipper.
///
/// [startAngle] 부터 [sweepAngle] 만큼 시계방향(캔버스 기준)으로 sweep,
/// [innerR] ~ [outerR] 두께의 반지 조각을 만든다.
/// 캔버스 좌표에서 각도 0 = 오른쪽(3시), π/2 = 아래(6시), π = 왼쪽(9시),
/// 3π/2 = 위(12시). Y축이 아래로 양수이므로 positive sweep 은 시계방향.
class _DonutSliceClipper extends CustomClipper<Path> {
  const _DonutSliceClipper({
    required this.arcCenter,
    required this.innerR,
    required this.outerR,
    required this.startAngle,
    required this.sweepAngle,
  });
  final Offset arcCenter;
  final double innerR;
  final double outerR;
  final double startAngle;
  final double sweepAngle;

  @override
  Path getClip(Size size) {
    final path = Path();
    final startOuter = arcCenter +
        Offset(outerR * math.cos(startAngle), outerR * math.sin(startAngle));
    path.moveTo(startOuter.dx, startOuter.dy);
    path.arcTo(
      Rect.fromCircle(center: arcCenter, radius: outerR),
      startAngle,
      sweepAngle,
      false,
    );
    final endAngle = startAngle + sweepAngle;
    final endInner = arcCenter +
        Offset(innerR * math.cos(endAngle), innerR * math.sin(endAngle));
    path.lineTo(endInner.dx, endInner.dy);
    path.arcTo(
      Rect.fromCircle(center: arcCenter, radius: innerR),
      endAngle,
      -sweepAngle,
      false,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _DonutSliceClipper old) =>
      old.arcCenter != arcCenter ||
      old.innerR != innerR ||
      old.outerR != outerR ||
      old.startAngle != startAngle ||
      old.sweepAngle != sweepAngle;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.active,
    required this.label,
    required this.index,
    required this.shell,
    required this.onTap,
  });
  final IconData icon;
  final IconData active;
  final String label;
  final int index;
  final StatefulNavigationShell shell;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final selected = shell.currentIndex == index;
    final color = selected ? FoodietColors.coral500 : FoodietColors.warm500;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? active : icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: FoodietText.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 주황 글라스 FAB — iOS 26+ 의 "Liquid Glass" 느낌.
///
/// 구성 요소:
///   1. 외곽 soft shadow — 코랄 틴트로 살짝 떠보이게.
///   2. `BackdropFilter(blur)` — 뒤의 body content 가 흐리게 비치도록.
///   3. 반투명 코랄 gradient fill — 뒤 내용이 오렌지 톤으로 물들어 보이게.
///   4. 얇은 흰색 외곽선 + 상단 하이라이트 crescent — 유리 깊이감.
///   5. 중앙 아이콘 (카메라 ↔ 닫기 크로스페이드) — 아치 열림 시 전환.
// iOS 26 Liquid Glass 스타일 카메라 FAB.
//
// 레이어 스택(아래 → 위):
//   0) 외곽 섀도: ambient drop + 코랄 halo + 접지 contact.
//   1) BackdropFilter: blur + saturation 매트릭스로 뒤 배경을 진짜 유리처럼 통과.
//   2) Radial 틴트: 거의 투명(화이트 살짝 + 코랄 트레이스) — glass fill.
//   3) Rim stroke: 상단 밝음 / 하단 어두움 dual gradient 테두리 (빛 받는 유리 가장자리).
//   4) Specular: 상단 crescent 하이라이트 — 유리 광택.
//   5) Ambient warm: 바닥에서 올라오는 코랄 잔광 — 브랜드 존재감.
//   6) 아이콘: 흰색 + drop shadow (투명 배경에서도 가독성 확보).
class _GlassCameraFab extends StatelessWidget {
  const _GlassCameraFab({
    required this.fabKey,
    required this.anim,
  });
  final Key fabKey;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: fabKey,
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: FoodietColors.warm900.withValues(alpha: 0.22),
            blurRadius: 22,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: FoodietColors.coral500.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: FoodietColors.warm900.withValues(alpha: 0.10),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.compose(
                  outer: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  inner: const ColorFilter.matrix(_kGlassSaturate),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            // Radial tint — 좌상단은 밝은 glass highlight, 전반은 은은한 코랄 톤.
            // 이 한 레이어로 "주황빛이 도는 유리" 느낌을 만든다.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.55),
                    radius: 1.4,
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0.08),
                      FoodietColors.coral500.withValues(alpha: 0.20),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: CustomPaint(painter: _GlassRimPainter())),
            Positioned(
              top: 3,
              left: 9,
              right: 9,
              height: 13,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.78),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: anim,
                builder: (_, __) {
                  final t = anim.value.clamp(0.0, 1.0);
                  final iconShadows = <Shadow>[
                    Shadow(
                      color: FoodietColors.warm900.withValues(alpha: 0.45),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ];
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: 1 - t,
                        child: Icon(
                          Icons.photo_camera_rounded,
                          size: 26,
                          color: Colors.white,
                          shadows: iconShadows,
                        ),
                      ),
                      Opacity(
                        opacity: t,
                        child: Transform.rotate(
                          angle: t * math.pi / 4,
                          child: Icon(
                            Icons.close_rounded,
                            size: 26,
                            color: Colors.white,
                            shadows: iconShadows,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Saturation 1.5x 매트릭스 — BackdropFilter로 통과한 배경의 채도를 올려
// 유리 너머 이미지가 생생하게 살아나도록(iOS vibrancy 흉내).
const List<double> _kGlassSaturate = <double>[
  1.394, -0.358, -0.036, 0, 0,
  -0.107,  1.143, -0.036, 0, 0,
  -0.107, -0.358,  1.464, 0, 0,
   0,      0,      0,     1, 0,
];

// 유리 테두리(rim): 상단 밝은 하이라이트 → 하단 미세한 그림자 스트로크.
// 빛을 받는 실제 유리 edge 의 광학적 성질을 근사.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 0.6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.25),
          FoodietColors.coral600.withValues(alpha: 0.22),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) => false;
}
