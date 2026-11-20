import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart'
    show bundledDefaultWallpaperAssetPath;

import 'desktop_test_harness.dart';

/// 环境光拆层的重绘闸门。
///
/// 锁定的是「谁在哪一层」而不是像素：漂移色场必须是「静态纹理保留层 +
/// 其上 Transform」，封面与暗纱/噪点必须是静态层，子树里不能有任何动画
/// 驱动——它们一旦跟着每帧重建，整层环境光（含 group opacity 的全屏
/// saveLayer）就会每帧重录/重光栅，这是桌面卡顿的最大头。
///
/// 为什么不断言 `debugNeedsPaint`：`pump()` 跑完整帧后所有边界都已重绘
/// 完毕，dirty 位归零；而只跑 `handleBeginFrame` 又停在 transient 阶段，
/// AnimatedBuilder 的 rebuild 还没发生，色场也不会脏。这条语义只能靠
/// 结构断言与 transient 回调计数表达。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAmbient(
    WidgetTester tester, {
    required bool reduceMotion,
    double intensity = 70,
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapDesktop(
        DesktopAmbient(
          imageUrl: 'https://example.test/cover.jpg',
          intensity: intensity,
          reduceMotion: reduceMotion,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('封面与暗纱是静态层，色场单独一层且由 ticker 驱动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAmbient(tester, reduceMotion: false);

      final cover = find.byKey(const ValueKey('ambient-cover'));
      final blobs = find.byKey(const ValueKey('ambient-blobs'));
      final veil = find.byKey(const ValueKey('ambient-veil'));
      expect(cover, findsOneWidget);
      expect(blobs, findsOneWidget);
      expect(veil, findsOneWidget);

      // 静态层里不能有任何 AnimatedBuilder：只要有一个，漂移色场就会
      // 顺带把 48σ 封面与 4200 个噪点一起拖进每帧重绘。
      expect(
        find.descendant(of: cover, matching: find.byType(AnimatedBuilder)),
        findsNothing,
      );
      expect(
        find.descendant(of: veil, matching: find.byType(AnimatedBuilder)),
        findsNothing,
      );
      // 色场层正是那组每帧更新变换的层：无论内部是「三团各一个」还是
      // 「一个 merge 三个控制器」，都必须挂着 AnimatedBuilder 且驱动
      // Transform——边界内的静态纹理不重录。
      expect(
        find.descendant(of: blobs, matching: find.byType(AnimatedBuilder)),
        findsWidgets,
      );
      // 三团漂移在跑：transient 回调非空。
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reduce-motion 下三团停帧，不产生任何 transient 回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAmbient(tester, reduceMotion: true);

      expect(find.byKey(const ValueKey('ambient-cover')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('intensity 为 0 时整层不构建', (tester) async {
    await pumpAmbient(tester, reduceMotion: false, intensity: 0);

    expect(find.byKey(const ValueKey('ambient-cover')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-blobs')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('随包默认场景按 asset 加载，不当成网络地址', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapDesktop(
        DesktopAmbient(
          imageUrl: bundledDefaultWallpaperAssetPath,
          intensity: 70,
          reduceMotion: true,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('ambient-cover')),
        matching: find.byType(Image),
      ),
    );
    final provider = image.image;
    expect(
      provider,
      isA<ResizeImage>(),
      reason: '样例 `Mush` 把封面画进 64×40，环境光不该按原图解码',
    );
    expect(
      (provider as ResizeImage).imageProvider,
      isA<AssetImage>(),
      reason: '默认场景是随包资产，走网络加载会静默失败只剩色场',
    );
    expect(provider.width, 64);
  });
}
