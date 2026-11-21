import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_setup_page.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/domain/initial_setup_status.dart';

import 'desktop_test_harness.dart';

class _SeededSetup extends InitialSetupController {
  _SeededSetup(this.seed);

  final InitialSetupStatus seed;

  @override
  Future<InitialSetupStatus> build() async => seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSetup(WidgetTester tester, {bool twoFactor = false}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          initialSetupProvider.overrideWith(
            () => _SeededSetup(
              InitialSetupStatus(
                setupRequired: true,
                setupAvailable: true,
                twoFactorRequired: twoFactor,
              ),
            ),
          ),
        ],
        child: wrapDesktop(const DesktopSetupPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('首启向导给出品牌条与两段表单', (tester) async {
    await pumpSetup(tester);

    expect(find.text('OmniNest'), findsWidgets);
    expect(find.textContaining('multiple storage'), findsOneWidget);
    expect(find.text('First-time setup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('setup-top-language')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('setup-token')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('setup-username')),
      findsOneWidget,
    );
    expect(find.text('Create super administrator'), findsOneWidget);
  });

  testWidgets('密码过短时在提交前拦下', (tester) async {
    await pumpSetup(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('setup-token')),
      'token-12345678',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('setup-password')),
      'short',
    );
    await tester.tap(find.text('Create super administrator'));
    await tester.pump();

    expect(find.textContaining('between 8 and 64'), findsOneWidget);
  });

  testWidgets('要求两步验证时出现生成二维码入口', (tester) async {
    await pumpSetup(tester, twoFactor: true);

    expect(find.text('Generate QR code'), findsOneWidget);
  });

  testWidgets('字段里回车等同点提交，仍然先跑校验', (tester) async {
    await pumpSetup(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('setup-token')),
      'token-12345678',
    );
    final password = find.byKey(const ValueKey<String>('setup-password'));
    await tester.enterText(password, 'short');
    await tester.pump();

    // 焦点停在密码框时按 Enter：`<form onSubmit>` 的等价路径。
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('between 8 and 64'), findsOneWidget);
  });

  testWidgets('密码强度计四段随输入点亮', (tester) async {
    await pumpSetup(tester);

    List<Color?> barColors() =>
        tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .where((box) => box.constraints?.maxHeight == 4)
            .map((box) => (box.decoration! as BoxDecoration).color)
            .toList();

    // 样例 `Setup.tsx:149`：`pass && <div className="sf-meter">`，空密码不渲染。
    final skin = DesktopSkin.of(
      tester.element(find.byKey(const ValueKey<String>('setup-password'))),
    );
    expect(barColors(), isEmpty);

    final password = find.byKey(const ValueKey<String>('setup-password'));
    await tester.enterText(password, 'Abcdef12');
    await tester.pump(const Duration(milliseconds: 320));

    // 有输入后是四段；大写+小写+数字且 8 位至少点亮三段。
    expect(barColors(), hasLength(4));
    final lit = barColors().where((color) => color != skin.line).length;
    expect(lit, greaterThanOrEqualTo(3));
  });
}
