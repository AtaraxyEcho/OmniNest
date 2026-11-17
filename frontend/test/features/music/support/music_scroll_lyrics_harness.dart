import 'dart:async';
import 'dart:ui' as ui show Image, ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

/// 滚动歌词组件测试共用的驱动与探针。

/// 推进若干帧：post-frame 中启动的跟随动画首帧不产生位移，
/// 需要额外帧完成（真实运行时按 60fps 连续推进）。
Future<void> advanceFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

/// 采样 [boundaryKey] 重绘边界的渲染像素，返回 (图像, G-R 取值函数)。
///
/// 渐变读色的 G 分量明显高于 R，非当前句色 G≈R，据此判断某点是否已被填充。
Future<(ui.Image, int Function(Offset))> pixelProbe(
  WidgetTester tester,
  Key boundaryKey,
) async {
  final renderObject = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  late final ui.Image image;
  await tester.binding.runAsync(() async {
    image = await renderObject.toImage(pixelRatio: 1);
  });
  late final ByteData bytes;
  await tester.binding.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    bytes = data!;
  });
  int delta(Offset point) {
    final x = point.dx.round().clamp(0, image.width - 1);
    final y = point.dy.round().clamp(0, image.height - 1);
    final offset = (y * image.width + x) * 4;
    return bytes.getUint8(offset + 1) - bytes.getUint8(offset);
  }

  return (image, delta);
}

Widget musicScrollLyricsApp({
  required MusicScrollLyricsFakeAudioPlayback player,
  PortalLyricVisualSettings? settings,
  bool scrollMode = true,
  TextAlign textAlign = TextAlign.left,
  Alignment blockAnchor = Alignment.center,
  double height = 400,
  List<MusicLyricLine>? lyrics,
  bool wordTimeline = false,
  int? trackOffsetMs,
  void Function(int deltaMs)? onAdjustLyricOffset,
  MusicLyricSpec? spec,
  String? fontFamily,
  Key? repaintBoundaryKey,
}) {
  final lines =
      lyrics ??
      List<MusicLyricLine>.generate(
        30,
        (index) => MusicLyricLine(
          position: Duration(seconds: index),
          text: 'Lyric $index',
        ),
      );
  final resolvedLines =
      wordTimeline
          ? List<MusicLyricLine>.generate(30, (index) {
            final base = lines[index];
            return MusicLyricLine(
              position: base.position,
              text: base.text,
              translation: base.translation,
              // 词级仅覆盖行首 0.4s：行远长于词级覆盖，验证按词时长推进。
              words: <MusicLyricWord>[
                MusicLyricWord(
                  offset: Duration.zero,
                  duration: const Duration(milliseconds: 400),
                  text: base.text,
                ),
              ],
            );
          })
          : lines;
  // 测试字体度量决定折行位置：传入 fontFamily 时用固定度量的 Ahem
  // 字体（每字形宽 = 字号），让折行断言可以精确预判。
  final body = RepaintBoundary(
    key: repaintBoundaryKey,
    child: SizedBox(
      height: height,
      child: MusicImmersiveLyrics(
        palette: MusicImmersivePalette.digital,
        player: player,
        onSeek: (position) => player.seek(position),
        track: musicScrollLyricsTestTrack,
        lyrics: resolvedLines,
        scale: 1,
        lyricSettings: settings,
        lyricSpec: spec,
        trackOffsetMs: trackOffsetMs,
        onAdjustLyricOffset: onAdjustLyricOffset,
        // 滚动歌词形态、文本排列与块锚点由宿主传入（设备级偏好 + 端形态 + 歌词位置）。
        scrollMode: scrollMode,
        textAlign: textAlign,
        blockAnchor: blockAnchor,
        onTogglePlayback: () {},
        onPrevious: () {},
        onNext: () {},
      ),
    ),
  );
  return MaterialApp(
    theme: ThemeData.dark(),
    // 歌词区包含本地化文案（"回到当前播放"），测试宿主需要提供委派，
    // 与真实宿主一致。
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body:
          fontFamily == null
              ? body
              : DefaultTextStyle(
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 16,
                  color: Colors.white,
                ),
                child: body,
              ),
    ),
  );
}

const MusicTrack musicScrollLyricsTestTrack = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Track',
  artistName: 'Artist',
  albumTitle: 'Album',
  format: 'FLAC',
  favorite: false,
);

class MusicScrollLyricsFakeAudioPlayback implements MusicAudioPlayback {
  MusicScrollLyricsFakeAudioPlayback({required Duration initialPosition})
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
      const MusicScrollLyricsSilentSpectrum();

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MusicScrollLyricsSilentSpectrum
    implements ValueListenable<MusicSpectrumFrame> {
  const MusicScrollLyricsSilentSpectrum();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
