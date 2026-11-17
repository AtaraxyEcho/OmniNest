import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_places_globe.dart';

/// Places 地图 `.pin b` 的 `ping 2.4s ease-out infinite`（`desktop.css:351`）。
///
/// 这里锁的不是像素，而是两条性能契约：脉冲环只在选中地点时存在，并且
/// 与地球 Canvas 各占一个保留层——否则 2.4s 的循环会把整颗点阵地球
/// 每帧重录/重光栅；减动效时连 ticker 都不能注册。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const places = <DesktopGlobePlace>[
    DesktopGlobePlace(
      name: 'Reykjavik',
      count: 12,
      latitude: 64.1,
      longitude: -21.9,
    ),
    DesktopGlobePlace(
      name: 'Kyoto',
      count: 8,
      latitude: 35.0,
      longitude: 135.8,
    ),
  ];

  Future<void> pumpGlobe(
    WidgetTester tester, {
    String? selected,
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          // MediaQuery 必须放在 MaterialApp 内层：WidgetsApp 会用
          // MediaQuery.fromView 覆盖外层显式构造的 data。
          body: MediaQuery(
            data: MediaQueryData(
              size: const Size(600, 600),
              devicePixelRatio: 1,
              disableAnimations: reduceMotion,
            ),
            child: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: DesktopPlacesGlobe(
                  places: places,
                  selected: selected,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('未选中地点时没有脉冲层，地球 Canvas 仍单独保留', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpGlobe(tester);
      expect(find.byKey(const ValueKey('places-globe-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('places-globe-ping')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(DesktopPlacesGlobe),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('选中地点时脉冲环独立成层，地球不跟着每帧重建', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpGlobe(tester, selected: 'Kyoto');
      expect(find.byKey(const ValueKey('places-globe-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('places-globe-ping')), findsOneWidget);
      // 脉冲环的 AnimatedBuilder 必须在自己的 RepaintBoundary 之内。
      expect(
        find.ancestor(
          of: find.descendant(
            of: find.byType(DesktopPlacesGlobe),
            matching: find.byType(AnimatedBuilder),
          ),
          matching: find.byKey(const ValueKey('places-globe-ping')),
        ),
        findsOneWidget,
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('减动效时脉冲环不注册 ticker', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpGlobe(tester, selected: 'Kyoto', reduceMotion: true);
      expect(find.byKey(const ValueKey('places-globe-ping')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
