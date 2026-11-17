import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';

void main() {
  testWidgets('移动端基础页面表面可以独立构建', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MobilePageSurface(
          child: Scaffold(body: Center(child: Text('OmniNest'))),
        ),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('OmniNest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
