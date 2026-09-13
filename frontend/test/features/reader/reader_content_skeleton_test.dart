import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_skeleton.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  testWidgets('章节加载指示器在窄屏与短横屏中稳定渲染', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [Size(320, 568), Size(640, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderContentSkeleton(
              settings: ReaderViewSettings(paletteId: 'dark'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('readerContentSkeleton')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
