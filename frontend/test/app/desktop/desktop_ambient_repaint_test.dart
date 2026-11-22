import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart'
    show bundledDefaultWallpaperAssetPath;

import 'desktop_test_harness.dart';

/// 环境光拆层的重绘闸门与 4×3 色网/艺术面板验证。
///
/// 锁定的是「谁在哪一层」而不是像素：漂移色场必须是「静态纹理保留层 +
/// 其上 Transform」，色网与暗纱/噪点必须是静态层，右侧 64% 艺术面板位于
/// 独立 `ambient-art` 边界，子树里互不拖累重绘。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DesktopAmbientMeshCache.instance.clearForTest();
  });

  Future<void> pumpAmbient(
    WidgetTester tester, {
    required bool reduceMotion,
    double intensity = 70,
    bool showArt = false,
    String imageUrl = 'https://example.test/cover.jpg',
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapDesktop(
        DesktopAmbient(
          imageUrl: imageUrl,
          intensity: intensity,
          reduceMotion: reduceMotion,
          showArt: showArt,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('色网与暗纱是静态层，色场单独一层且由 ticker 驱动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAmbient(tester, reduceMotion: false);

      final cover = find.byKey(const ValueKey('ambient-cover'));
      final blobs = find.byKey(const ValueKey('ambient-blobs'));
      final veil = find.byKey(const ValueKey('ambient-veil'));
      expect(cover, findsOneWidget);
      expect(blobs, findsOneWidget);
      expect(veil, findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-art')), findsNothing);

      // 静态层里不能有任何 AnimatedBuilder。
      expect(
        find.descendant(of: cover, matching: find.byType(AnimatedBuilder)),
        findsNothing,
      );
      expect(
        find.descendant(of: veil, matching: find.byType(AnimatedBuilder)),
        findsNothing,
      );
      // 色场层由 AnimatedBuilder 驱动 Transform。
      expect(
        find.descendant(of: blobs, matching: find.byType(AnimatedBuilder)),
        findsWidgets,
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reduce-motion 下三团与艺术层停帧，不产生任何 transient 回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAmbient(tester, reduceMotion: true, showArt: true);

      expect(find.byKey(const ValueKey('ambient-cover')), findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-art')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('intensity 为 0 时整层不构建', (tester) async {
    await pumpAmbient(tester, reduceMotion: false, intensity: 0, showArt: true);

    expect(find.byKey(const ValueKey('ambient-cover')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-art')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-blobs')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('4×3 矢量色网渲染替换旧 64px 裸拉伸，且 showArt 独立隔离艺术层', (tester) async {
    final testGrid = AmbientMeshGrid(
      points: List<Color>.generate(
        12,
        (i) => Color.fromARGB(255, 20 + i * 15, 60 + i * 10, 120 + i * 8),
      ),
      average: const Color(0xFF5A78A0),
    );
    DesktopAmbientMeshCache.instance.putForTest(
      bundledDefaultWallpaperAssetPath,
      testGrid,
    );

    await pumpAmbient(
      tester,
      reduceMotion: true,
      showArt: true,
      imageUrl: bundledDefaultWallpaperAssetPath,
    );

    final cover = find.byKey(const ValueKey('ambient-cover'));
    final art = find.byKey(const ValueKey('ambient-art'));
    final blobs = find.byKey(const ValueKey('ambient-blobs'));
    final veil = find.byKey(const ValueKey('ambient-veil'));
    expect(cover, findsOneWidget);
    expect(art, findsOneWidget);
    expect(blobs, findsOneWidget);
    expect(veil, findsOneWidget);

    // ambient-cover 内走 DesktopAmbientMeshSurface + AmbientColourMeshPainter，不再包含 64px 裸 Image。
    expect(
      find.descendant(
        of: cover,
        matching: find.byType(DesktopAmbientMeshSurface),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cover, matching: find.byType(Image)),
      findsNothing,
    );
    final customPaints = tester.widgetList<CustomPaint>(
      find.descendant(of: cover, matching: find.byType(CustomPaint)),
    );
    expect(
      customPaints.any((cp) => cp.painter is AmbientColourMeshPainter),
      isTrue,
      reason: '4×3 色网命中缓存后应使用 AmbientColourMeshPainter 矢量绘制',
    );

    // ambient-art 渲染 EditorialArtPanel，按 1280px 高清解码随包资产。
    expect(
      find.descendant(of: art, matching: find.byType(EditorialArtPanel)),
      findsOneWidget,
    );
    final artImage = tester.widget<Image>(
      find.descendant(of: art, matching: find.byType(Image)),
    );
    final provider = artImage.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).imageProvider, isA<AssetImage>());
    expect(provider.width, 1280);
  });
}
