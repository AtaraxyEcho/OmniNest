import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/hosted_touch_canvas.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 折叠屏/横竖屏切换（D8）：宽度变化只重算布局，不重挂载子树。
void main() {
  testWidgets('HostedTouchCanvas 宽度切换保留滚动位置与 State', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final stateKey = GlobalKey<_ProbeState>();

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HostedTouchCanvas(
              hosted: true,
              maxContentWidth: MobileLayoutTokens.chromeMaxWidth,
              child: _Probe(
                key: stateKey,
                controller: scrollController,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAt(360);
    final stateBefore = stateKey.currentState;
    expect(stateBefore, isNotNull);
    scrollController.jumpTo(120);
    await tester.pump();

    // 展开到平板宽度再折回。
    await pumpAt(840);
    await pumpAt(360);

    final stateAfter = stateKey.currentState;
    expect(
      identical(stateBefore, stateAfter),
      isTrue,
      reason: '宽度切换不得重挂载内容 State（折叠展开/旋转）',
    );
    expect(scrollController.offset, 120);
    expect(stateAfter!.buildCount, greaterThan(1));
    expect(stateAfter.disposeCount, 0);
  });

  testWidgets('HostedTouchCanvas 托管态 MediaQuery 宽与画布一致', (tester) async {
    tester.view.physicalSize = const Size(840, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    double? canvasWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HostedTouchCanvas(
            hosted: true,
            maxContentWidth: MobileLayoutTokens.chromeMaxWidth,
            child: Builder(
              builder: (context) {
                canvasWidth = MediaQuery.sizeOf(context).width;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    expect(canvasWidth, MobileLayoutTokens.chromeMaxWidth);
    expect(
      MobileLayoutTokens.chromeMaxWidth,
      lessThan(ResponsiveBreakpoints.desktop),
    );
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int buildCount = 0;
  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return ListView.builder(
      controller: widget.controller,
      itemCount: 50,
      itemBuilder:
          (context, index) => SizedBox(height: 40, child: Text('$index')),
    );
  }
}
