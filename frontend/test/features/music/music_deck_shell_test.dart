import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_layout.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_mini_player.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_shell.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';

void main() {
  testWidgets('移动端查看全部页面提供返回首页控件', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MobileShellScope(hosted: true, child: MusicDeckShell()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
      findsNothing,
    );
    await tester.tap(find.text('View All').first);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
      findsNothing,
    );
    expect(find.text('View All'), findsNWidgets(2));
  });

  testWidgets('桌面壳层语义不因禁用态播放按钮整页合并失效', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
          musicPlaybackSessionProvider.overrideWith(
            _StubPlaybackSessionController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MusicDeckShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 不变量守卫：语义树根不得带按钮语义。实机 Web 上禁用态播放按钮的
    // 语义曾沿祖先链合并到树根致整页标记为 disabled 按钮（D-002）；
    // 该合并仅在引擎语义管线出现，VM 测试无法复现，此断言仅锁定守卫边界。
    final handle = tester.ensureSemantics();
    await tester.pump();

    // ignore: deprecated_member_use
    final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode;
    expect(root, isNotNull);
    expect(root!.flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('宽屏三张玻璃卡等高（导航/内容/正在播放）', (tester) async {
    tester.view.physicalSize = const Size(1900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
          musicPlaybackSessionProvider.overrideWith(
            _StubPlaybackSessionController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MusicDeckShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 左卡=含「首页」导航项的最近玻璃卡；右卡=含「正在播放」标题的最近玻璃卡
    // （内容区存在嵌套小玻璃卡，故按内容锚定左右两卡分别测量）。
    Size? sizeOf(Finder anchor) {
      final card =
          find
              .ancestor(of: anchor, matching: find.byType(MusicDeckGlass))
              .first;
      return (card.evaluate().single.findRenderObject() as RenderBox?)?.size;
    }

    final leftSize = sizeOf(find.text('首页'));
    final rightSize = sizeOf(find.text('正在播放'));
    expect(leftSize, isNotNull);
    expect(rightSize, isNotNull);
    expect(leftSize!.height, rightSize!.height, reason: '左右两张玻璃卡高度必须一致');
    expect(leftSize.width, rightSize.width, reason: '左右两张玻璃卡宽度必须一致');
  });

  testWidgets('桌面侧卡与播放岛共用底线，播放岛提供播放模式入口', (tester) async {
    tester.view.physicalSize = const Size(1900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 走真实中心控制器：播放模式命令是控制器上的扩展方法，替身无法拦截，
    // 只有端到端读状态才能证明控制岛接到了同一条轮换命令。
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(_IslandPlayModeStubApi()),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
        musicPlatformLibraryProvider.overrideWith(
          _FakeMusicPlatformLibraryController.new,
        ),
        musicPlaybackSessionProvider.overrideWith(
          _StubPlaybackSessionController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MusicDeckShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Rect glassRect(Finder anchor) => tester.getRect(
      find.ancestor(of: anchor, matching: find.byType(MusicDeckGlass)).first,
    );

    final island = tester.getRect(find.byType(MusicDeckMiniPlayer));
    final leftCard = glassRect(find.text('首页'));
    final rightCard = glassRect(find.text('正在播放'));

    // 三块表面落在同一条基线上：侧卡不再被抬高整个岛高。
    expect(island.bottom, moreOrLessEquals(leftCard.bottom, epsilon: 0.5));
    expect(island.bottom, moreOrLessEquals(rightCard.bottom, epsilon: 0.5));
    // 播放岛取中内容列的整条带宽，与两侧卡各留一个 cardGap。
    const gap = MusicDeckDesktopLayout.cardGap;
    expect(island.left, moreOrLessEquals(leftCard.right + gap, epsilon: 0.5));
    expect(
      rightCard.left,
      moreOrLessEquals(island.right + gap, epsilon: 0.5),
      reason: '岛宽不再按比例收缩，超宽屏只按上限收束',
    );
    expect(island.height, MusicDeckMiniPlayer.barHeight);

    // 播放模式入口与沉浸页 Dock 同源：三态各一图标，点击走轮换命令。
    expect(
      container.read(musicCenterControllerProvider).value!.playMode,
      MusicPlayMode.repeatOne,
    );
    expect(find.byType(MusicPlayModeButton), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);

    await tester.tap(find.byType(MusicPlayModeButton));
    await tester.pump();
    expect(
      container.read(musicCenterControllerProvider).value!.playMode,
      MusicPlayMode.sequential,
      reason: '单曲循环档点击后轮换回顺序播放',
    );
    // 图标切换走 160ms 淡入淡出，推进到时序结束后再断言两档图标。
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.repeat_one_rounded), findsNothing);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    // 播放队列持久化带 160ms 防抖定时器，推进时钟让它自然落地。
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('本地资源列表提供删除入口并进入永久删除确认', (tester) async {
    tester.view.physicalSize = const Size(1900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [_localManagementTrack],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
          musicPlaybackSessionProvider.overrideWith(
            _StubPlaybackSessionController.new,
          ),
          authSessionProvider.overrideWith(_ManageSessionNotifier.new),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MusicDeckShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('本地资源').first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('永久删除？'), findsOneWidget);
    expect(
      find.text('是否删除“Local Management Track”及其存储文件？此操作无法撤销。'),
      findsOneWidget,
    );

    // 取消不得触发删除：确认框关闭后列表仍在原位。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('永久删除？'), findsNothing);
    expect(find.text('Local Management Track'), findsOneWidget);
  });
}

const MusicTrack _localManagementTrack = MusicTrack(
  id: 'track-local-1',
  fileNodeId: 'file-local-1',
  title: 'Local Management Track',
  artistName: 'Local Artist',
  albumTitle: 'Local Album',
  format: 'mp3',
  favorite: false,
);

class _ManageSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-local',
      username: 'local',
      role: 'USER',
      permissions: const <String>{'media:write'},
    ),
  );
}

class _FakeMusicCenterController extends MusicCenterController {
  _FakeMusicCenterController(this.initialState);

  final MusicCenterState initialState;

  @override
  Future<MusicCenterState> build() async => initialState;
}

class _MemoryMusicPlaybackQueueStore implements MusicPlaybackQueueStore {
  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async => null;

  @override
  Future<void> save(
    String ownerId,
    MusicPlaybackQueueSnapshot snapshot,
  ) async {}
}

/// 只提供控制岛用例走到的链路，恢复的播放模式固定为单曲循环。
class _IslandPlayModeStubApi implements MusicApi {
  MusicPagedResult<T> _emptyPage<T>() =>
      MusicPagedResult<T>(items: <T>[], page: 0, size: 30);

  @override
  Future<MusicDashboard> dashboard() async =>
      MusicDashboard.fromJson(const <String, dynamic>{});

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => _emptyPage<MusicTrack>();

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async => _emptyPage<MusicAlbum>();

  @override
  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async => _emptyPage<MusicArtist>();

  @override
  Future<List<MusicPlaylist>> playlists() async => const <MusicPlaylist>[];

  @override
  Future<List<MusicRecentEntry>> recentItems() async =>
      const <MusicRecentEntry>[];

  @override
  Future<MusicTrack?> lastPlayed() async => null;

  @override
  Future<MusicPlaybackQueueSnapshot> playbackQueue() async =>
      MusicPlaybackQueueSnapshot.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[],
        'currentIndex': -1,
        'shuffleEnabled': false,
        'repeatMode': 'one',
      });

  @override
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async => snapshot;

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMusicPlatformLibraryController
    extends MusicPlatformLibraryController {
  @override
  Future<MusicPlatformLibraryState> build() async {
    return const MusicPlatformLibraryState();
  }
}

class _StubPlaybackSessionController extends MusicPlaybackSessionController {
  static const _NoopAudioPlayback _player = _NoopAudioPlayback._();

  @override
  MusicPlaybackSession build() {
    return const MusicPlaybackSession(player: _player, lastError: null);
  }
}

class _NoopAudioPlayback implements MusicAudioPlayback {
  const _NoopAudioPlayback._();
  static const MusicAudioPlayerStreams _streams = MusicAudioPlayerStreams(
    position: Stream<Duration>.empty(),
    duration: Stream<Duration>.empty(),
    volume: Stream<double>.empty(),
    completed: Stream<bool>.empty(),
    log: Stream<MusicAudioLog>.empty(),
  );

  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState();

  @override
  MusicAudioPlayerStreams get stream => _streams;

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
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();
}
