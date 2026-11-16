/// 홈 탭 셸 — iPhone Duo 등 여러 화면 크기 · 비대칭 safe area 레이아웃 테스트.
///
/// Duo 치수는 iOS 27.1 시뮬레이터 실측: 바깥 466×678pt, 안쪽 669×951pt.
/// 안쪽 가로(951×669) 의 safe area 는 실측(오른쪽 84 · 아래 34), 나머지 자세의
/// inset 과 Split View 폭(≈ 절반) 은 측정 전이라 비대칭 상황을 가정해 넣는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/features/home/home_shell.dart';
import 'package:foodiet/services/duo_display.dart';
import 'package:go_router/go_router.dart';

class _Case {
  const _Case(this.name, this.size, [this.padding = EdgeInsets.zero]);
  final String name;
  final Size size;
  final EdgeInsets padding;
}

const _cases = [
  _Case('iPhone 세로', Size(393, 852), EdgeInsets.only(top: 59, bottom: 34)),
  _Case('iPhone 가로', Size(852, 393),
      EdgeInsets.only(left: 59, right: 59, bottom: 21)),
  _Case('Duo 바깥 세로 (오른쪽 inset)', Size(466, 678),
      EdgeInsets.only(right: 50, bottom: 20)),
  _Case('Duo 바깥 가로 (왼쪽 inset)', Size(678, 466),
      EdgeInsets.only(left: 50, bottom: 20)),
  _Case('Duo 안쪽 세로', Size(669, 951), EdgeInsets.only(top: 40, bottom: 20)),
  _Case('Duo 안쪽 가로 (실측 inset)', Size(951, 669),
      EdgeInsets.only(right: 84, bottom: 34)),
  _Case('Duo 안쪽 Split View (왼쪽 inset)', Size(475, 669),
      EdgeInsets.only(left: 30, bottom: 20)),
];

Future<void> _pumpShell(WidgetTester tester, _Case c,
    {DuoDisplayState? duo}) async {
  const dpr = 3.0;
  final pad = FakeViewPadding(
    left: c.padding.left * dpr,
    top: c.padding.top * dpr,
    right: c.padding.right * dpr,
    bottom: c.padding.bottom * dpr,
  );
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = c.size * dpr;
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  addTearDown(tester.view.reset);

  Widget page(String label) => Scaffold(
        appBar: AppBar(
          title: Text('title $label'),
          actions: [
            IconButton(
              key: Key('action $label'),
              icon: const Icon(Icons.person),
              onPressed: () {},
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            children: [
              for (var i = 0; i < 30; i++) ListTile(title: Text('$label $i')),
            ],
          ),
        ),
      );

  final router = GoRouter(
    initialLocation: '/a',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(navigationShell: shell),
        branches: [
          for (final p in ['/a', '/b', '/c', '/d'])
            StatefulShellBranch(routes: [
              GoRoute(path: p, builder: (_, __) => page(p)),
            ]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (duo != null)
          duoDisplayProvider.overrideWith((ref) => Stream.value(duo)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _tabRect(WidgetTester tester, String label) => tester.getRect(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
    );

void main() {
  for (final c in _cases) {
    testWidgets('${c.name}: 오버플로 없음 + FAB 가 탭 사이 빈칸 중앙', (tester) async {
      await _pumpShell(tester, c);
      expect(tester.takeException(), isNull);

      final fab = tester.getRect(find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_GlassCameraFab'));
      final left = _tabRect(tester, '기록');
      final right = _tabRect(tester, '인사이트');
      final gapCenter = (left.right + right.left) / 2;

      expect(fab.center.dx, moreOrLessEquals(gapCenter, epsilon: 0.5));
      // FAB 는 좌우 safe area 안쪽에 있어야 한다.
      expect(fab.left, greaterThanOrEqualTo(c.padding.left));
      expect(fab.right, lessThanOrEqualTo(c.size.width - c.padding.right));
      // 탭은 safe area 를 침범하지 않는다.
      expect(_tabRect(tester, '홈').left, greaterThanOrEqualTo(c.padding.left));
      expect(_tabRect(tester, '커뮤니티').right,
          lessThanOrEqualTo(c.size.width - c.padding.right));
    });
  }

  testWidgets('넓은 화면에선 탭 묶음이 읽기 폭(640) 안으로 모인다', (tester) async {
    await _pumpShell(tester, _cases.firstWhere((c) => c.size.width == 951));
    final span =
        _tabRect(tester, '커뮤니티').right - _tabRect(tester, '홈').left;
    expect(span, lessThanOrEqualTo(640 + 0.5));
  });

  group('iPhone Duo (힌지 있음) — 우측 하단 플로팅 메뉴', () {
    // 실기기 실측(iOS 27.1): 접은 바깥 457×678, 펼친 가로 951×669.
    const closed = _Case('Duo 접음 (실측)', Size(457, 678),
        EdgeInsets.only(right: 84, bottom: 34));
    const closedStrip = Rect.fromLTWH(373, 0, 84, 174);
    const closedDuo = DuoDisplayState(
      hasHinge: true,
      hingeStatus: DuoHingeStatus.closed,
      occlusions: [closedStrip, Rect.fromLTWH(390.7, 29.3, 37, 37)],
    );
    const open = _Case('Duo 펼침 가로 (실측)', Size(951, 669),
        EdgeInsets.only(right: 84, bottom: 34));
    const openStrip = Rect.fromLTWH(867, 0, 84, 124);
    const openDuo = DuoDisplayState(
      hasHinge: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
      occlusions: [openStrip],
    );

    Rect fabRect(WidgetTester tester) => tester.getRect(find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_GlassCameraFab'));

    for (final (c, duo, strip) in [
      (closed, closedDuo, closedStrip),
      (open, openDuo, openStrip),
    ]) {
      testWidgets('${c.name}: 하단 바 없음 · 메뉴는 띠 안 · 본문은 화면 끝까지',
          (tester) async {
        await _pumpShell(tester, c, duo: duo);
        expect(tester.takeException(), isNull);
        expect(find.byType(BottomAppBar), findsNothing);

        // 카메라 버튼 + 탭 4개가 띠 가운데, 상태바 아래 · 홈 인디케이터 위.
        final fab = fabRect(tester);
        expect(fab.center.dx, moreOrLessEquals(strip.center.dx, epsilon: 0.5));
        expect(fab.top, greaterThan(strip.bottom));
        for (final label in ['홈', '기록', '인사이트', '커뮤니티']) {
          final r = tester.getRect(find.byTooltip(label));
          expect(r.center.dx, moreOrLessEquals(strip.center.dx, epsilon: 0.5));
          expect(r.left, greaterThanOrEqualTo(strip.left));
          expect(r.bottom, lessThanOrEqualTo(c.size.height - c.padding.bottom));
        }

        // 본문은 띠 쪽 safe area 를 걷어내 화면 끝까지.
        final row = tester.getRect(find.byType(ListTile).first);
        expect(row.right, moreOrLessEquals(c.size.width, epsilon: 0.5));

        // 앱바 액션은 상태바 · 카메라 띠를 비켜 간다.
        final action = tester.getRect(find.byKey(const Key('action /a')));
        expect(action.right, lessThanOrEqualTo(strip.left + 0.5));
      });
    }

    testWidgets('탭 버튼으로 브랜치 전환', (tester) async {
      await _pumpShell(tester, closed, duo: closedDuo);
      await tester.tap(find.byTooltip('인사이트'));
      await tester.pumpAndSettle();
      expect(find.text('title /c'), findsOneWidget);
      await tester.tap(find.byTooltip('커뮤니티'));
      await tester.pumpAndSettle();
      expect(find.text('title /d'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('띠가 왼쪽(Split View 왼쪽 앱)이면 메뉴도 왼쪽', (tester) async {
      const c = _Case('Duo Split 왼쪽', Size(475, 669),
          EdgeInsets.only(left: 84, bottom: 34));
      const strip = Rect.fromLTWH(0, 0, 84, 124);
      await _pumpShell(tester, c,
          duo: const DuoDisplayState(hasHinge: true, occlusions: [strip]));
      expect(tester.takeException(), isNull);
      expect(fabRect(tester).center.dx,
          moreOrLessEquals(strip.center.dx, epsilon: 0.5));
      expect(tester.getRect(find.byType(ListTile).first).left,
          moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('띠가 없으면(위쪽 상태바만) safe area 안 우측 하단', (tester) async {
      const c = _Case('Duo 펼침 세로 (가정)', Size(669, 951),
          EdgeInsets.only(top: 40, bottom: 34));
      await _pumpShell(tester, c,
          duo: const DuoDisplayState(
              hasHinge: true, occlusions: [Rect.fromLTWH(0, 0, 669, 40)]));
      expect(tester.takeException(), isNull);
      expect(find.byType(BottomAppBar), findsNothing);
      final fab = fabRect(tester);
      expect(fab.right, lessThanOrEqualTo(c.size.width - 16 + 0.5));
      expect(fab.right, greaterThan(c.size.width - 100));
    });
  });
}
