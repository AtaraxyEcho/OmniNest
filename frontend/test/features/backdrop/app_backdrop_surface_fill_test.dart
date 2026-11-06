import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';

/// 背景媒体层必须始终铺满宿主。
///
/// 回归点：`AppBackdropSurface` 把媒体层交给 `AnimatedSwitcher`，其默认
/// layoutBuilder 是一个 `StackFit.loose` 的 `Stack`。松约束下图片会按
/// 固有尺寸排版，`BoxFit` 完全不生效——16:9 素材放进更宽的窗口时左右各留一条
/// 舞台底色（暗色）硬边，`cover` / `fill` 都退化成同一副 letterbox 观感。
///
/// 内置默认壁纸换成视频后，这一层由封面帧（`Image.asset`）承担同样的职责：
/// 它是视频就绪前唯一的可见内容，同样必须拿到紧约束。
void main() {
  // 比 16:9 更宽的视口：只有真正铺满才不会露出左右底色。
  const viewport = Size(2400, 1000);

  AppBackdropAsset bundledVideoAsset() => AppBackdropAsset(
    id: bundledDefaultWallpaperId,
    path: bundledDefaultWallpaperAssetPath,
    title: 'OmniNest',
    mediaType: AppBackdropMediaType.video,
    sourceType: AppBackdropSourceType.bundled,
    fileSize: 0,
    modifiedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    thumbnailPath: bundledDefaultWallpaperPosterAssetPath,
  );

  Future<void> pumpSurface(WidgetTester tester, AppBackdropFit fit) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppBackdropSurface(
              asset: bundledVideoAsset(),
              settings: AppBackdropSettings(fit: fit),
              policy: AppBackdropPolicy.portal,
              environmentBlurSigma: 0,
              active: false,
            ),
          ),
        ),
      ),
    );
    // 不 pumpAndSettle：视频会话会在 post-frame 打开一个必然失败的播放器，
    // 本用例只关心封面帧拿到的约束。
    await tester.pump();
  }

  for (final fit in <AppBackdropFit>[
    AppBackdropFit.cover,
    AppBackdropFit.fill,
    AppBackdropFit.contain,
  ]) {
    testWidgets('内置壁纸 ${fit.value} 铺满视口，BoxFit 生效', (tester) async {
      await pumpSurface(tester, fit);

      final images = find.byType(Image);
      expect(images, findsOneWidget);
      expect(tester.getSize(images), viewport);
      expect(tester.takeException(), isNull);
    });
  }
}
