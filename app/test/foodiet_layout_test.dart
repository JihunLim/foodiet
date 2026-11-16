/// 적응형 레이아웃 헬퍼 단위 테스트 (iPhone Duo · iPad · 가로 모드).
///
/// Duo 치수는 iOS 27.1 시뮬레이터 실측: 바깥 466pt, 안쪽 669pt(세로) / 951pt(가로).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/theme/foodiet_layout.dart';

void main() {
  group('FoodietLayout.gutter', () {
    test('좁은 화면은 최소 여백 20 유지', () {
      expect(FoodietLayout.gutter(393), 20);
      expect(FoodietLayout.gutter(466), 20);
      expect(FoodietLayout.gutter(669), 20);
    });

    test('넓은 화면은 콘텐츠를 640 으로 가운데 정렬', () {
      // Duo 안쪽 가로 951 에서 오른쪽 inset 84 를 뺀 safe area 폭.
      expect(FoodietLayout.gutter(867), (867 - 640) / 2);
    });
  });

  group('FoodietLayout.useTwoColumns', () {
    test('Duo 안쪽 세로/Split View 는 1단, 안쪽 가로는 2단', () {
      expect(FoodietLayout.useTwoColumns(475), isFalse);
      expect(FoodietLayout.useTwoColumns(669), isFalse);
      expect(FoodietLayout.useTwoColumns(867), isTrue);
    });
  });

  group('FoodietLayout.centerOffsetWithin', () {
    test('대칭 inset 은 화면 정중앙', () {
      expect(
        FoodietLayout.centerOffsetWithin(width: 393, childWidth: 60),
        (393 - 60) / 2,
      );
    });

    test('비대칭 inset 은 safe area 안쪽 중앙', () {
      final x = FoodietLayout.centerOffsetWithin(
        width: 466,
        childWidth: 60,
        insetRight: 50,
      );
      // safe area = 0..416 → 중앙 208 → 왼쪽 끝 178.
      expect(x, 178);
    });
  });

  group('ReadableWidth', () {
    Future<Size> childSize(WidgetTester tester, double width) async {
      const key = Key('child');
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            height: 100,
            child: const ReadableWidth(
              child: SizedBox(key: key, width: double.infinity, height: 10),
            ),
          ),
        ),
      ));
      return tester.getSize(find.byKey(key));
    }

    testWidgets('읽기 폭 이하에선 제약을 바꾸지 않는다 (tight 폭 유지)',
        (tester) async {
      // 일반 iPhone · Duo 세로: 자식이 그대로 tight 폭/높이를 받는다.
      expect(await childSize(tester, 393), const Size(393, 100));
      expect(await childSize(tester, 669), const Size(669, 100));
    });

    testWidgets('넓은 화면에선 680 으로 제한', (tester) async {
      expect((await childSize(tester, 890)).width, 680);
    });
  });
}
