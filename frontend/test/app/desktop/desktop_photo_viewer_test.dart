import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_photo_viewer_page.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpViewer(WidgetTester tester, {String photoId = 'p-0'}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          photoDetailProvider.overrideWith(
            (ref, id) async =>
                id == 'p-1'
                    ? seededPhoto
                    : seededPhotoDashboard.recentPhotos.firstWhere(
                      (photo) => photo.id == id,
                    ),
          ),
        ],
        child: wrapDesktop(DesktopPhotoViewerPage(photoId: photoId)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('顶栏给出序号与总数，胶片条可切换当前照片', (tester) async {
    await pumpViewer(tester);

    expect(find.text('1 of 7'), findsOneWidget);
    expect(find.text('Frame 1'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('viewer-thumb-p-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  });

  testWidgets('胶片条底部遮罩是暗色而非白色光晕', (tester) async {
    await pumpViewer(tester);

    final darkFilmstrip = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration) return false;
      final gradient = decoration.gradient;
      return gradient is LinearGradient &&
          gradient.colors.length == 2 &&
          gradient.colors.first == Colors.transparent &&
          gradient.colors.last == const Color(0x59000000);
    });
    expect(darkFilmstrip, findsOneWidget);
  });

  testWidgets('信息面板展示相机与尺寸', (tester) async {
    await pumpViewer(tester, photoId: 'p-1');

    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Dimensions'), findsOneWidget);
    expect(find.textContaining('Fujifilm'), findsWidgets);
  });

  testWidgets('缩放按钮把比例推到上限后不再溢出', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byIcon(Icons.zoom_in_rounded));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
