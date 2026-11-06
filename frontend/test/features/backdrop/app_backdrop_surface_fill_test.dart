import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';

/// 背景媒体层必须始终铺满宿主。
///
/// 回归点：`AppBackdropSurface` 把媒体层交给 `AnimatedSwitcher`，其默认
/// layoutBuilder 是一个 `StackFit.loose` 的 `Stack`。松约束下 `Image` 会按
/// 固有尺寸排版，`BoxFit` 完全不生效——16:9 壁纸放进更宽的窗口时左右各留一条
/// 舞台底色（暗色）硬边，`cover` / `fill` 都退化成同一副 letterbox 观感。
void main() {
  // 比 16:9 更宽的视口：只有真正铺满才不会露出左右底色。
  const viewport = Size(2400, 1000);

  AppBackdropAsset desktopBundledAsset() => AppBackdropAsset(
    id: bundledDefaultWallpaperId,
    path: bundledDesktopWallpaperAssetPath,
    title: 'OmniNest',
    mediaType: AppBackdropMediaType.image,
    sourceType: AppBackdropSourceType.bundled,
    fileSize: 0,
    modifiedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Future<void> pumpSurface(WidgetTester tester, AppBackdropFit fit) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropSelectionTargetProvider.overrideWithValue(
            AppBackdropSelectionTarget.desktop,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppBackdropSurface(
              asset: desktopBundledAsset(),
              settings: AppBackdropSettings(fit: fit),
              policy: AppBackdropPolicy.portal,
              environmentBlurSigma: 0,
              active: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final fit in <AppBackdropFit>[
    AppBackdropFit.cover,
    AppBackdropFit.fill,
  ]) {
    testWidgets('内置壁纸 ${fit.value} 铺满视口，BoxFit 生效', (tester) async {
      await pumpSurface(tester, fit);

      final images = find.byType(Image);
      expect(images, findsOneWidget);
      expect(tester.getSize(images), viewport);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('内置壁纸 contain 以模糊同图铺底，完整图叠在其上', (tester) async {
    await pumpSurface(tester, AppBackdropFit.contain);

    // 底层 cover 铺满视口，上层 contain 完整显示；两层都必须拿到紧约束，
    // 否则模糊铺底自己也会缩成固有尺寸，留白重新变成硬边。
    final images = find.byType(Image);
    expect(images, findsNWidgets(2));
    expect(tester.getSize(images.first), viewport);
    expect(tester.getSize(images.last), viewport);
    expect(tester.takeException(), isNull);
  });
}
