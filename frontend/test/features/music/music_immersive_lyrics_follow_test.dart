import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

void main() {
  testWidgets('三行歌词始终围绕当前句居中显示', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 20),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));

    expect(find.text('Lyric 19'), findsOneWidget);
    expect(find.text('Lyric 20'), findsOneWidget);
    expect(find.text('Lyric 21'), findsOneWidget);
    expect(find.text('Lyric 18'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 20',
    );

    player.emit(const Duration(seconds: 21));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Lyric 20'), findsOneWidget);
    expect(find.text('Lyric 21'), findsOneWidget);
    expect(find.text('Lyric 22'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 21',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('单行歌词仅显示当前句并按固定周期呼吸扩散', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 12),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.mineradioClassic.copyWith(
          visibleLines: 1,
        ),
      ),
    );

    expect(find.text('Lyric 12'), findsOneWidget);
    expect(find.text('Lyric 11'), findsNothing);
    expect(find.text('Lyric 13'), findsNothing);
    final quietStyle =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!;
    final quietScale =
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('music-lyric-reactive-transform')),
            )
            .transform
            .getMaxScaleOnAxis();
    expect(find.byType(InkWell), findsNothing);
    expect(
      find.byKey(const ValueKey('music-lyric-text-gradient')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 700));

    final brightStyle =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!;
    final brightScale =
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('music-lyric-reactive-transform')),
            )
            .transform
            .getMaxScaleOnAxis();
    final motion =
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('music-lyric-reactive-motion')),
            )
            .transform
            .getTranslation();
    // 呼吸只做缩放与上移（默认在读色为白色，颜色呼吸不可见）。
    expect(brightStyle.color, quietStyle.color);
    expect(brightScale, greaterThan(quietScale + 0.025));
    expect(brightScale, lessThan(quietScale + 0.05));
    expect(motion.y, lessThan(-1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('整页模式按可用高度决定可见行数且不产生布局溢出', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 20),
    );
    addTearDown(player.dispose);

    // 极矮窗口：行高由内容决定，只容得下一行时自动降级为单行。
    await tester.pumpWidget(_lyricsApp(player: player, height: 60));
    expect(find.text('Lyric 20'), findsOneWidget);
    expect(find.text('Lyric 19'), findsNothing);
    expect(find.text('Lyric 21'), findsNothing);
    expect(tester.takeException(), isNull);

    // 常规矮窗口：容得下多行时按可用高度显示，不再强制单行。
    // 重建后需等 AnimatedSwitcher 退场结束，否则同一行会有新旧两份。
    await tester.pumpWidget(_lyricsApp(player: player, height: 220));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Lyric 20'), findsOneWidget);
    expect(find.text('Lyric 19'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭呼吸后当前歌词保持固定缩放并使用自定义颜色', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 12),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          visibleLines: 1,
          breathingEnabled: false,
          currentPaint: const LyricPaint.solid(0xFF73E6C4),
        ),
      ),
    );

    final transformFinder = find.byKey(
      const ValueKey('music-lyric-reactive-transform'),
    );
    final initialScale =
        tester.widget<Transform>(transformFinder).transform.getMaxScaleOnAxis();
    await tester.pump(const Duration(milliseconds: 900));
    final laterScale =
        tester.widget<Transform>(transformFinder).transform.getMaxScaleOnAxis();
    final style =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!;

    expect(laterScale, initialScale);
    expect(style.color, const Color(0xFF73E6C4));
    // 溢光已整体移除：歌词不再使用 Shadow。
    expect(style.shadows, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在读行与非当前句使用各自调色盘颜色', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 20),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          breathingEnabled: false,
          currentPaint: const LyricPaint.solid(0xFF4A7890),
          inactivePaint: const LyricPaint.solid(0xFFFFF2D0),
        ),
      ),
    );

    final currentStyle =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!;
    final pastStyle = tester.widget<Text>(find.text('Lyric 19')).style!;
    final upcomingStyle = tester.widget<Text>(find.text('Lyric 21')).style!;
    final expectedInactive = const Color(
      0xFFFFF2D0,
    ).withValues(alpha: PortalLyricVisualSettings.defaults.inactiveOpacity);
    // 当前行满亮用在读色；已唱行与未唱行共用非当前句色并压暗。
    expect(currentStyle.color, const Color(0xFF4A7890));
    expect(pastStyle.color, expectedInactive);
    expect(upcomingStyle.color, expectedInactive);
    expect(tester.takeException(), isNull);
  });
}

Widget _lyricsApp({
  required _FakeMusicAudioPlayback player,
  PortalLyricVisualSettings? settings,
  double height = 400,
}) {
  final lyrics = List<MusicLyricLine>.generate(
    30,
    (index) => MusicLyricLine(
      position: Duration(seconds: index),
      text: 'Lyric $index',
    ),
  );
  return MaterialApp(
    theme: ThemeData.dark(),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: MusicImmersiveLyrics(
          palette: MusicImmersivePalette.digital,
          player: player,
          track: _track,
          lyrics: lyrics,
          scale: 1,
          lyricSettings: settings ?? PortalLyricVisualSettings.defaults,
          // 多行歌词形态：滚动形态与文本排列改为组件参数（设备级偏好 + 端形态）。
          scrollMode: false,
          textAlign: TextAlign.left,
          blockAnchor: Alignment.center,
          onTogglePlayback: () {},
          onPrevious: () {},
          onNext: () {},
        ),
      ),
    ),
  );
}

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Track',
  artistName: 'Artist',
  albumTitle: 'Album',
  format: 'FLAC',
  favorite: false,
);

class _FakeMusicAudioPlayback implements MusicAudioPlayback {
  _FakeMusicAudioPlayback({required Duration initialPosition})
    : _state = MusicAudioPlayerState(
        playing: true,
        position: initialPosition,
        duration: const Duration(minutes: 3),
      );

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  MusicAudioPlayerState _state;

  @override
  MusicAudioPlayerState get state => _state;

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    completed: const Stream<bool>.empty(),
    log: const Stream<MusicAudioLog>.empty(),
  );

  void emit(Duration position) {
    _state = _state.copyWith(position: position);
    _positionController.add(position);
  }

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> pause() async {
    _state = _state.copyWith(playing: false);
  }

  @override
  Future<void> play() async {
    _state = _state.copyWith(playing: true);
  }

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> seek(Duration position) async {
    emit(position);
  }

  @override
  void setVolume(double volume) {
    _state = _state.copyWith(volume: volume);
  }

  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
  }
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// 供探针测试复用的构建入口。
class LyricsAppProbe {
  const LyricsAppProbe(this.widget);
  final Widget widget;
}

LyricsAppProbe buildLyricsAppProbe() {
  return LyricsAppProbe(
    _lyricsApp(
      player: _FakeMusicAudioPlayback(
        initialPosition: const Duration(seconds: 10),
      ),
    ),
  );
}
