import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面弹层遮罩铺满窗口、不走 Navigator route', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapDesktop(
        Builder(
          builder:
              (context) => Center(
                child: DesktopButton(
                  label: 'Open modal',
                  onPressed:
                      () => showDesktopDialog<void>(
                        context,
                        builder: (_) => const DesktopDialog(title: 'Modal'),
                      ),
                ),
              ),
        ),
      ),
    );

    final barriersBefore = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('Open modal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Modal'), findsOneWidget);
    // 壳层把 Navigator 限制在侧栏/坞之间的内容区；若弹层是 showGeneralDialog
    // 的 route，ModalBarrier 会出现且 scrim 只能盖住那一块。
    expect(find.byType(ModalBarrier).evaluate().length, barriersBefore);

    final scrim = tester.renderObject<RenderBox>(
      find.byType(BackdropFilter).last,
    );
    expect(scrim.size.width, closeTo(kDesktopViewport.width, 1));
    expect(scrim.size.height, closeTo(kDesktopViewport.height, 1));

    // 遮罩本身可点击关闭。
    await tester.tapAt(const Offset(12, 12));
    await tester.pump();
    expect(find.text('Modal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
