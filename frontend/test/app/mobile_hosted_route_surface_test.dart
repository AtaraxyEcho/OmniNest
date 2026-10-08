// 根级推入页的宿主重绑回归：MobileHostedRoute 除了补 hosted scope，还必须把
// 模块调色板重绑成暗色——公开分享相册页此前未经包裹，在浅色根主题下
// 直接拿到 Frame 暖纸面，手机打开分享链接时整页亮底。
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
  testWidgets('移动视口 + 宿主包装时相册调色板重绑为暗色', (tester) async {
    late Color surface;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      onSurface: (value) => surface = value,
    );

    final dark = OmniNestTheme.dark().extension<PhotosColors>()!;
    final light = OmniNestTheme.light().extension<PhotosColors>()!;
    expect(surface, dark.surface);
    expect(surface, isNot(light.surface));
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

  testWidgets('实底工具路由在无壁纸的浅色根主题下随主题翻浅', (tester) async {
    late Color ink;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      solidSurface: true,
      onProbe: (context) => context.env.ink,
      onSurface: (value) => ink = value,
    );

    expect(ink, MobileEnvPalette.light.ink);
    expect(ink, isNot(MobileEnvPalette.dark.ink));
  });

  testWidgets('实底浅面注册极性表时不抹掉既有模块调色板', (tester) async {
    late Color surface;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      solidSurface: true,
      onProbe: (context) => context.photosColors.surface,
      onSurface: (value) => surface = value,
    );

    expect(
      surface,
      OmniNestTheme.light().extension<PhotosColors>()!.surface,
      reason: 'copyWith 追加极性表必须按类型合并，不得替换整个扩展集',
    );
  });

  testWidgets('实底工具路由在壁纸在场时仍锁暗环境基底', (tester) async {
    late Color ink;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      solidSurface: true,
      backdropActive: true,
      onProbe: (context) => context.env.ink,
      onSurface: (value) => ink = value,
    );

    expect(ink, MobileEnvPalette.dark.ink);
  });

  testWidgets('环境档路由（媒体模块）不受实底标记影响', (tester) async {
    late Color ink;
    await _run(
      tester,
      hostedRoute: true,
      surface: const Size(390, 844),
      onProbe: (context) => context.env.ink,
      onSurface: (value) => ink = value,
    );

    expect(ink, MobileEnvPalette.dark.ink);
  });
}

Future<void> _run(
  WidgetTester tester, {
  required bool hostedRoute,
  required Size surface,
  required ValueChanged<Color> onSurface,
  bool solidSurface = false,
  bool backdropActive = false,
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
        home: Scaffold(
          body:
              hostedRoute
                  ? MobileHostedRoute(solidSurface: solidSurface, child: child)
                  : MobileShellScope(hosted: false, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}
