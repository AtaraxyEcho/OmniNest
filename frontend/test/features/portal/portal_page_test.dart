import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/portal/presentation/pages/portal_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PortalPage', () {
    testWidgets('renders without crashing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // 设置宽屏尺寸以使用桌面布局
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // 覆盖 session 存储以避免 FlutterSecureStorage 插件依赖
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            musicAudioPlaybackProvider.overrideWith(
              (ref) => const _FakeMusicAudioPlayback(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.from(AppThemePalette.dark),
            home: const PortalPage(),
          ),
        ),
      );

      // 等待异步 provider 处理
      await tester.pump(const Duration(seconds: 1));

      // 验证页面已渲染
      expect(find.byType(PortalPage), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PortalPage)),
      );
      final scene = container.read(appBackdropSceneControllerProvider);
      expect(scene.owner, 'portal');
      expect(scene.policy.scene, AppBackdropScene.portal);
      expect(scene.policy.visible, isTrue);
    });

    testWidgets('renders compact desktop height without overflow', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      // 设置宽屏低高度尺寸，覆盖桌面端初始窗口底部栏场景
      tester.view.physicalSize = const Size(2560, 1180);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // 覆盖 session 存储以避免 FlutterSecureStorage 插件依赖
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            musicAudioPlaybackProvider.overrideWith(
              (ref) => const _FakeMusicAudioPlayback(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.from(AppThemePalette.dark),
            home: const PortalPage(),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(PortalPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeMusicAudioPlayback implements MusicAudioPlayback {
  const _FakeMusicAudioPlayback();

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
