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
import '../../services/duo_display.dart';
import '../../services/photo_upload_service.dart';
import '../../theme/foodiet_layout.dart';
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

/// 아치의 두 반쪽 — 카메라 / 앨범.
enum _Side { camera, gallery }

/// 아치가 피어나는 방향. 하단 바 FAB 는 위로, iPhone Duo 플로팅 메뉴는
/// 화면 안쪽(메뉴가 오른쪽에 있으면 왼쪽)으로.
enum _ArcFacing { up, left, right }

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

  /// 아치가 피어나는 방향 — build 에서 레이아웃(하단 바 / Duo 플로팅 메뉴)에 맞춰 갱신.
  _ArcFacing _facing = _ArcFacing.up;

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
      _pick(chosen == _Side.camera ? PhotoSource.camera : PhotoSource.gallery);
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
  ///
  /// 위로 피는 아치: 왼쪽 = 카메라, 오른쪽 = 앨범.
  /// 옆으로 피는 아치(Duo 플로팅 메뉴): 위 = 카메라, 아래 = 앨범.
  _Side? _sideForDelta(Offset delta) {
    if (delta.distance < 16) return null;
    switch (_facing) {
      case _ArcFacing.up:
        if (delta.dy > 20) return null; // FAB 아래로 빠짐 → 선택 아님
        if (delta.dx.abs() < 12) return null; // 거의 수직 → dead zone
        return delta.dx < 0 ? _Side.camera : _Side.gallery;
      case _ArcFacing.left:
      case _ArcFacing.right:
        // 아치 반대쪽(화면 가장자리)으로 빠지면 선택 아님.
        final away = _facing == _ArcFacing.left ? delta.dx > 20 : delta.dx < -20;
        if (away) return null;
        if (delta.dy.abs() < 12) return null; // 거의 수평 → dead zone
        return delta.dy < 0 ? _Side.camera : _Side.gallery;
    }
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

  /// 스낵바 여백 — 하단 바 위로 띄우거나, Duo 에선 플로팅 메뉴 옆으로 비킨다.
  EdgeInsets _snackMargin = const EdgeInsets.fromLTRB(16, 0, 16, 80);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: _snackMargin,
        ),
      );
  }

  // ─── overlay ──────────────────────────────────────────────────────────

  Widget _buildOverlay(BuildContext overlayCtx) {
    final fabCtx = _fabKey.currentContext;
    if (fabCtx == null) return const SizedBox.shrink();
    final rb = fabCtx.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached) return const SizedBox.shrink();
    // Positioned 좌표계는 overlay 기준. 화면 전역 좌표와 overlay 원점이 항상
    // 같다고 가정하지 않는다 (Split View · 큰 화면에서 어긋날 수 있음).
    final overlayBox = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox?;
    final origin = rb.localToGlobal(
      Offset.zero,
      ancestor: overlayBox != null && overlayBox.attached ? overlayBox : null,
    );
    final size = rb.size;
    final center =
        Offset(origin.dx + size.width / 2, origin.dy + size.height / 2);
    final geo = _arcGeometry(center);

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
            // 반달 아치. FAB 쪽 가장자리 기준 scale 로 FAB 에서 피어나는 모션.
            Positioned.fromRect(
              rect: geo.box,
              child: IgnorePointer(
                ignoring: t < 0.5,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.45 + 0.55 * raw,
                    alignment: geo.scaleAlignment,
                    child: ValueListenableBuilder<_Side?>(
                      valueListenable: _hoverSide,
                      builder: (_, hover, __) => _buildArc(hover, geo),
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

  /// 아치를 놓을 상자(overlay 좌표) · 상자 안 원 중심 · 두 반쪽 시작 각도.
  ///
  /// 캔버스 각도: 0 = 3시, π/2 = 6시, π = 9시, 3π/2 = 12시 (시계방향 +).
  ///   - up   : 위 반원. 카메라 9→12시, 앨범 12→3시.
  ///   - left : 왼쪽 반원. 카메라 9→12시, 앨범 6→9시.
  ///   - right: 오른쪽 반원. 카메라 12→3시, 앨범 3→6시.
  ({
    Rect box,
    Offset arcCenter,
    double cameraStart,
    double galleryStart,
    Alignment scaleAlignment,
  }) _arcGeometry(Offset c) {
    const r = _kArcOuterR;
    switch (_facing) {
      case _ArcFacing.up:
        return (
          box: Rect.fromLTWH(c.dx - r, c.dy - r, r * 2, r),
          arcCenter: _kArcCenter,
          cameraStart: math.pi,
          galleryStart: 3 * math.pi / 2,
          scaleAlignment: Alignment.bottomCenter,
        );
      case _ArcFacing.left:
        return (
          box: Rect.fromLTWH(c.dx - r, c.dy - r, r, r * 2),
          arcCenter: const Offset(r, r),
          cameraStart: math.pi,
          galleryStart: math.pi / 2,
          scaleAlignment: Alignment.centerRight,
        );
      case _ArcFacing.right:
        return (
          box: Rect.fromLTWH(c.dx, c.dy - r, r, r * 2),
          arcCenter: const Offset(0, r),
          cameraStart: 3 * math.pi / 2,
          galleryStart: 0,
          scaleAlignment: Alignment.centerLeft,
        );
    }
  }

  Widget _buildArc(
    _Side? hover,
    ({
      Rect box,
      Offset arcCenter,
      double cameraStart,
      double galleryStart,
      Alignment scaleAlignment,
    }) geo,
  ) {
    // 각 반쪽의 가운데 각도 · 아이콘 위치.
    const midR = (_kArcInnerR + _kArcOuterR) / 2;
    Offset iconAt(double start) {
      final mid = start + math.pi / 4;
      return geo.arcCenter + Offset(midR * math.cos(mid), midR * math.sin(mid));
    }

    final leftIcon = iconAt(geo.cameraStart);
    final rightIcon = iconAt(geo.galleryStart);

    final leftColor = hover == _Side.camera
        ? FoodietColors.coral100
        : FoodietColors.cream50;
    final rightColor = hover == _Side.gallery
        ? FoodietColors.coral100
        : FoodietColors.cream50;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 카메라 반쪽 — up 이면 9시→12시 도넛 조각.
        Positioned.fill(
          child: PhysicalShape(
            clipper: _DonutSliceClipper(
              arcCenter: geo.arcCenter,
              innerR: _kArcInnerR,
              outerR: _kArcOuterR,
              startAngle: geo.cameraStart,
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
        // 앨범 반쪽 — up 이면 12시→3시 도넛 조각.
        Positioned.fill(
          child: PhysicalShape(
            clipper: _DonutSliceClipper(
              arcCenter: geo.arcCenter,
              innerR: _kArcInnerR,
              outerR: _kArcOuterR,
              startAngle: geo.galleryStart,
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
          emphasized: hover == _Side.camera,
        ),
        _centerLabel(
          position: rightIcon,
          icon: Icons.photo_library_rounded,
          label: '앨범',
          emphasized: hover == _Side.gallery,
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

  /// 카메라 버튼 — 누른 채 드래그로 카메라/앨범 선택. 두 레이아웃 공용.
  Widget _cameraButton() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: _GlassCameraFab(
        fabKey: _fabKey,
        anim: _anim,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 커뮤니티 탭(index 3) 에서는 가운데 카메라 FAB 를 아래로 슬라이드해서
    // 숨긴다 — 사진 기록보다 피드 보기에 집중하는 흐름.
    final isCommunityTab = widget.navigationShell.currentIndex == 3;

    // iPhone Duo(힌지가 있는 기기) 는 하단 바 대신 우측 하단 플로팅 메뉴.
    final duo = ref.watch(duoDisplayProvider).valueOrNull;
    if (duo != null && duo.hasHinge) {
      return _buildDuo(context, duo, isCommunityTab);
    }
    _facing = _ArcFacing.up;
    _snackMargin = const EdgeInsets.fromLTRB(16, 0, 16, 80);

    return Scaffold(
      // 레이아웃별로 키를 달리해 전환 시 Scaffold 를 통째로 바꾼다 — 같은
      // Scaffold 를 재사용하면 FAB 퇴장 애니메이션 동안 카메라 버튼(GlobalKey)이
      // 두 군데에 동시에 존재하게 된다.
      key: const ValueKey('shell-bottom-bar'),
      backgroundColor: FoodietColors.cream00,
      body: widget.navigationShell,
      floatingActionButton: IgnorePointer(
        ignoring: isCommunityTab,
        // 카메라 버튼은 그대로 (scale 1) — 자기 반지름(절반)만큼만 아래로
        // 슬라이드해서 BottomAppBar 노치를 동그라미가 채우는 모양.
        // 시각적으로 하단바 윗 라인이 평평해 보이고, 카메라가 그 안에
        // "쏙" 들어간 듯.
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          offset: isCommunityTab ? const Offset(0, 0.5) : Offset.zero,
          child: _cameraButton(),
        ),
      ),
      floatingActionButtonLocation: const SafeCenterDockedFabLocation(),
      bottomNavigationBar: BottomAppBar(
        color: FoodietColors.cream50,
        elevation: 4,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        // 바는 화면 끝까지, 탭 묶음은 읽기 폭 안으로 — 넓은 화면(Duo 안쪽
        // 디스플레이 가로, iPad) 에서 탭이 양 끝으로 흩어지지 않게.
        // 좌우 대칭이라 탭 사이 빈칸은 계속 FAB 중앙과 맞는다.
        padding: EdgeInsets.symmetric(
          horizontal: FoodietLayout.gutter(
            MediaQuery.sizeOf(context).width,
            min: 0,
          ),
        ),
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
                icon: Icons.groups_outlined,
                active: Icons.groups_rounded,
                label: '커뮤니티',
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

  // ─── iPhone Duo: 우측 하단 플로팅 메뉴 ───────────────────────────────────
  //
  // 하단 바를 없애고 [카메라 + 세로 탭 캡슐] 을 상태바 띠 아래(보통 오른쪽)에
  // 띄운다. 본문은 띠 쪽 safe area 를 걷어내 화면 끝까지 쓰고, 앱바 액션 · 탭만
  // 띠(상태바 · 카메라)를 비켜 간다. 띠 위치 · 크기는 기기가 알려주는 예약 영역에서.

  Widget _buildDuo(
      BuildContext context, DuoDisplayState duo, bool isCommunityTab) {
    final mq = MediaQuery.of(context);
    final strip = DuoStrip.from(size: mq.size, occlusions: duo.occlusions);
    final onLeft = strip.side == DuoStripSide.left;
    _facing = onLeft ? _ArcFacing.right : _ArcFacing.left;

    // 메뉴 가로 중심: 띠가 있으면 띠 가운데, 없으면(펼친 세로 등) safe area 안쪽.
    final stripRect = strip.rect;
    final menuCenterX = stripRect != null
        ? stripRect.center.dx
        : mq.size.width - mq.padding.right - 16 - _kDuoFabSize / 2;
    // 본문 · 스낵바가 비켜야 할 메뉴 쪽 폭.
    final menuReserve =
        stripRect != null ? strip.width : _kDuoFabSize + 16 * 2;
    _snackMargin = EdgeInsets.fromLTRB(
      16 + (onLeft ? menuReserve : 0),
      0,
      16 + (onLeft ? 0 : menuReserve),
      16,
    );

    final appBarLeft = onLeft ? strip.width : 0.0;
    final appBarRight = strip.side == DuoStripSide.right ? strip.width : 0.0;
    final theme = Theme.of(context);
    // 키보드가 올라오면 입력란을 가리지 않게 메뉴를 숨긴다.
    final keyboardOpen = mq.viewInsets.bottom > 0;

    return Scaffold(
      key: const ValueKey('shell-duo'),
      backgroundColor: FoodietColors.cream00,
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              // 띠 쪽 inset 을 걷어내고, 아래(홈 인디케이터) inset 도 본문에선 빼서
              // 스크롤 콘텐츠가 화면 맨 아래까지 지나가게 한다. 대신 목록 끝
              // 여백(scrollBottom)에 메뉴 높이 + 아래 inset 을 더해 마지막 항목이
              // 메뉴 · 인디케이터 위로 올라올 수 있게.
              data: mq.copyWith(
                padding: strip.bodyPadding(mq.padding).copyWith(bottom: 0),
                viewPadding:
                    strip.bodyPadding(mq.viewPadding).copyWith(bottom: 0),
              ),
              child: Theme(
                data: theme.copyWith(
                  appBarTheme: theme.appBarTheme.copyWith(
                    actionsPadding:
                        EdgeInsets.only(left: appBarLeft, right: appBarRight),
                  ),
                ),
                child: DuoChromeInsets(
                  appBarLeft: appBarLeft,
                  appBarRight: appBarRight,
                  scrollBottom:
                      _kDuoMenuHeight + _kDuoMenuGap + mq.padding.bottom,
                  child: widget.navigationShell,
                ),
              ),
            ),
          ),
          Positioned(
            left: menuCenterX - _kDuoFabSize / 2,
            width: _kDuoFabSize,
            bottom: mq.padding.bottom + _kDuoMenuGap,
            child: IgnorePointer(
              ignoring: keyboardOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: keyboardOpen ? 0 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 커뮤니티 탭에선 카메라를 숨기되 자리는 유지 — 탭 위치가
                    // 탭마다 들썩이지 않게.
                    IgnorePointer(
                      ignoring: isCommunityTab,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        scale: isCommunityTab ? 0.6 : 1,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: isCommunityTab ? 0 : 1,
                          child: _cameraButton(),
                        ),
                      ),
                    ),
                    const SizedBox(height: _kDuoMenuGap),
                    _DuoTabPill(
                      shell: widget.navigationShell,
                      onTap: _go,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── iPhone Duo 플로팅 메뉴 치수 ────────────────────────────────────────
const double _kDuoFabSize = 60; // _GlassCameraFab 크기와 같게.
const double _kDuoMenuWidth = 56;
const double _kDuoTabExtent = 48;
const double _kDuoPillPadding = 6;
const double _kDuoMenuGap = 12;
const double _kDuoMenuHeight = _kDuoFabSize +
    _kDuoMenuGap +
    _kDuoTabExtent * 4 +
    _kDuoPillPadding * 2;

/// Duo 세로 탭 캡슐 — 아이콘만. 이름은 툴팁(길게 누르기) · VoiceOver 로.
///
/// 순서는 하단 바와 같다(위→아래 = 왼→오른): 홈 · 기록 · 인사이트 · 커뮤니티.
class _DuoTabPill extends StatelessWidget {
  const _DuoTabPill({required this.shell, required this.onTap});
  final StatefulNavigationShell shell;
  final void Function(int) onTap;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, '홈'),
    (Icons.calendar_month_outlined, Icons.calendar_month, '기록'),
    (Icons.insights_outlined, Icons.insights, '인사이트'),
    (Icons.groups_outlined, Icons.groups_rounded, '커뮤니티'),
  ];

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(_kDuoMenuWidth / 2));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: FoodietColors.warm900.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        // 본문이 뒤로 지나가므로 반투명 유리 — 카메라 버튼과 같은 결.
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: _kDuoMenuWidth,
            padding: const EdgeInsets.symmetric(vertical: _kDuoPillPadding),
            decoration: BoxDecoration(
              color: FoodietColors.cream50.withValues(alpha: 0.86),
              borderRadius: radius,
              border: Border.all(color: FoodietColors.cream100),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _DuoTabButton(
                    icon: _tabs[i].$1,
                    activeIcon: _tabs[i].$2,
                    label: _tabs[i].$3,
                    selected: shell.currentIndex == i,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DuoTabButton extends StatelessWidget {
  const _DuoTabButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: _kDuoTabExtent / 2,
          child: SizedBox(
            width: _kDuoTabExtent,
            height: _kDuoTabExtent,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? FoodietColors.coral100 : Colors.transparent,
                ),
                child: Icon(
                  selected ? activeIcon : icon,
                  size: 22,
                  color:
                      selected ? FoodietColors.coral500 : FoodietColors.warm500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [FloatingActionButtonLocation.centerDocked] 와 같지만, 가로 중앙을
/// 화면 전체가 아니라 **좌우 safe area 안쪽** 기준으로 잡는다.
///
/// BottomAppBar 는 탭 Row 를 SafeArea 로 감싸므로 FAB 자리(가운데 빈칸)는
/// safe area 안쪽의 중앙에 생긴다. 기본 centerDocked 는 화면 정중앙에 놓기
/// 때문에 좌우 inset 이 다르면 (iPhone Duo 바깥 디스플레이의 카메라 쪽,
/// Split View) FAB 와 노치가 (left - right) / 2 만큼 빗나가 옆 탭을 가린다.
class SafeCenterDockedFabLocation extends StandardFabLocation
    with FabDockedOffsetY {
  const SafeCenterDockedFabLocation();

  @override
  double getOffsetX(
      ScaffoldPrelayoutGeometry scaffoldGeometry, double adjustment) {
    return FoodietLayout.centerOffsetWithin(
      width: scaffoldGeometry.scaffoldSize.width,
      childWidth: scaffoldGeometry.floatingActionButtonSize.width,
      insetLeft: scaffoldGeometry.minInsets.left,
      insetRight: scaffoldGeometry.minInsets.right,
    );
  }

  @override
  String toString() => 'SafeCenterDockedFabLocation';
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
