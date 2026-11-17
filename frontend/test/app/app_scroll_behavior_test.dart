import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/app_scroll_behavior.dart';

void main() {
  testWidgets('Windows 滚动视口禁用 Tooltip 浮层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const OmniNestScrollBehavior(),
        home: ListView(
          children: const [Tooltip(message: 'Play', child: Text('Track'))],
        ),
      ),
    );

    final visibility = tester.widgetList<TooltipVisibility>(
      find.byType(TooltipVisibility),
    );
    expect(visibility.any((widget) => !widget.visible), isTrue);
  });
}
