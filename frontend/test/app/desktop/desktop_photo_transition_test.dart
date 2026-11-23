import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_photo_transition.dart';
import 'package:omninest/features/photos/domain/photo.dart';

import 'desktop_test_harness.dart';

PhotoItem _photo(String id, {int width = 1600, int height = 1000}) {
  return PhotoItem(
    id: id,
    fileNodeId: 'node-$id',
    title: 'Photo $id',
    format: 'jpg',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026, 1, 1),
    width: width,
    height: height,
    coverUrl: 'https://example.invalid/photos/$id.jpg',
  );
}

Widget _wrapScoped(Widget child) {
  return ProviderScope(
    overrides: desktopSeedOverrides(),
    child: wrapDesktop(child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DesktopPhotoTransitionRegistry.instance.reset();
  });

  tearDown(() {
    DesktopPhotoTransitionRegistry.instance.reset();
  });

  testWidgets('有源卡片锚点时，进场从卡片矩形放大展开，完成后交还舞台图片', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
    );
    addTearDown(controller.dispose);

    final photo = _photo('p-1');
    var hiddenInStage = false;

    await tester.pumpWidget(
      _wrapScoped(
        Stack(
          children: [
            Positioned(
              left: 120,
              top: 180,
              width: 240,
              height: 150,
              child: DesktopPhotoAnchor(
                photo: photo,
                borderRadius: 10,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: DesktopPhotoViewerTransition(
                initialPhotoId: 'p-1',
                animation: controller,
                child: Builder(
                  builder: (context) {
                    hiddenInStage =
                        DesktopPhotoTransitionFlightScope.shouldHideStageImage(
                          context,
                        );
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );

    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final flightFinder = find.byKey(
      const ValueKey<String>('desktop-photo-flight-card'),
    );
    expect(flightFinder, findsOneWidget);
    expect(hiddenInStage, isTrue);

    final startRect = tester.getRect(flightFinder);
    expect(startRect.left, closeTo(120, 40));
    expect(startRect.width, greaterThanOrEqualTo(240));

    await tester.pump(const Duration(milliseconds: 140));
    final midRect = tester.getRect(flightFinder);
    expect(midRect.width, greaterThan(startRect.width));
    expect(midRect.height, greaterThan(startRect.height));

    await tester.pumpAndSettle();
    expect(flightFinder, findsNothing);
    expect(hiddenInStage, isFalse);
  });

  testWidgets('查看器翻页后退出时，按当前照片缩回对应卡片位置', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    addTearDown(controller.dispose);

    final owner = Object();
    final photo1 = _photo('p-1');
    final photo2 = _photo('p-2');

    await tester.pumpWidget(
      _wrapScoped(
        Stack(
          children: [
            Positioned(
              left: 80,
              top: 160,
              width: 220,
              height: 140,
              child: DesktopPhotoAnchor(
                photo: photo1,
                borderRadius: 10,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 980,
              top: 420,
              width: 220,
              height: 140,
              child: DesktopPhotoAnchor(
                photo: photo2,
                borderRadius: 10,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: DesktopPhotoViewerTransition(
                initialPhotoId: 'p-1',
                animation: controller,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    // 模拟在查看器内翻到 p-2 后关闭。
    DesktopPhotoTransitionRegistry.instance.updateViewerStage(
      owner,
      DesktopPhotoViewerStageSnapshot(
        photoId: 'p-2',
        coverUrl: photo2.coverUrl,
        aspectRatio: 1.6,
        infoOpen: false,
        canFlyBack: true,
      ),
    );

    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final flightFinder = find.byKey(
      const ValueKey<String>('desktop-photo-flight-card'),
    );
    expect(flightFinder, findsOneWidget);
    final nearEndRect = tester.getRect(flightFinder);
    // 应朝右侧 p-2（left=980）收束，而非左侧 p-1（left=80）。
    expect(nearEndRect.center.dx, greaterThan(800));
    expect(nearEndRect.width, lessThan(400));

    await tester.pumpAndSettle();
    DesktopPhotoTransitionRegistry.instance.clearViewerStage(owner);
  });

  testWidgets('无锚点或查看器处于放大状态时回退为居中缩放淡入淡出', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
    );
    addTearDown(controller.dispose);

    var hiddenInStage = true;
    await tester.pumpWidget(
      _wrapScoped(
        DesktopPhotoViewerTransition(
          initialPhotoId: 'missing-photo',
          animation: controller,
          child: Builder(
            builder: (context) {
              hiddenInStage =
                  DesktopPhotoTransitionFlightScope.shouldHideStageImage(
                    context,
                  );
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey<String>('desktop-photo-flight-card')),
      findsNothing,
    );
    expect(hiddenInStage, isFalse);
    expect(find.byType(Transform), findsWidgets);

    await tester.pumpAndSettle();
  });
}
