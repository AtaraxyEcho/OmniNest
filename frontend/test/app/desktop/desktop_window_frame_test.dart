import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_frame.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面窗口四周铺八条缩放带，中心区域不拦截点击', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var tapped = false;
    try {
      tester.view.physicalSize = kDesktopViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: wrapDesktop(
            DesktopWindowFrame(
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped = true,
                  child: const SizedBox(width: 200, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              (widget.cursor == SystemMouseCursors.resizeUpDown ||
                  widget.cursor == SystemMouseCursors.resizeLeftRight ||
                  widget.cursor == SystemMouseCursors.resizeUpLeftDownRight ||
                  widget.cursor == SystemMouseCursors.resizeUpRightDownLeft),
        ),
        findsNWidgets(8),
      );

      // 内容区仍能正常点击：缩放带只占最外圈 5px。
      await tester.tapAt(const Offset(800, 500));
      await tester.pump();
      expect(tapped, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('移动形态不铺缩放带', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: wrapDesktop(
            const DesktopWindowFrame(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.resizeUpDown,
        ),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
