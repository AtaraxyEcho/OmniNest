// 视觉环境抽屉走 useRootNavigator，且 showModalBottomSheet 会把属主链上的
// Theme 冻结进模态子树（InheritedTheme.capture）：抽屉里 Theme.of 要么没有
// 极性注册（MobileEnvPalette.of 退回暗基准，切"浅色模式"成了空操作），
// 要么是打开那一刻的旧主题（翻设置不跟随）。
// 这里守住两件事：① 抽屉表面按外观设置取极性；② 抽屉保持打开时翻外观即刻跟随。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/backdrop/presentation/mobile_env_settings_sheet.dart';

const ValueKey<String> _sheetSurfaceKey = ValueKey<String>(
  'omninest.envSheet.surface',
);

/// 桩外观控制器读取的极性问题：每个用例先复位为浅色。
ThemeMode _sheetThemeMode = ThemeMode.light;

/// 桩外观控制器：只喂极性判定，不写 SharedPreferences、不接鉴权与偏好同步。
class _StubAppearanceController extends AppearanceController {
  @override
  ThemeMode build() => _sheetThemeMode;
}

/// 空图库桩控制器：抽屉只读状态，测试不碰 drift 与网络。
class _StubBackdropController extends AppBackdropController {
  @override
  Future<AppBackdropState> build() async => const AppBackdropState();

  @override
  Future<void> syncFromServer() async {}

  @override
  Future<void> ensureFreshServerUrls({bool force = false}) async {}
}

ProviderContainer _createContainer() {
  final container = ProviderContainer(
    overrides: [
      appearanceControllerProvider.overrideWith(_StubAppearanceController.new),
      appBackdropControllerProvider.overrideWith(_StubBackdropController.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 与 lib/app/app.dart 同一条链路：外观设置（ThemeMode）→ MaterialApp 主题。
Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final mode = ref.watch(appearanceControllerProvider);
        return MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.light(),
          darkTheme: OmniNestTheme.dark(),
          themeMode: mode,
          // 极性注册在页面子树里，根 Navigator 在它之上，抽屉取不到——
          // 这正是缺陷现场。
          home: MobileEnvironmentScope(
            child: Builder(
              builder:
                  (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showMobileEnvSettingsSheet(context),
                        child: const Text('打开视觉环境'),
                      ),
                    ),
                  ),
            ),
          ),
        );
      },
    ),
  );
}

/// 手机尺寸 + 指定极性下打开抽屉；返回容器供后续翻设置使用。
Future<ProviderContainer> _pumpOpenSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = _createContainer();
  await tester.pumpWidget(_harness(container));
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开视觉环境'));
  await tester.pumpAndSettle();
  return container;
}

/// 翻外观设置：MaterialApp 主题随 provider 重建，抽屉保持打开不重开。
Future<void> _flipAppearance(
  WidgetTester tester,
  ProviderContainer container,
  ThemeMode mode,
) async {
  _sheetThemeMode = mode;
  container.invalidate(appearanceControllerProvider);
  await tester.pumpAndSettle();
}

Color _sheetSurfaceColor(WidgetTester tester) {
  final surface = tester.widget<DecoratedBox>(find.byKey(_sheetSurfaceKey));
  return (surface.decoration as BoxDecoration).color!;
}

Color _sheetInkColor(WidgetTester tester) {
  // 关闭位换成样例 48 玻璃圆钮后，字形是 OmniIcons.close 矢量。
  return tester
      .widget<OmniIcon>(
        find.descendant(
          of: find.byType(MobileGlassIconButton),
          matching: find.byType(OmniIcon),
        ),
      )
      .color!;
}

void main() {
  setUp(() {
    _sheetThemeMode = ThemeMode.light;
  });

  testWidgets('视觉环境抽屉浅极性下画纸面实底而不是暗基准', (tester) async {
    await _pumpOpenSheet(tester);

    expect(find.byKey(_sheetSurfaceKey), findsOneWidget);
    expect(_sheetSurfaceColor(tester), MobileEnvPalette.light.sheetSolid);
    expect(
      _sheetSurfaceColor(tester),
      isNot(MobileEnvPalette.dark.sheetSolid),
      reason: '浅极性下不得退回暗基准',
    );
    expect(_sheetInkColor(tester), MobileEnvPalette.light.ink);
  });

  testWidgets('视觉环境抽屉深极性下画深色实底', (tester) async {
    _sheetThemeMode = ThemeMode.dark;
    await _pumpOpenSheet(tester);

    expect(_sheetSurfaceColor(tester), MobileEnvPalette.dark.sheetSolid);
    expect(_sheetInkColor(tester), MobileEnvPalette.dark.ink);
  });

  testWidgets('抽屉关闭位是 48 玻璃圆钮配样例 close 矢量', (tester) async {
    await _pumpOpenSheet(tester);

    final close = find.byType(MobileGlassIconButton);
    expect(close, findsOneWidget);
    final rect = tester.getRect(close);
    expect(rect.width, 48);
    expect(rect.height, 48);
    expect(
      tester.widget<MobileGlassIconButton>(close).vector,
      OmniIcons.close,
      reason: '样例 .sheet-head 关闭位是 .icon-button + 同源 close，不留 Material 字形',
    );
  });

  testWidgets('抽屉不重开，仅翻外观设置也必须跟随极性', (tester) async {
    final container = await _pumpOpenSheet(tester);

    expect(_sheetSurfaceColor(tester), MobileEnvPalette.light.sheetSolid);

    await _flipAppearance(tester, container, ThemeMode.dark);

    expect(
      find.byKey(_sheetSurfaceKey),
      findsOneWidget,
      reason: '抽屉没有被重开，仍是同一个表面',
    );
    expect(_sheetSurfaceColor(tester), MobileEnvPalette.dark.sheetSolid);
    expect(_sheetInkColor(tester), MobileEnvPalette.dark.ink);

    await _flipAppearance(tester, container, ThemeMode.light);

    expect(_sheetSurfaceColor(tester), MobileEnvPalette.light.sheetSolid);
    expect(_sheetInkColor(tester), MobileEnvPalette.light.ink);
  });
}
