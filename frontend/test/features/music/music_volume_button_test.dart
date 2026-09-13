import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/widgets/music_volume_button.dart';

void main() {
  testWidgets('悬停音量按钮后面板持续展开，不会反复收缩', (tester) async {
    final gesture = await _pumpHarness(tester);
    final buttonCenter = tester.getCenter(find.byType(MusicVolumeButton));

    await gesture.moveTo(buttonCenter);
    await tester.pumpAndSettle();
    expect(_panelFooterText(), findsOneWidget);

    // 面板展开后指针在按钮上微动：旧实现的全屏遮罩会让按钮 MouseRegion
    // 收到假 exit 而进入隐藏循环，真机鼠标抖动时表现为反复收缩。
    // 循环中的面板有短暂隐藏窗口，多次采样以捕获。
    await gesture.moveTo(buttonCenter + const Offset(2, 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(_panelFooterText(), findsOneWidget);
    }
  });

  testWidgets('面板位于按钮正上方且水平居中，点击面板外部关闭', (tester) async {
    final gesture = await _pumpHarness(tester);

    await gesture.moveTo(tester.getCenter(find.byType(MusicVolumeButton)));
    await tester.pumpAndSettle();

    final buttonRect = tester.getRect(find.byType(MusicVolumeButton));
    final footerRect = tester.getRect(_panelFooterText());
    expect(footerRect.bottom, lessThanOrEqualTo(buttonRect.top));
    expect((footerRect.center.dx - buttonRect.center.dx).abs(), lessThan(1.0));

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_panelFooterText(), findsNothing);
  });

  testWidgets('悬停面板内静音按钮触发 Tooltip 不抛渲染异常', (tester) async {
    final gesture = await _pumpHarness(tester);

    await gesture.moveTo(tester.getCenter(find.byType(MusicVolumeButton)));
    await tester.pumpAndSettle();
    expect(_panelFooterText(), findsOneWidget);

    final muteIcon = find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          widget.icon == Icons.volume_up_rounded &&
          widget.size == 14,
    );
    await gesture.moveTo(tester.getCenter(muteIcon));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 200));

    // 旧实现的面板经 CompositedTransformFollower 定位，Tooltip 在布局期
    // 计算 paint transform 触发 RenderFollowerLayer 断言。
    expect(tester.takeException(), isNull);
    expect(find.text('音量'), findsOneWidget);
  });
}

Finder _panelFooterText() => find.text('100');

Future<TestGesture> _pumpHarness(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 1),
        ),
      ),
      home: Scaffold(
        body: Center(
          child: MusicVolumeButton(
            player: _FakeMusicAudioPlayback(),
            tooltip: '音量',
            style: MusicVolumeButtonStyle.flat,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

class _FakeMusicAudioPlayback implements MusicAudioPlayback {
  @override
  MusicAudioPlayerState get state =>
      const MusicAudioPlayerState(playing: true, volume: 100);

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: const Stream<Duration>.empty(),
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
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  void setVolume(double volume) {}

  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  Future<void> dispose() async {}
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();
}
