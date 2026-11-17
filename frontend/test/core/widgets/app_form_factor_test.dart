import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/app_form_factor.dart';
import 'package:omninest/core/widgets/hosted_touch_canvas.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 读取子树同时可见的 MediaQuery 宽与 LayoutBuilder 约束宽。
class _WidthProbe extends StatelessWidget {
  const _WidthProbe({this.formKey, this.constraintsKey});

  final Key? formKey;
  final Key? constraintsKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final form = omniCanvasFormOf(context, constraints);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'media:${MediaQuery.sizeOf(context).width.toStringAsFixed(0)}',
              key: formKey,
            ),
            Text(
              'constraints:${constraints.maxWidth.toStringAsFixed(0)}'
              ' form:${form.name}',
              key: constraintsKey,
            ),
          ],
        );
      },
    );
  }
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size viewport, {
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: MediaQueryData(size: viewport), child: child),
    ),
  );
  await tester.pump();
}

void main() {
  group('resolveOmniCanvasForm', () {
    test('托管态无论宽度一律触屏画布', () {
      expect(
        resolveOmniCanvasForm(maxWidth: 1280, hosted: true),
        OmniCanvasForm.touchCanvas,
      );
      expect(
        resolveOmniCanvasForm(maxWidth: 360, hosted: true),
        OmniCanvasForm.touchCanvas,
      );
    });

    test('非托管以 workbenchRail 为界', () {
      expect(
        resolveOmniCanvasForm(
          maxWidth: ResponsiveBreakpoints.workbenchRail,
          hosted: false,
        ),
        OmniCanvasForm.desktopRail,
      );
      expect(
        resolveOmniCanvasForm(maxWidth: 1023.9, hosted: false),
        OmniCanvasForm.touchCanvas,
      );
    });
  });

  group('HostedTouchCanvas', () {
    testWidgets('托管平板：MediaQuery 与约束宽同为画布上限', (tester) async {
      await _pumpAt(
        tester,
        const Size(1280, 800),
        child: MobileShellScope(
          hosted: true,
          child: HostedTouchCanvas(
            hosted: true,
            maxContentWidth: 720,
            child: const _WidthProbe(
              formKey: Key('media'),
              constraintsKey: Key('constraints'),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('media')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('media'))).data,
        'media:720',
        reason: '画布限宽必须同步到 MediaQuery，否则子树读屏幕宽会判反',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('constraints')))
            .data!
            .startsWith('constraints:720 form:touchCanvas'),
        isTrue,
      );
    });

    testWidgets('非托管宽窗仍走桌面侧栏画布', (tester) async {
      await _pumpAt(
        tester,
        const Size(1280, 800),
        child: HostedTouchCanvas(
          hosted: false,
          maxContentWidth: 720,
          child: const _WidthProbe(constraintsKey: Key('constraints')),
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('constraints')))
            .data!
            .contains('form:desktopRail'),
        isTrue,
      );
    });
  });
}
