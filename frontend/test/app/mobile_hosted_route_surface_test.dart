// 根级推入页的宿主重绑回归：MobileHostedRoute 除了补 hosted scope，还必须把
// 模块调色板重绑成暗色——公开分享相册页此前未经包裹，在浅色根主题下
// 直接拿到 Frame 暖纸面，手机打开分享链接时整页亮底。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
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
}

Future<void> _run(
  WidgetTester tester, {
  required bool hostedRoute,
  required Size surface,
  required ValueChanged<Color> onSurface,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final child = Builder(
    builder: (context) {
      onSurface(context.photosColors.surface);
      return const SizedBox.shrink();
    },
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: OmniNestTheme.light(),
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
