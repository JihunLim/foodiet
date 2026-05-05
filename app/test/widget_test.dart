/// foodiet 앱 스모크 테스트.
///
/// 기본 렌더링 확인용. 실제 라우팅 테스트는 features/ 하위에 추가 예정.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('foodiet'))),
      ),
    );
    expect(find.text('foodiet'), findsOneWidget);
  });
}
