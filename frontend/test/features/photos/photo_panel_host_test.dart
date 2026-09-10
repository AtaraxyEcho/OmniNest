import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_panel_host.dart';

void main() {
  Finder hostStack() => find.byType(Stack);

  Widget host({required bool visible, VoidCallback? onClose}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            PhotoPanelHost(
              visible: visible,
              onClose: onClose ?? () {},
              child: const SizedBox.expand(
                child: ColoredBox(color: Color(0xF00A0A0A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Finder bottomAnchoredFinder() {
    return find.descendant(
      of: hostStack(),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Positioned && widget.left == 0 && widget.bottom == 0,
      ),
    );
  }

  testWidgets('紧凑宽度渲染为底部滑入面板（全宽、0.8 屏高上限）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(visible: true));
    await tester.pumpAndSettle();

    final positioned = tester.widget<Positioned>(bottomAnchoredFinder());
    expect(positioned.right, 0);
    expect(positioned.width, isNull, reason: '紧凑形态为全宽，不定宽');

    final constrained = tester.widget<ConstrainedBox>(
      find.descendant(
        of: bottomAnchoredFinder(),
        matching: find.byType(ConstrainedBox),
      ),
    );
    expect(
      constrained.constraints.maxHeight,
      closeTo(860 * 0.8, 0.1),
      reason: '底部面板高度上限为 0.8 屏高',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏保持右侧 320 侧滑栏形态', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(visible: true));
    await tester.pumpAndSettle();

    final sidePanel = find.descendant(
      of: hostStack(),
      matching: find.byWidgetPredicate(
        (widget) => widget is Positioned && widget.width == photoInfoPanelWidth,
      ),
    );
    final positioned = tester.widget<Positioned>(sidePanel);
    expect(positioned.right, 0);
    expect(positioned.top, 0);
    expect(positioned.bottom, 0);

    expect(bottomAnchoredFinder(), findsNothing, reason: '宽屏不应渲染底部形态');
  });

  testWidgets('紧凑形态向下快速拖动触发关闭回调', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var closed = false;
    await tester.pumpWidget(host(visible: true, onClose: () => closed = true));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ColoredBox).last, const Offset(0, 260), 900);
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });

  testWidgets('面板容器装饰随断点切换（顶部圆角 ↔ 左描边）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final compactDecoration = photoPanelContainerDecoration(captured);
    expect(compactDecoration.borderRadius, isNotNull);
    expect(
      compactDecoration.border,
      isA<Border>().having((border) => border.top, 'top border', isNotNull),
    );

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump();
    final wideDecoration = photoPanelContainerDecoration(captured);
    expect(wideDecoration.borderRadius, isNull);
    expect(
      wideDecoration.border,
      isA<Border>().having((border) => border.left, 'left border', isNotNull),
    );
  });
}
