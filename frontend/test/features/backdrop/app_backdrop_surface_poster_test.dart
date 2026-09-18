import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_video_view.dart';

void main() {
  testWidgets('内置默认壁纸为打包静态图,立即渲染且不建视频会话', (tester) async {
    final asset = AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: bundledDefaultWallpaperAssetPath,
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
              asset: asset,
              settings: const AppBackdropSettings(),
              policy: AppBackdropPolicy.portalMobile,
              active: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    bool isBundledImage(Widget widget) =>
        widget is Image && widget.image is AssetImage;

    // 内置壁纸直接渲染打包资产,不得再挂视频层。
    expect(
      find.image(const AssetImage(bundledDefaultWallpaperAssetPath)),
      findsOneWidget,
    );
    expect(find.byWidgetPredicate(isBundledImage), findsOneWidget);
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
