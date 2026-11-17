import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/app_slider.dart';

void main() {
  testWidgets('Windows 滑杆不创建 Material Slider 并响应点击', (tester) async {
    var value = 0.2;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: StatefulBuilder(
          builder:
              (context, setState) => Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 240,
                    child: AppSlider(
                      value: value,
                      onChanged: (next) => setState(() => value = next),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );

    expect(find.byType(Slider), findsNothing);
    await tester.tapAt(
      tester.getCenter(find.byType(AppSlider)) + const Offset(70, 0),
    );
    await tester.pump();

    expect(value, greaterThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows 滑杆响应键盘步进和语义增减操作', (tester) async {
    var value = 0.5;
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: StatefulBuilder(
            builder:
                (context, setState) => Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 240,
                      child: AppSlider(
                        value: value,
                        divisions: 4,
                        semanticLabel: '音量',
                        onChanged: (next) => setState(() => value = next),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      );

      await tester.tap(find.byType(AppSlider));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, 0.75);

      final node = tester.getSemantics(find.byType(AppSlider));
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.label, '音量');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('非 Windows 平台继续使用 Material Slider', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(body: AppSlider(value: 0.4, onChanged: (_) {})),
      ),
    );

    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('业务代码统一使用 AppSlider', () {
    final violations = <String>[];
    final sourceFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in sourceFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.endsWith('/core/widgets/app_slider.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\bSlider\s*\(').allMatches(source)) {
        final line = source.substring(0, match.start).split('\n').length;
        violations.add('$normalizedPath:$line');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Windows 业务页必须通过 AppSlider 避免 AXTree 滑杆缺陷',
    );
  });
}
