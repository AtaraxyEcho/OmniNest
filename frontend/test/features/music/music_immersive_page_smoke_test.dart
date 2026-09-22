import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';

/// 不依赖原生音频引擎的播放器替身，供页面冒烟测试使用。
class _SilentMusicAudioPlayback implements MusicAudioPlayback {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);

  final MusicAudioPlayerState _state = MusicAudioPlayerState(
    playing: false,
    position: const Duration(minutes: 1),
    duration: const Duration(minutes: 3),
  );

  @override
  MusicAudioPlayerState get state => _state;

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  MusicAudioPlayerStreams get stream => MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    completed: const Stream<bool>.empty(),
    log: const Stream<MusicAudioLog>.empty(),
  );

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> seek(Duration position) async {}

  @override
  void setVolume(double volume) {}

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

void main() {
  testWidgets('进入沉浸播放页并悬停不触发 MouseTracker/布局重入', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost',
              wsBaseUrl: 'ws://localhost',
            ),
          ),
          musicAudioPlaybackProvider.overrideWith(
            (ref) => _SilentMusicAudioPlayback(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MusicImmersivePlayer()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 样例居中/居右布局的 Dock 传输行含 ±10 秒快进快退。
    expect(find.byTooltip('后退 10 秒'), findsOneWidget);
    expect(find.byTooltip('前进 10 秒'), findsOneWidget);
    // 无本地播放项时不出现收藏入口（收藏命令只覆盖本地曲库）。
    expect(find.byTooltip('收藏'), findsNothing);
    expect(find.byTooltip('取消收藏'), findsNothing);

    // 用真实鼠标事件扫过卡组、歌词、底栏与空白处，覆盖 enter/exit 交错。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    const path = <Offset>[
      Offset(640, 512),
      Offset(300, 300),
      Offset(900, 300),
      Offset(640, 950),
      Offset(20, 20),
      Offset(640, 512),
    ];
    for (final position in path) {
      final hit = HitTestResult();
      tester.binding.hitTestInView(hit, position, tester.view.viewId);
      tester.binding.dispatchEvent(pointer.hover(position), hit);
      await tester.pump();
    }
    // 均衡器动画会持续产生帧，多推几帧确认收敛。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('小数缩放下沉浸页固定高度块不产生 RenderFlex 溢出', (tester) async {
    // DPR 2 + 逻辑 1267×1007 → 缩放系数 ≈0.983：行盒物理像素取整与固定
    // 尺寸控件（如 40px 播放键放进 40*scale 行）在此最容易触发溢出断言。
    tester.view.physicalSize = const Size(2534, 2014);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost',
              wsBaseUrl: 'ws://localhost',
            ),
          ),
          musicAudioPlaybackProvider.overrideWith(
            (ref) => _SilentMusicAudioPlayback(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MusicImmersivePlayer()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
  });
}
