import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_video_view.dart';

void main() {
  Future<void> pumpBundledSurface(WidgetTester tester) async {
    final asset = AppBackdropAsset(
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

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppBackdropSurface(
              asset: asset,
              settings: const AppBackdropSettings(),
              policy: AppBackdropPolicy.portalMobile,
              environmentBlurSigma: 0,
              active: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('内置默认壁纸是打包视频：封面帧垫底且视频层同时挂载', (tester) async {
    await pumpBundledSurface(tester);

    // 视频首帧受解码与打开耗时影响，封面帧必须先铺满，避免露出舞台底色。
    expect(
      find.image(const AssetImage(bundledDefaultWallpaperPosterAssetPath)),
      findsOneWidget,
    );
    expect(find.byType(AppBackdropVideoView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史 v2 图片档的内置壁纸行回退封面帧而不是错误底纹', (tester) async {
    // 升级前的数据库里存着 mediaType=image 的内置行，素材文件已随 v3 删除。
    // 这一行要到下一次 ensureBundledBackdrop 才会被覆盖，期间不能显示错误图标。
    final legacy = AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: 'assets/backdrops/default_desktop.jpg',
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.image,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 0,
      modifiedAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppBackdropSurface(
              asset: legacy,
              settings: const AppBackdropSettings(),
              policy: AppBackdropPolicy.portalMobile,
              environmentBlurSigma: 0,
              active: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.image(const AssetImage(bundledDefaultWallpaperPosterAssetPath)),
      findsOneWidget,
    );
    expect(find.byType(AppBackdropVideoView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motionAllowed=false 时视频层仍挂载，避免模块切换重开闪烁', (tester) async {
    final asset = AppBackdropAsset(
      id: 'server-video',
      path: 'https://example.com/wallpaper.mp4',
      title: 'server video',
      mediaType: AppBackdropMediaType.video,
      sourceType: AppBackdropSourceType.server,
      fileSize: 1,
      modifiedAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropControllerProvider.overrideWith(_StubController.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppBackdropSurface(
              asset: asset,
              settings: const AppBackdropSettings(),
              policy: AppBackdropPolicy.work,
              environmentBlurSigma: 0,
              active: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 实底模块（Photos/Files 等）策略下不得把 Video 组件从树中拆掉。
    expect(find.byType(AppBackdropVideoView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 隔离真实控制器:视频打开失败触发的签名 URL 刷新不进测试环境。
class _StubController extends AppBackdropController {
  @override
  Future<AppBackdropState> build() async => const AppBackdropState();

  @override
  Future<void> ensureFreshServerUrls({bool force = false}) async {}
}
