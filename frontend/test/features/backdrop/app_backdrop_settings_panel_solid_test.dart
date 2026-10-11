// 壳层下背景设置面板必须走环境 sheet 表面：Portal 浅主题在壁纸在场时把
// surfaceContainerHigh 换成 52% 暗烟熏值，面板照它铺底会让底下的页面透成灰板
//（实机反馈"展开设置页面透明"）。样例浅态的 sheet 族是 82% 白玻璃，
// 所以守卫的量法是"亮面 + 等于 sheetSolid"，不是"必须不透明"。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_settings_panel.dart';

class _StubBackdropController extends AppBackdropController {
  @override
  Future<AppBackdropState> build() async => const AppBackdropState();

  @override
  Future<void> ensureFreshServerUrls({bool force = false}) async {}
}

Future<Color?> _panelFill(
  WidgetTester tester, {
  required MobileEnvPalette palette,
}) async {
  final container = ProviderContainer(
    overrides: [
      appBackdropControllerProvider.overrideWith(_StubBackdropController.new),
    ],
  );
  addTearDown(container.dispose);

  // 桌面 Portal 在浅主题 + 壁纸在场时给的就是这套半透容器色。
  final theme = OmniNestTheme.light().copyWith(
    colorScheme: OmniNestTheme.light().colorScheme.copyWith(
      surfaceContainerHigh: const Color(0x85172328),
    ),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme.copyWith(extensions: [palette]),
        home: MobileShellScope(
          hosted: true,
          child: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showAppBackdropSettings(context),
                      child: const Text('打开背景设置'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开背景设置'));
  await tester.pumpAndSettle();

  final fill = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(Dialog),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (fill.decoration as BoxDecoration).color;
}

void main() {
  // 守卫的是"不跟桌面那档 52% 暗烟熏容器色"。样例第 4 层把 sheet 族从
  // 半透玻璃改成实色 #f1f4ed + `backdrop-filter: none`，所以这里判的是
  // "浅态面板必须是亮实底"，不再判 α=0.82。
  testWidgets('壳层浅极性下面板底取样例的实色纸面，而不是半透暗容器色', (tester) async {
    final color = await _panelFill(tester, palette: MobileEnvPalette.light);

    expect(color, MobileEnvPalette.light.sheetSolid);
    expect(color!.a, 1, reason: '样例浅态 sheet 族是实色且不再叠 blur');
    expect(color.r, greaterThan(0.9), reason: '浅态表面必须是亮面，不能透暗');
    expect(color.g, greaterThan(0.9));
    expect(color.b, greaterThan(0.9));
  });

  testWidgets('壳层暗极性下面板同样落在 sheet 表面上', (tester) async {
    final color = await _panelFill(tester, palette: MobileEnvPalette.dark);

    expect(color, MobileEnvPalette.dark.sheetSolid);
    expect(color!.a, 1);
  });
}
