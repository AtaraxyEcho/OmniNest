part of 'music_controller_test.dart';

const _preloadTestAlbum = MusicAlbum(
  id: 'album-1',
  title: 'Backfilled Album',
  artistName: 'Cloud Artist',
  trackCount: 3,
);

const _preloadTestArtist = MusicArtist(
  id: 'artist-1',
  name: 'Cloud Artist',
  trackCount: 3,
  albumCount: 1,
);

const _neteaseLibraryStatus = MusicPlatformStatus(
  platform: 'netease',
  displayName: 'NetEase Cloud Music',
  enabled: true,
  connected: true,
  capabilities: MusicPlatformCapabilities(playlists: true, likedTracks: true),
);

const _connectedNeteaseStatus = MusicPlatformStatus(
  platform: 'netease',
  displayName: 'NetEase Cloud Music',
  enabled: true,
  connected: true,
  capabilities: MusicPlatformCapabilities(playlists: true),
);

List<OnlinePlaylist> _onlinePlaylists(int count) {
  return List<OnlinePlaylist>.generate(
    count,
    (index) => OnlinePlaylist(
      platform: 'netease',
      playlistId: 'list-$index',
      name: 'Collection $index',
    ),
    growable: false,
  );
}

/// 注册 Music 中心首帧分层加载的回归用例。
///
/// 首帧只等本分区必需请求，仪表盘点、专辑/歌手全量列表与平台账号资料由
/// `_backfillSecondary` 在首帧之后补齐。这里锁住三件事：分层顺序、旧回填不得
/// 覆盖新一轮刷新、补齐时不重播已经发布并被用户关掉的旧错误。
void registerMusicFirstFrameTieringTests() {
  test('首帧只等必需请求，次级切片在其后补齐', () async {
    final api =
        _FakeMusicApi()
          ..dashboardValue = const MusicDashboard(
            trackCount: 7,
            albumCount: 1,
            artistCount: 1,
            playHistoryCount: 0,
            recentTracks: [],
            recentAlbums: [],
            featuredArtists: [],
          )
          ..libraryAlbums = [_preloadTestAlbum]
          ..libraryArtists = [_preloadTestArtist]
          ..platformInfoValue = const PlatformUserInfo(
            platform: 'netease',
            nickname: 'Cloud User',
          )
          ..secondaryGate = Completer<void>();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final firstFrame = await container.read(
      musicCenterControllerProvider.future,
    );

    // 必需切片已就位，次级切片仍为空：首帧没有被最慢的账号资料回源压住。
    expect(firstFrame.tracks, hasLength(2));
    expect(firstFrame.playlists, hasLength(1));
    expect(firstFrame.dashboard.trackCount, 0);
    expect(firstFrame.albums, isEmpty);
    expect(firstFrame.artists, isEmpty);
    expect(firstFrame.neteaseUserInfo, isNull);
    expect(api.secondaryRequests, hasLength(4));

    api.secondaryGate!.complete();
    await pumpEventQueue();

    final filled = container.read(musicCenterControllerProvider).value!;
    expect(filled.dashboard.trackCount, 7);
    expect(filled.albums.single.id, 'album-1');
    expect(filled.artists.single.id, 'artist-1');
    expect(filled.neteaseUserInfo?.nickname, 'Cloud User');
    // 补齐只填延后槽，不动首帧已发布的数据。
    expect(filled.tracks, firstFrame.tracks);
    expect(filled.playlists, firstFrame.playlists);
  });

  test('次级回填晚于新一轮刷新时不得覆盖新状态', () async {
    final api =
        _FakeMusicApi()
          ..libraryAlbums = [_preloadTestAlbum]
          ..secondaryGate = Completer<void>();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    // 首轮回填仍挂起，用户此刻发起刷新并先完成：新一轮取到的数据才是最终状态。
    api.gateSecondary = false;
    api.libraryAlbums = [];
    final refreshing =
        container.read(musicCenterControllerProvider.notifier).refresh();
    await refreshing;
    expect(
      container.read(musicCenterControllerProvider).value!.albums,
      isEmpty,
    );

    // 旧一轮回包更晚到达时生成号已过期，不得把 album-1 再写回状态。
    api.secondaryGate!.complete();
    await pumpEventQueue();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.albums, isEmpty);
  });

  test('次级回填只追加本轮新错误，不重播已关掉的旧部分失败', () async {
    final api =
        _FakeMusicApi()
          ..playlistsError = const AppException(
            code: 'PLAYLIST_LOAD_FAILED',
            message: '歌单加载失败',
          )
          ..dashboardError = const AppException(
            code: 'DASHBOARD_LOAD_FAILED',
            message: '统计加载失败',
          )
          ..secondaryGate = Completer<void>();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final firstFrame = await container.read(
      musicCenterControllerProvider.future,
    );
    expect(firstFrame.errorMessage, 'PLAYLIST_LOAD_FAILED');

    container.read(musicCenterControllerProvider.notifier).clearError();
    api.secondaryGate!.complete();
    await pumpEventQueue();

    // 用户已关闭的必需请求错误不得被回填再弹一次；本轮新错误照常上报。
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.errorMessage, 'DASHBOARD_LOAD_FAILED');
  });
}

/// 注册在线歌单预热合并发布的回归用例。
///
/// 预热必须一次性标记加载中、一次性合并结果发布，并在刷新后保留已缓存曲目，
/// 否则首页会按歌单数量连续整页重建、每次刷新重复回源全部第三方歌单。
void registerMusicPlaylistPreloadTests() {
  test('歌单预热合并为两次发布而不是逐条发布', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(3)
          ..playlistTracksGate = Completer<void>();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final trackCounts = <int>[];
    final subscription = container.listen(musicPlatformLibraryProvider, (
      previous,
      next,
    ) {
      final value = next.asData?.value;
      if (value != null) {
        trackCounts.add(value.playlistTracks.length);
      }
    });
    addTearDown(subscription.close);

    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();

    final loading = container.read(musicPlatformLibraryProvider).value!;
    expect(loading.loadingPlaylistKeys, {
      'netease:list-0',
      'netease:list-1',
      'netease:list-2',
    });
    expect(loading.playlistTracks, isEmpty);
    expect(trackCounts, <int>[0, 0]);

    api.playlistTracksGate!.complete();
    await pumpEventQueue();

    expect(trackCounts, <int>[0, 0, 3]);
    expect(api.platformPlaylistTrackRequests, [
      'netease:list-0',
      'netease:list-1',
      'netease:list-2',
    ]);
  });

  test('刷新保留已缓存歌单曲目并只回源新增歌单', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(2);
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();
    expect(api.platformPlaylistTrackRequests, hasLength(2));

    api.neteasePlaylists = _onlinePlaylists(3);
    await container.read(musicPlatformLibraryProvider.notifier).refresh();
    await pumpEventQueue();

    expect(api.platformPlaylistTrackRequests, [
      'netease:list-0',
      'netease:list-1',
      'netease:list-2',
    ]);
    final state = container.read(musicPlatformLibraryProvider).value!;
    expect(state.playlistTracks.keys, <String>{
      'netease:list-0',
      'netease:list-1',
      'netease:list-2',
    });
    expect(state.loadingPlaylistKeys, isEmpty);
  });

  test('预热只取首页曲目，打开歌单时补齐首屏页', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(1)
          ..playlistTrackCount = 800;
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();

    final preloaded = container.read(musicPlatformLibraryProvider).value!;
    final preloadPage = preloaded.playlistTracks['netease:list-0']!;
    // 预热只需要封面与预览，载荷按页大小截断，但总数告诉它还有更多。
    expect(api.platformPlaylistTrackSizes['netease:list-0'], 50);
    expect(preloadPage.items, hasLength(50));
    expect(preloadPage.totalElements, 800);
    expect(preloadPage.hasMore, isTrue);
    expect(
      preloaded.coverUrlForPlaylist(preloaded.playlists.first),
      isNotEmpty,
    );

    final opened = await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadPlaylistTracks(preloaded.playlists.first);

    // 打开只取首屏页：详情按滚动续载，整表留给播放补齐。
    expect(api.platformPlaylistTrackSizes['netease:list-0'], 200);
    expect(opened, hasLength(200));
    final loaded = container.read(musicPlatformLibraryProvider).value!;
    expect(loaded.playlistTracks['netease:list-0']!.hasMore, isTrue);

    final all = await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadAllPlaylistTracks(preloaded.playlists.first);

    expect(api.platformPlaylistTrackSizes['netease:list-0'], 1000);
    expect(all, hasLength(800));
    final full = container.read(musicPlatformLibraryProvider).value!;
    expect(full.playlistTracks['netease:list-0']!.hasMore, isFalse);
  });

  test('显式刷新只回源列表，打开歌单才单独取新页', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _neteaseLibraryStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(1);
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();
    expect(api.platformListRefreshFlags['playlists'], isNot(true));
    final preloadRequests = api.platformPlaylistTrackRequests.length;

    await container.read(musicPlatformLibraryProvider.notifier).refresh();
    await pumpEventQueue();

    // 用户刷新让歌单与喜欢列表回源，但已缓存的曲目页不重复下载。
    expect(api.platformListRefreshFlags['playlists'], isTrue);
    expect(api.platformListRefreshFlags['likedTracks'], isTrue);
    expect(api.platformPlaylistTrackRequests, hasLength(preloadRequests));

    final playlist =
        container.read(musicPlatformLibraryProvider).value!.playlists.first;
    await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadPlaylistTracks(playlist, forceRefresh: true);

    expect(api.platformPlaylistTrackSizes['netease:list-0'], 200);
    expect(api.platformListRefreshFlags['playlistTracks'], isTrue);
    expect(api.platformPlaylistTrackRequests, hasLength(preloadRequests + 1));
  });

  test('预热只覆盖前 8 个歌单，其余走按需加载', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(10);
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();

    expect(api.platformPlaylistTrackRequests, <String>[
      for (var index = 0; index < 8; index++) 'netease:list-$index',
    ]);
    final state = container.read(musicPlatformLibraryProvider).value!;
    expect(state.playlists, hasLength(10));
  });

  test('晚到的预热首页不会截断已加载的歌单详情', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(1)
          ..playlistTrackCount = 800
          ..holdPlaylistTracks = true;
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();
    final playlist =
        container.read(musicPlatformLibraryProvider).value!.playlists.first;
    // 预热首页仍被挂起时打开歌单：两个请求同时在途，谁都可以先回。
    final opening = container
        .read(musicPlatformLibraryProvider.notifier)
        .loadPlaylistTracks(playlist);
    await pumpEventQueue();
    expect(api.heldPlaylistTracks, hasLength(2));

    api.heldPlaylistTracks[1].released.complete();
    expect(await opening, hasLength(200));
    // 预热页更小且更晚到达：必须丢弃，否则列表被截回首页条数。
    api.heldPlaylistTracks[0].released.complete();
    await pumpEventQueue();

    final state = container.read(musicPlatformLibraryProvider).value!;
    final page = state.playlistTracks['netease:list-0']!;
    expect(page.items, hasLength(200));
    expect(page.size, 200);
    expect(state.loadingPlaylistKeys, isEmpty);
  });

  test('详情续载按页追加且不会并发重复请求', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(1)
          ..playlistTrackCount = 800;
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();
    final notifier = container.read(musicPlatformLibraryProvider.notifier);
    final playlist =
        container.read(musicPlatformLibraryProvider).value!.playlists.first;
    await notifier.loadPlaylistTracks(playlist);
    final requests = api.platformPlaylistTrackRequests.length;

    final first = notifier.loadMorePlaylistTracks(playlist);
    final second = notifier.loadMorePlaylistTracks(playlist);
    await Future.wait(<Future<void>>[first, second]);

    expect(api.platformPlaylistTrackRequests, hasLength(requests + 1));
    expect(api.platformPlaylistTrackPages['netease:list-0'], 1);
    final state = container.read(musicPlatformLibraryProvider).value!;
    final page = state.playlistTracks['netease:list-0']!;
    expect(page.items, hasLength(400));
    // 追加后仍有下一页，且续载结束后不再显示底部进度。
    expect(page.hasMore, isTrue);
    expect(state.appendingPlaylistKeys, isEmpty);
  });

  test('连续点击播放整队只回源一次', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            _connectedNeteaseStatus,
          ]
          ..neteasePlaylists = _onlinePlaylists(1)
          ..playlistTrackCount = 800;
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();
    final notifier = container.read(musicPlatformLibraryProvider.notifier);
    final playlist =
        container.read(musicPlatformLibraryProvider).value!.playlists.first;
    final requests = api.platformPlaylistTrackRequests.length;

    final first = notifier.loadAllPlaylistTracks(playlist);
    final second = notifier.loadAllPlaylistTracks(playlist);

    expect(await first, hasLength(800));
    expect(await second, hasLength(800));
    expect(api.platformPlaylistTrackRequests, hasLength(requests + 1));
    expect(api.platformPlaylistTrackSizes['netease:list-0'], 1000);
    final state = container.read(musicPlatformLibraryProvider).value!;
    expect(state.playlistTracks['netease:list-0']!.items, hasLength(800));
    expect(state.loadingPlaylistKeys, isEmpty);
  });
}
