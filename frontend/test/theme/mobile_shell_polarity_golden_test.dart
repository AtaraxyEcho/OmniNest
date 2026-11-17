// 壳层极性的真实渲染基线：无壁纸的实底壳在暗/浅两种根主题下的整屏观感。
// 这批图是"壳层注册极性"这一刀唯一的像素证据，缺了它就只能靠测试断言颜色值。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';

import '../support/golden_fonts.dart';

class _ZeroUnreadCount extends UnreadCountNotifier {
  @override
  int build() => 0;
}

class _SilentMusicAudioPlayback implements MusicAudioPlayback {
  const _SilentMusicAudioPlayback();

  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState();

  @override
  MusicAudioPlayerStreams get stream => const MusicAudioPlayerStreams(
    position: Stream<Duration>.empty(),
    duration: Stream<Duration>.empty(),
    volume: Stream<double>.empty(),
    completed: Stream<bool>.empty(),
    log: Stream<MusicAudioLog>.empty(),
  );

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  void setVolume(double volume) {}

  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> dispose() async {}
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadGoldenFonts);

  Future<void> pumpShell(WidgetTester tester, Brightness brightness) async {
    final branchKeys = <String, Key>{
      '/portal': UniqueKey(),
      '/library': UniqueKey(),
      '/reader': UniqueKey(),
      '/files': UniqueKey(),
    };
    final router = GoRouter(
      initialLocation: '/portal',
      routes: [
        StatefulShellRoute.indexedStack(
          builder:
              (context, state, navigationShell) =>
                  MobileAppShell(navigationShell: navigationShell),
          branches: [
            for (final entry in branchKeys.entries)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: entry.key,
                    builder: (context, state) => const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(360, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          presetAppEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost:8080/api/v1',
              wsBaseUrl: 'ws://localhost:8080/ws',
            ),
          ),
          mobileShellLocalBackdropActiveProvider.overrideWithValue(false),
          // 壳层离线横幅会拉起 connectivity 平台流，测试宿主没有实现该通道，
          // 未桩住时流订阅的 MissingPluginException 会记到当前用例头上。
          appOnlineStatusProvider.overrideWith((ref) => Stream.value(true)),
          unreadCountProvider.overrideWith(_ZeroUnreadCount.new),
          mobileShellSelectionActiveProvider.overrideWith(
            (ref, branch) => false,
          ),
          musicAudioPlaybackProvider.overrideWith(
            (ref) => const _SilentMusicAudioPlayback(),
          ),
        ],
        child: RepaintBoundary(
          key: const ValueKey('shell-golden'),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme:
                brightness == Brightness.light
                    ? OmniNestTheme.light()
                    : OmniNestTheme.dark(),
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (name, brightness) in <(String, Brightness)>[
    ('dark_system', Brightness.dark),
    ('light_system', Brightness.light),
  ]) {
    testWidgets('移动壳层极性基线 $name', (tester) async {
      await pumpShell(tester, brightness);
      await expectLater(
        find.byKey(const ValueKey('shell-golden')),
        matchesGoldenFile('goldens/mobile_shell_$name.png'),
      );
    });
  }
}
