import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_hero_flight_shuttle.dart';

PhotoItem _photo({String? coverUrl}) {
  return PhotoItem(
    id: 'photo-1',
    fileNodeId: 'file-1',
    title: 'photo.jpg',
    format: 'jpg',
    fileSize: 1,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026),
    coverUrl: coverUrl,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Center(child: SizedBox(width: 240, height: 240, child: child)),
  );
}

/// 断言须限定在 shuttle 子树内：MaterialApp 路由自身携带框架级
/// FadeTransition，全树查找会误伤。
Finder _insideShuttle(Finder matching) {
  return find.descendant(
    of: find.byType(PhotoHeroFlightShuttle),
    matching: matching,
  );
}

void main() {
  testWidgets('pop 方向直接飞行起始侧子树', (tester) async {
    final controller = AnimationController(vsync: tester);
    addTearDown(controller.dispose);
    controller.value = 1.0;

    await tester.pumpWidget(
      _host(
        PhotoHeroFlightShuttle(
          photo: _photo(coverUrl: 'https://example.test/cover.jpg'),
          animation: controller.view,
          flightDirection: HeroFlightDirection.pop,
          fromChild: const SizedBox(key: ValueKey('from-child')),
          coverDecodeWidth: 1024,
        ),
      ),
    );

    expect(
      _insideShuttle(find.byKey(const ValueKey('from-child'))),
      findsOneWidget,
    );
    // 退出方向不构造清晰层：缩略图/清晰图切换只发生在进入方向。
    expect(_insideShuttle(find.byType(FadeTransition)), findsNothing);
    expect(_insideShuttle(find.byType(CachedNetworkImage)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('push 方向底层为起始子树、上层以飞行进度交叉淡入封面档图', (tester) async {
    final controller = AnimationController(vsync: tester);
    addTearDown(controller.dispose);
    controller.value = 0.4;
    final photo = _photo(coverUrl: 'https://example.test/cover.jpg');

    await tester.pumpWidget(
      _host(
        PhotoHeroFlightShuttle(
          photo: photo,
          animation: controller.view,
          flightDirection: HeroFlightDirection.push,
          fromChild: const SizedBox(key: ValueKey('from-child')),
          coverDecodeWidth: 1024,
        ),
      ),
    );

    // 底层始终可见，清晰层透明占位（测试网络必失败）不遮盖底层。
    expect(
      _insideShuttle(find.byKey(const ValueKey('from-child'))),
      findsOneWidget,
    );
    final fade = tester.widget<FadeTransition>(
      _insideShuttle(find.byType(FadeTransition)),
    );
    expect(fade.opacity, same(controller.view));

    final image = tester.widget<CachedNetworkImage>(
      _insideShuttle(find.byType(CachedNetworkImage)),
    );
    expect(image.memCacheWidth, 1024);
    expect(image.fit, BoxFit.contain);
    // 清晰层不自带淡入：透明度完全由飞行进度驱动。
    expect(image.fadeInDuration, Duration.zero);
    expect(image.cacheKey, photo.coverCacheKey);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无封面时 push 仅飞行起始侧子树', (tester) async {
    final controller = AnimationController(vsync: tester);
    addTearDown(controller.dispose);
    controller.value = 0.0;

    await tester.pumpWidget(
      _host(
        PhotoHeroFlightShuttle(
          photo: _photo(),
          animation: controller.view,
          flightDirection: HeroFlightDirection.push,
          fromChild: const SizedBox(key: ValueKey('from-child')),
          coverDecodeWidth: 1024,
        ),
      ),
    );

    expect(
      _insideShuttle(find.byKey(const ValueKey('from-child'))),
      findsOneWidget,
    );
    expect(_insideShuttle(find.byType(FadeTransition)), findsNothing);
    expect(_insideShuttle(find.byType(CachedNetworkImage)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
