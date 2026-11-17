import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';

void main() {
  testWidgets('播放按钮保持固定尺寸并提供白色播放图标', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Center(
          child: MusicPlaybackButton(
            isPlaying: false,
            tooltip: '播放',
            onPressed: () => tapCount++,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(MusicPlaybackButton)),
      const Size(40, 40),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded));
    expect(icon.color, const Color(0xFFF7FCFC));

    await tester.tap(find.byType(MusicPlaybackButton));
    await tester.pump();
    expect(tapCount, 1);
  });

  testWidgets('紧凑播放按钮在小窗口中自动缩小', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 560);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Center(
          child: MusicPlaybackButton(
            isPlaying: false,
            tooltip: '播放',
            onPressed: () {},
            buttonSize: MusicPlaybackButtonSize.compact,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(MusicPlaybackButton)),
      const Size(34, 34),
    );
  });

  testWidgets('播放进度条使用统一的轨道和触点规格', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: MusicPlaybackProgressBar(
                value: 0.4,
                onChanged: null,
                semanticLabel: '播放进度',
              ),
            ),
          ),
        ),
      ),
    );

    final sliderTheme = tester.widget<SliderTheme>(find.byType(SliderTheme));
    expect(sliderTheme.data.trackHeight, 4);
    expect(sliderTheme.data.activeTrackColor, const Color(0xFF79D6D2));
    expect(sliderTheme.data.thumbShape, isA<RoundSliderThumbShape>());
  });
}
