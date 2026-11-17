import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/phone_form_factor.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget host({ThemeMode? themeMode, bool? phoneFormFactor}) {
    return ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          phoneFormFactor == null
              ? _TestAuthSessionNotifier.new
              : _AdminAuthSessionNotifier.new,
        ),
        if (phoneFormFactor != null)
          userPreferencesApiProvider.overrideWithValue(_StubPreferencesApi()),
        if (phoneFormFactor != null)
          phoneFormFactorProvider.overrideWith(
            () => _StubPhoneFormFactor(phoneFormFactor),
          ),
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

  testWidgets('弹层内循环按钮的命中区不低于 48', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();

    final chipInkWell = find.ancestor(
      of: find.byIcon(Icons.dark_mode_outlined),
      matching: find.byType(InkWell),
    );
    expect(chipInkWell, findsOneWidget);
    expect(
      tester.getRect(chipInkWell).height,
      greaterThanOrEqualTo(48),
      reason: '可见描边保持 24，命中区按壳层标准抬到 48',
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

  // 管理台入口按手机形态收敛（决策 D2）：手机隐藏、平板保留。
  testWidgets('管理员在手机形态不出现管理入口', (tester) async {
    await tester.pumpWidget(host(phoneFormFactor: true));
    await tester.pump();

    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
  });

  testWidgets('管理员在平板形态保留管理入口', (tester) async {
    await tester.pumpWidget(host(phoneFormFactor: false));
    await tester.pump();

    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
  });
}

class _TestAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return const AuthSessionState.unauthenticated();
  }
}

class _AdminAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(id: 'admin-1', username: 'admin', role: 'ADMIN'),
    );
  }
}

class _StubPhoneFormFactor extends PhoneFormFactorNotifier {
  _StubPhoneFormFactor(this.value);

  final bool value;

  @override
  bool build() => value;
}

/// 已认证会话会让菜单链路触达偏好 API，桩掉远端读取。
class _StubPreferencesApi extends UserPreferencesApi {
  _StubPreferencesApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  @override
  Future<PreferenceSnapshot> getSnapshot(String scope) async {
    return PreferenceSnapshot.empty(scope);
  }

  @override
  Future<PreferenceSnapshot> patch({
    required String scope,
    required int? baseVersion,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const {},
  }) async {
    return PreferenceSnapshot.empty(scope);
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
