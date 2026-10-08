import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_host.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';

/// 桌面端阅读路由生效的背景策略：静态快照档，环境档位为 focus（sigma 28）。
const String _readerOwner = 'route:/reader/items/1/chapters/2';

AppBackdropState _enabledWallpaper({double blurAmount = 0}) {
  final asset = AppBackdropAsset(
    id: 'bundled-wallpaper',
    path: bundledWallpaperAssetPathFor(AppBackdropSelectionTarget.desktop),
    title: 'OmniNest',
    mediaType: AppBackdropMediaType.image,
    sourceType: AppBackdropSourceType.bundled,
    fileSize: 0,
    modifiedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  return AppBackdropState(
    backdrops: <AppBackdropAsset>[asset],
    settings: AppBackdropSettings(
      enabled: true,
      selectedBackdropId: asset.id,
      blurAmount: blurAmount,
    ),
  );
}

class _StubBackdropController extends AppBackdropController {
  _StubBackdropController(this._state);

  final AppBackdropState _state;

  @override
  Future<AppBackdropState> build() async => _state;

  @override
  Future<void> ensureFreshServerUrls({bool force = false}) async {}
}

/// 平台覆盖必须在测试体返回前复位，否则 binding 的 debug 变量自检失败。
Future<void> _withTargetPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pumpReaderBackdrop(
  WidgetTester tester, {
  required Size viewport,
  double blurAmount = 0,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      appBackdropControllerProvider.overrideWith(
        () =>
            _StubBackdropController(_enabledWallpaper(blurAmount: blurAmount)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AppBackdropHost(child: const ColoredBox(color: Colors.black)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  container
      .read(appBackdropSceneControllerProvider.notifier)
      .request(_readerOwner, AppBackdropPolicy.staticContent);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('桌面宽窗阅读路由不得叠加全屏环境模糊', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      await _pumpReaderBackdrop(tester, viewport: const Size(1440, 900));

      // 该全屏 ImageFilter.blur 层与阅读页实底合成时沿边界出现对角亮缝。
      final surface = tester.widget<AppBackdropSurface>(
        find.byType(AppBackdropSurface),
      );
      expect(surface.environmentBlurSigma, 0);
      expect(find.byType(ImageFiltered), findsNothing);
    });
  });

  testWidgets('移动壳层阅读路由仍按 focus 档折算环境模糊', (tester) async {
    await _withTargetPlatform(TargetPlatform.android, () async {
      await _pumpReaderBackdrop(tester, viewport: const Size(390, 844));

      final surface = tester.widget<AppBackdropSurface>(
        find.byType(AppBackdropSurface),
      );
      expect(
        surface.environmentBlurSigma,
        AppEnvironmentPresentation.of(AppEnvironmentMode.focus).blurSigma,
      );
      expect(find.byType(ImageFiltered), findsOneWidget);
    });
  });

  testWidgets('桌面端用户自设模糊不受形态门控影响', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      await _pumpReaderBackdrop(
        tester,
        viewport: const Size(1440, 900),
        blurAmount: 8,
      );

      expect(find.byType(ImageFiltered), findsOneWidget);
    });
  });
}
