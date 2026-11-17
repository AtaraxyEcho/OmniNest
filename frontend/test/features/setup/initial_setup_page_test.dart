import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/domain/initial_setup_status.dart';
import 'package:omninest/features/setup/presentation/pages/initial_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 语言默认跟随系统；测试环境（Ahem 字体、en 系统语言）固定为 zh 保证
  // 断言稳定。
  Future<void> pinChineseLocale(WidgetTester tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('zh');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  }

  testWidgets('首次安装向导在桌面端和移动端均保持可滚动且不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pinChineseLocale(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(360, 760), Size(1280, 800)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSetupProvider.overrideWith(_AvailableSetupNotifier.new),
          ],
          child: const _LocaleHost(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('创建超级管理员'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull, reason: '尺寸 $size 出现布局异常');
    }
  });

  testWidgets('安装引导页右上角可切换界面语言为英文', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pinChineseLocale(tester);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSetupProvider.overrideWith(_AvailableSetupNotifier.new),
        ],
        child: const _LocaleHost(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建超级管理员'), findsOneWidget);

    // 紧凑语言切换按钮以地球图标为锚点，与表单内的默认语言下拉互不混淆。
    await tester.tap(find.byIcon(Icons.language_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('English'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create super administrator'), findsOneWidget);
    expect(find.text('创建超级管理员'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改用户名后作废已生成的两步验证二维码', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pinChineseLocale(tester);
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSetupProvider.overrideWith(_TwoFactorSetupNotifier.new),
        ],
        child: const _LocaleHost(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setupTwoFactorGenerateButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setupTwoFactorQr')), findsOneWidget);

    // 二维码里编码的是 otpauth URI 的用户名，口令与账户名一改，
    // 先前那张码就永远不会被用到，必须退回"重新生成"而不是静默提交旧秘钥。
    await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'root2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setupTwoFactorQr')), findsNothing);
    expect(
      find.byKey(const Key('setupTwoFactorGenerateButton')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// MaterialApp 语言跟随 localeControllerProvider，与真实 App 行为一致。
class _LocaleHost extends ConsumerWidget {
  const _LocaleHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(localeControllerProvider);
    return MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OmniNestTheme.light(),
      home: const InitialSetupPage(),
    );
  }
}

class _AvailableSetupNotifier extends InitialSetupController {
  @override
  Future<InitialSetupStatus> build() async {
    return const InitialSetupStatus(setupRequired: true, setupAvailable: true);
  }
}

class _TwoFactorSetupNotifier extends InitialSetupController {
  @override
  Future<InitialSetupStatus> build() async {
    return const InitialSetupStatus(
      setupRequired: true,
      setupAvailable: true,
      twoFactorRequired: true,
    );
  }

  @override
  Future<TwoFactorSetupData> newTwoFactorSecret({
    required String setupToken,
    String? username,
  }) async {
    return TwoFactorSetupData(
      secret: 'JBSWY3DPEHPK3PXP',
      otpauthUri:
          'otpauth://totp/OmniNest:$username'
          '?secret=JBSWY3DPEHPK3PXP&issuer=OmniNest',
    );
  }
}
