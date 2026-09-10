import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget host({ThemeMode? themeMode}) {
    return ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
        if (themeMode != null)
          appearanceControllerProvider.overrideWith(
            () => _FixedAppearanceController(themeMode),
          ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: Center(child: UserAvatarMenu())),
      ),
    );
  }

  testWidgets('头像菜单面板为直角 hairline 卡片并按主题令牌着色', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('外观'));
    final colors = Theme.of(context).colorScheme;
    final panelMaterial =
        tester
            .widgetList<Material>(find.byType(Material))
            .where(
              (widget) =>
                  widget.elevation == 6 &&
                  widget.shape is RoundedRectangleBorder &&
                  (widget.shape! as RoundedRectangleBorder).borderRadius ==
                      BorderRadius.zero,
            )
            .toList();
    expect(panelMaterial, hasLength(1));
    expect(panelMaterial.first.color, colors.surfaceContainerLow);
    expect(
      (panelMaterial.first.shape! as RoundedRectangleBorder).side.color,
      colors.outlineVariant,
    );
  });

  testWidgets('头像菜单语言行内按钮切换全局语言且不关闭面板', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      localeDeviceLanguageKey: 'zh',
    });
    await tester.pumpWidget(host());
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UserAvatarMenu)),
    );
    expect(container.read(localeControllerProvider), 'zh');

    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();
    // 按钮显示切换目标：当前中文 → English
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(container.read(localeControllerProvider), 'en');
    expect(find.text('语言'), findsOneWidget);

    // 再次点击目标「中文」切回
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(container.read(localeControllerProvider), 'zh');
  });

  testWidgets('头像菜单主题仅在浅色与深色间切换且不回到跟随系统', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UserAvatarMenu)),
    );
    expect(container.read(appearanceControllerProvider), ThemeMode.system);

    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();
    // 跟随系统不参与循环：点击后直接进入深色
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceControllerProvider), ThemeMode.dark);
    expect(find.text('跟随系统'), findsNothing);

    await tester.tap(find.text('浅色模式'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceControllerProvider), ThemeMode.light);

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceControllerProvider), ThemeMode.dark);
    expect(find.text('外观'), findsOneWidget);
  });
}

class _TestAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return const AuthSessionState.unauthenticated();
  }
}

class _FixedAppearanceController extends AppearanceController {
  _FixedAppearanceController(this.initial);

  final ThemeMode initial;

  @override
  ThemeMode build() => initial;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
  }
}
