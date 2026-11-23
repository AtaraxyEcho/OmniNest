import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart'
    show bundledDefaultWallpaperAssetPath;

import 'desktop_test_harness.dart';

/// 环境光拆层的重绘闸门、4×3 色网/全出血艺术层、Reader 光池、Plain 纯净模式与双缓冲切换验证。
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
    bool isReaderRoute = false,
    EditorialArtPreset artPreset = EditorialArtPreset.landscape,
    Color? fallbackTone,
    String? imageUrl = 'https://example.test/cover.jpg',
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
          isReaderRoute: isReaderRoute,
          artPreset: artPreset,
          fallbackTone: fallbackTone,
        ),
      ),
    );
    await tester.pump();
    // 场景准备通过 scheduleMicrotask 异步调度，带 220ms 软超时与 300ms 采样超时，
    // 多推一帧把计时器跑掉，避免用例结束时留下 pending timer。
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('移除 blobs 后色网与暗纱均为静态层，稳态 0 transient 回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAmbient(tester, reduceMotion: false);

      final cover = find.byKey(const ValueKey('ambient-cover'));
      final veil = find.byKey(const ValueKey('ambient-veil'));
      expect(cover, findsOneWidget);
      expect(veil, findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-blobs')), findsNothing);
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
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reduce-motion 下艺术层与色网停帧，不产生任何 transient 回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAmbient(tester, reduceMotion: true, showArt: true);

      expect(find.byKey(const ValueKey('ambient-cover')), findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-art')), findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-veil')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('intensity 为 0 时整层不构建', (tester) async {
    await pumpAmbient(tester, reduceMotion: false, intensity: 0, showArt: true);

    expect(find.byKey(const ValueKey('ambient-cover')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-art')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-veil')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('4×3 矢量色网渲染与全出血艺术层独立隔离，landscape 解码宽 1280', (tester) async {
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
      artPreset: EditorialArtPreset.landscape,
      imageUrl: bundledDefaultWallpaperAssetPath,
    );

    final cover = find.byKey(const ValueKey('ambient-cover'));
    final art = find.byKey(const ValueKey('ambient-art'));
    final veil = find.byKey(const ValueKey('ambient-veil'));
    expect(cover, findsOneWidget);
    expect(art, findsOneWidget);
    expect(veil, findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-blobs')), findsNothing);

    // ambient-cover 内走 DesktopAmbientMeshSurface + AmbientColourMeshPainter，不再包含裸 Image。
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

    // ambient-art 渲染全出血无模糊无 ShaderMask 的 EditorialArtPanel，landscape 解码宽 1280。
    expect(
      find.descendant(of: art, matching: find.byType(EditorialArtPanel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: art, matching: find.byType(ImageFiltered)),
      findsNothing,
    );
    expect(
      find.descendant(of: art, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    final artImage = tester.widget<Image>(
      find.descendant(of: art, matching: find.byType(Image)),
    );
    final provider = artImage.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).imageProvider, isA<AssetImage>());
    expect(provider.width, 1280);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('isReaderRoute 为 true 时隐藏 ambient-art，仅渲染柔焦 4×3 色网与光池', (
    tester,
  ) async {
    final testGrid = AmbientMeshGrid(
      points: List<Color>.filled(12, const Color(0xFFD6C7AE)),
      average: const Color(0xFFD6C7AE),
    );
    DesktopAmbientMeshCache.instance.putForTest(
      bundledDefaultWallpaperAssetPath,
      testGrid,
    );

    await pumpAmbient(
      tester,
      reduceMotion: true,
      showArt: true,
      isReaderRoute: true,
      artPreset: EditorialArtPreset.portraitBook,
      imageUrl: bundledDefaultWallpaperAssetPath,
    );

    final cover = find.byKey(const ValueKey('ambient-cover'));
    expect(cover, findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-art')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-veil')), findsOneWidget);
    expect(
      find.descendant(of: cover, matching: find.byType(ImageFiltered)),
      findsOneWidget,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DesktopAmbientPlain 纯净背景静态渲染，零 transient 回调', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrapDesktop(const DesktopAmbientPlain()));
    await tester.pump();

    expect(find.byType(DesktopAmbientPlain), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-plain')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('双缓冲切换封面、预设与纸色兜底流畅无异常且不产生连点堆叠', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final gridA = AmbientMeshGrid(
        points: List<Color>.filled(12, const Color(0xFF284B63)),
        average: const Color(0xFF284B63),
      );
      final gridB = AmbientMeshGrid(
        points: List<Color>.filled(12, const Color(0xFF8C4A32)),
        average: const Color(0xFF8C4A32),
      );
      DesktopAmbientMeshCache.instance.putForTest(
        'https://example.test/a.jpg',
        gridA,
      );
      DesktopAmbientMeshCache.instance.putForTest(
        'https://example.test/b.jpg',
        gridB,
      );

      await pumpAmbient(
        tester,
        reduceMotion: false,
        showArt: true,
        artPreset: EditorialArtPreset.landscape,
        imageUrl: 'https://example.test/a.jpg',
      );

      // 连续快速切换封面与预设（验证双缓冲最多 2 层、连点不堆叠）。
      await tester.pumpWidget(
        wrapDesktop(
          const DesktopAmbient(
            imageUrl: 'https://example.test/b.jpg',
            intensity: 70,
            reduceMotion: false,
            showArt: true,
            artPreset: EditorialArtPreset.square,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 切换至无图纸色兜底（Reader 无封面场景）。
      await tester.pumpWidget(
        wrapDesktop(
          const DesktopAmbient(
            imageUrl: null,
            intensity: 70,
            reduceMotion: false,
            showArt: false,
            isReaderRoute: true,
            artPreset: EditorialArtPreset.portraitBook,
            fallbackTone: Color(0xFFD6C7AE),
          ),
        ),
      );

      // 推进完成异步预备与 720ms 交叉淡入淡出。
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 760));
      await tester.pump();

      expect(find.byKey(const ValueKey('ambient-cover')), findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-art')), findsNothing);
      expect(find.byKey(const ValueKey('ambient-blobs')), findsNothing);
      expect(find.byKey(const ValueKey('ambient-veil')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
