import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

void main() {
  testWidgets('全套描边图标按请求尺寸渲染且不抛异常', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const icons = <OmniIconsData>[
      OmniIcons.home,
      OmniIcons.library,
      OmniIcons.book,
      OmniIcons.folder,
      OmniIcons.search,
      OmniIcons.bell,
      OmniIcons.clock,
      OmniIcons.sun,
      OmniIcons.moon,
      OmniIcons.cloud,
      OmniIcons.rain,
      OmniIcons.snow,
      OmniIcons.storm,
      OmniIcons.haze,
      OmniIcons.play,
      OmniIcons.pause,
      OmniIcons.next,
      OmniIcons.previous,
      OmniIcons.chevron,
      OmniIcons.more,
      OmniIcons.heart,
      OmniIcons.grid,
      OmniIcons.list,
      OmniIcons.plus,
      OmniIcons.device,
      OmniIcons.settings,
      OmniIcons.image,
      OmniIcons.film,
      OmniIcons.music,
      OmniIcons.arrow,
      OmniIcons.share,
      OmniIcons.download,
      OmniIcons.close,
      OmniIcons.queue,
      OmniIcons.shuffle,
      OmniIcons.repeat,
      OmniIcons.sparkle,
      OmniIcons.check,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Column(
          children: [
            for (final icon in icons)
              OmniIcon(key: ValueKey(icon.hashCode), icon: icon, size: 22),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final icon in icons) {
      final size = tester.getSize(find.byKey(ValueKey(icon.hashCode)));
      expect(size, const Size(22, 22));
    }
  });

  testWidgets('非默认尺寸同步缩放描边', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: OmniIcon(icon: OmniIcons.search, size: 44)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OmniIcon)), const Size(44, 44));
  });

  test('天气编码映射到描边天气图标族', () {
    expect(OmniIcons.weatherFor(100), OmniIcons.sun);
    expect(OmniIcons.weatherFor(150), OmniIcons.moon);
    expect(OmniIcons.weatherFor(305), OmniIcons.rain);
    expect(OmniIcons.weatherFor(405), OmniIcons.snow);
    expect(OmniIcons.weatherFor(999), OmniIcons.cloud);
  });
}
