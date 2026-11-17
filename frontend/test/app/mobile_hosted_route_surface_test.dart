// 根级推入页的宿主重绑回归：MobileHostedRoute 除了补 hosted scope，还必须把
// 极性与主题一起跟着外观设置解析——此前非实底（媒体）路由无条件钉暗，
// 浅色外观下打开相册就是一整页暗栈；样例的浅态把这些面一律铺成纸面玻璃。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('移动视口 + 宿主包装时相册调色板跟着外观设置落纸面', (tester) async {
    late Color surface;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      onSurface: (value) => surface = value,
    );

    final light = OmniNestTheme.light().extension<PhotosColors>()!;
    final dark = OmniNestTheme.dark().extension<PhotosColors>()!;
    expect(surface, light.surface);
    expect(surface, isNot(dark.surface));
  });

  testWidgets('桌面宽窗不经宿主包装时保持根主题调色板', (tester) async {
    late Color surface;
    await _run(
      tester,
      hostedRoute: false,
      surface: const Size(1440, 900),
      onSurface: (value) => surface = value,
    );

    expect(surface, OmniNestTheme.light().extension<PhotosColors>()!.surface);
  });

  testWidgets('推入路由在浅色外观下翻浅，壁纸在场也不改判', (tester) async {
    late Color ink;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      backdropActive: true,
      onProbe: (context) => context.env.ink,
      onSurface: (value) => ink = value,
    );

    expect(ink, MobileEnvPalette.light.ink);
  });

  testWidgets('推入路由在深色外观下仍是暗栈，浅根主题不参与判定', (tester) async {
    late Color ink;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      brightness: Brightness.dark,
      onProbe: (context) => context.env.ink,
      onSurface: (value) => ink = value,
    );

    expect(ink, MobileEnvPalette.dark.ink);
  });

  testWidgets('注册极性表时不抹掉既有模块调色板', (tester) async {
    late Color surface;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      onProbe: (context) => context.photosColors.surface,
      onSurface: (value) => surface = value,
    );

    expect(
      surface,
      OmniNestTheme.light().extension<PhotosColors>()!.surface,
      reason: 'copyWith 追加极性表必须按类型合并，不得替换整个扩展集',
    );
  });
}

Future<void> _run(
  WidgetTester tester, {
  required bool hostedRoute,
  required Size surface,
  required ValueChanged<Color> onSurface,
  bool backdropActive = false,
  Brightness brightness = Brightness.light,
  Color Function(BuildContext)? onProbe,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final probe = onProbe ?? (context) => context.photosColors.surface;
  final child = Builder(
    builder: (context) {
      onSurface(probe(context));
      return const SizedBox.shrink();
    },
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileShellLocalBackdropActiveProvider.overrideWithValue(
          backdropActive,
        ),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        darkTheme: OmniNestTheme.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body:
              hostedRoute
                  ? MobileHostedRoute(child: child)
                  : MobileShellScope(hosted: false, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}
