import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/app_min_width_guard.dart';
import 'package:omninest/core/widgets/app_form_factor.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// hover 能力 × 宽度矩阵（触屏笔电/平板桌面模式 vs 纯桌面浏览器）。
void main() {
  Widget probe({required bool hoverCapable, required bool mobileForm}) {
    return MaterialApp(
      home: DesktopFormMinWidth(
        mobileForm: mobileForm,
        hoverCapable: hoverCapable,
        child: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  testWidgets('hover 桌面窄窗固定最小宽并横向滚动', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      probe(hoverCapable: true, mobileForm: false),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('无 hover 窄窗放行触屏布局', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      probe(hoverCapable: false, mobileForm: false),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  test('画布形态：hosted 强制触屏，非托管按 workbenchRail', () {
    expect(
      resolveOmniCanvasForm(maxWidth: 1280, hosted: true),
      OmniCanvasForm.touchCanvas,
    );
    expect(
      resolveOmniCanvasForm(
        maxWidth: ResponsiveBreakpoints.workbenchRail - 1,
        hosted: false,
      ),
      OmniCanvasForm.touchCanvas,
    );
    expect(
      resolveOmniCanvasForm(
        maxWidth: ResponsiveBreakpoints.workbenchRail,
        hosted: false,
      ),
      OmniCanvasForm.desktopRail,
    );
  });
}
