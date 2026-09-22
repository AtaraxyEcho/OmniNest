import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 居右布局歌词列头部 ±0.2s 按钮：调整曲目级歌词延迟并在头部显示当前值。

void main() {
  testWidgets('歌词列头部 ±0.2s 按钮写入曲目级延迟并展示当前值', (tester) async {
    // 视觉偏好种子：居右布局，使歌词列头部（含 ±0.2s 按钮）参与构建。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'music_player_visual_v1': jsonEncode(<String, dynamic>{
        'schemaVersion': 14,
        'visual': <String, dynamic>{
          'lyrics': <String, dynamic>{
            'enabled': true,
            'layout': 'right',
            'translationEnabled': false,
          },
        },
      }),
    });
    final player = _SilentMusicAudioPlayback();
    addTearDown(player.dispose);
    final api = _FakeUserPreferencesApi();
    final container = ProviderContainer.test(
      overrides: [
        userPreferencesApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        musicCenterControllerProvider.overrideWith(
          () => _FakeMusicCenterController(_centerState()),
        ),
        musicPlaybackSessionProvider.overrideWith(
          () => _FakeMusicPlaybackSessionController(player),
        ),
      ],
    );
    addTearDown(container.dispose);

    // 桌面基准视口：保证两侧双列构图（居右布局）生效。
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    await tester.pump();

    // 头部初始无偏移读数；点击 +0.2s 后写入曲目级延迟并显示读数。
    expect(find.text('延后 0.2 秒'), findsNothing);
    await tester.tap(find.text('+0.2s'));
    await tester.pump();
    await tester.pump();
    expect(
      container.read(musicTrackLyricOffsetProvider('netease:1')).asData?.value,
      200,
    );
    expect(find.text('延后 0.2 秒'), findsOneWidget);

    // 再点一次累加；重置按钮清零后读数消失。
    await tester.tap(find.text('+0.2s'));
    await tester.pump();
    await tester.pump();
    expect(find.text('延后 0.4 秒'), findsOneWidget);
    await tester.tap(find.byTooltip('重置歌词偏移'));
    await tester.pump();
    await tester.pump();
    expect(
      container.read(musicTrackLyricOffsetProvider('netease:1')).asData?.value,
      0,
    );
    expect(find.text('延后 0.4 秒'), findsNothing);
  });
}

MusicCenterState _centerState() {
  final track = const MusicTrack(
    id: 'netease:1',
    fileNodeId: '',
    title: 'Header Track',
    artistName: 'Artist',
    albumTitle: 'Album',
    format: 'FLAC',
    favorite: false,
    lyricsRaw: '[00:00.00]First line\n[00:10.00]Second line',
  );
  final item = MusicPlayableItem(
    ref: const OnlineMusicRef(platform: MusicPlatform.netease, songId: '1'),
    track: track,
  );
  return MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: [track],
    albums: const [],
    artists: const [],
    playlists: const [],
    currentItem: item,
    isPlaying: true,
    playbackItems: [item],
    playbackIndex: 0,
    neteaseUserInfo: const PlatformUserInfo(
      platform: 'netease',
      userId: '42',
      nickname: 'tester',
      avatarUrl: '',
      vip: false,
    ),
  );
}

class _FakeMusicCenterController extends MusicCenterController {
  _FakeMusicCenterController(this.initialState);

  final MusicCenterState initialState;

  @override
  Future<MusicCenterState> build() async => initialState;
}

class _AuthenticatedSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(id: 'user-1', username: 'tester', role: 'MEMBER'),
    );
  }
}

class _FakeUserPreferencesApi extends UserPreferencesApi {
  _FakeUserPreferencesApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  final Map<String, Map<String, dynamic>> values =
      <String, Map<String, dynamic>>{};

  @override
  Future<PreferenceSnapshot> getSnapshot(String scope) async {
    return PreferenceSnapshot(
      scope: scope,
      preferences: values[scope] ?? const <String, dynamic>{},
      version: values.containsKey(scope) ? 1 : null,
    );
  }

  @override
  Future<PreferenceSnapshot> patch({
    required String scope,
    required int? baseVersion,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const <String>{},
  }) async {
    final preferences = Map<String, dynamic>.from(
      values[scope] ?? const <String, dynamic>{},
    )..addAll(changes);
    values[scope] = preferences;
    return PreferenceSnapshot(
      scope: scope,
      preferences: preferences,
      version: 1,
    );
  }

  @override
  Future<void> delete({required String scope, required int baseVersion}) async {
    values.remove(scope);
  }
}

class _FakeMusicPlaybackSessionController
    extends MusicPlaybackSessionController {
  _FakeMusicPlaybackSessionController(this.player);

  final MusicAudioPlayback player;

  @override
  MusicPlaybackSession build() {
    return MusicPlaybackSession(player: player, lastError: null);
  }

  @override
  Future<void> syncFromCenterState() async {}
}

class _SilentMusicAudioPlayback implements MusicAudioPlayback {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);

  MusicAudioPlayerState _state = const MusicAudioPlayerState(
    playing: true,
    position: Duration(seconds: 3),
    duration: Duration(minutes: 3),
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
    _state = _state.copyWith(position: position);
    _positionController.add(position);
  }

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
