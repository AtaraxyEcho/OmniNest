part of 'music_controller_test.dart';

/// 喜欢支路可门闩的假 API：验证渐进发布时歌单先行、喜欢后到。
class _GatedLikedMusicApi extends _FakeMusicApi {
  final Completer<void> likedGate = Completer<void>();

  @override
  Future<MusicPagedResult<OnlineTrack>> platformLikedTracks(
    String platform, {
    int page = 0,
    int size = 1000,
    bool refresh = false,
  }) async {
    await likedGate.future;
    return super.platformLikedTracks(
      platform,
      page: page,
      size: size,
      refresh: refresh,
    );
  }
}

/// 大体量喜欢列表的假 API：验证分页首屏与触底续载。
class _ManyLikedMusicApi extends _FakeMusicApi {
  static const int trackCount = 450;

  final List<OnlineTrack> _tracks = List<OnlineTrack>.generate(
    trackCount,
    (index) => OnlineTrack(
      platform: 'netease',
      songId: 'liked-$index',
      title: 'Liked Song $index',
      artistName: 'Cloud Artist',
    ),
  );

  @override
  Future<MusicPagedResult<OnlineTrack>> platformLikedTracks(
    String platform, {
    int page = 0,
    int size = 1000,
    bool refresh = false,
  }) async {
    return _paged(_tracks, page, size);
  }
}

/// 续载响应可门闩的假 API：验证刷新重置后在途旧页被丢弃。
class _GatedMoreLikedMusicApi extends _ManyLikedMusicApi {
  final Completer<void> moreGate = Completer<void>();

  @override
  Future<MusicPagedResult<OnlineTrack>> platformLikedTracks(
    String platform, {
    int page = 0,
    int size = 1000,
    bool refresh = false,
  }) async {
    if (page > 0 && size == 200) {
      await moreGate.future;
    }
    return super.platformLikedTracks(
      platform,
      page: page,
      size: size,
      refresh: refresh,
    );
  }
}

void registerMusicPlatformTests() {
  test(
    'platform library preloads playlist tracks after entering music',
    () async {
      final api =
          _FakeMusicApi()
            ..platformStatuses = const <MusicPlatformStatus>[
              MusicPlatformStatus(
                platform: 'netease',
                displayName: 'NetEase Cloud Music',
                enabled: true,
                connected: true,
                capabilities: MusicPlatformCapabilities(playlists: true),
              ),
            ];
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicPlatformLibraryProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(musicPlatformLibraryProvider).value!;
      expect(api.platformPlaylistTrackRequests, ['netease:netease-list-1']);
      expect(
        state.coverUrlForPlaylist(state.playlistsByPlatform['netease']!.single),
        'https://example.com/netease-cover.jpg',
      );
    },
  );

  test('渐进发布：歌单随首帧落地，喜欢列表回源完成后补发', () async {
    final api =
        _GatedLikedMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(
                playlists: true,
                likedTracks: true,
              ),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    // build 完成即可拿到歌单；喜欢支路仍被门闩挂起，不得拖住首帧。
    final early = await container.read(musicPlatformLibraryProvider.future);
    expect(early.playlists, isNotEmpty);
    expect(early.likedTracks, isEmpty);

    api.likedGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final settled = container.read(musicPlatformLibraryProvider).value!;
    expect(settled.playlists, isNotEmpty);
    expect(settled.likedTracks, isNotEmpty);
  });

  test('渐进发布的迟到喜欢结果不覆盖后续整刷', () async {
    final api =
        _GatedLikedMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(
                playlists: true,
                likedTracks: true,
              ),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(musicPlatformLibraryProvider.future);
    // 首帧后立即整刷：refresh 的 _load 入口同步推进世代，随后才放行门闩，
    // 挂起的渐进结果必须被世代守卫丢弃。
    final refreshFuture =
        container.read(musicPlatformLibraryProvider.notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    api.likedGate.complete();
    await refreshFuture;

    final refreshed = container.read(musicPlatformLibraryProvider).value!;
    expect(refreshed.likedTracks, isNotEmpty);
    final refreshedLikedByPlatform = refreshed.likedTracksByPlatform;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 迟到的渐进结果未覆盖整刷结果：喜欢列表仍指向整刷落地的同一集合。
    final settled = container.read(musicPlatformLibraryProvider).value!;
    expect(
      identical(settled.likedTracksByPlatform, refreshedLikedByPlatform),
      isTrue,
    );
  });

  test('喜欢列表分页：首屏只取 200 条，触底续载补齐剩余页', () async {
    final api =
        _ManyLikedMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(likedTracks: true),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(musicPlatformLibraryProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final first = container.read(musicPlatformLibraryProvider).value!;
    // 首屏只解码首页载荷，整表 450 条不再一次性压进 UI isolate。
    expect(first.likedTracks, hasLength(200));
    expect(first.hasMoreLikedTracks(const <String>['netease']), isTrue);

    await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadMoreLikedTracks(const <String>['netease']);
    // 450 条按 200/页需两次续载：第一次到 400，仍可续。
    expect(
      container.read(musicPlatformLibraryProvider).value!.likedTracks,
      hasLength(400),
    );

    await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadMoreLikedTracks(const <String>['netease']);
    final second = container.read(musicPlatformLibraryProvider).value!;
    expect(second.likedTracks, hasLength(450));
    expect(second.hasMoreLikedTracks(const <String>['netease']), isFalse);
    expect(second.loadingMoreLiked, isFalse);
    // 已取尽后重复触底不再发请求、也不再发布新状态。
    await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadMoreLikedTracks(const <String>['netease']);
    expect(
      identical(
        container
            .read(musicPlatformLibraryProvider)
            .value!
            .likedTracksByPlatform,
        second.likedTracksByPlatform,
      ),
      isTrue,
    );
  });

  test('喜欢列表整表加载供队列重建：一次取满后端单页上限', () async {
    final api =
        _ManyLikedMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(likedTracks: true),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    // 队列重建发生在音乐页挂载之后：先等平台曲库落地再触发整表加载。
    await container.read(musicPlatformLibraryProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final all = await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadAllLikedTracks('netease');

    expect(all, hasLength(_ManyLikedMusicApi.trackCount));
    final state =
        container.read(musicPlatformLibraryProvider).value ??
        const MusicPlatformLibraryState();
    expect(state.likedTracks, hasLength(_ManyLikedMusicApi.trackCount));
    expect(state.hasMoreLikedTracks(const <String>['netease']), isFalse);
  });

  test('刷新重置喜欢列表后，在途续载的旧响应不得追加', () async {
    final api =
        _GatedMoreLikedMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(likedTracks: true),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 触底续载第 1 页（200~399），响应被门闩挂起。
    final loadMore = container
        .read(musicPlatformLibraryProvider.notifier)
        .loadMoreLikedTracks(const <String>['netease']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // 续载在途期间整刷：喜欢列表重置回首屏 200 条，世代与请求序号均推进。
    await container.read(musicPlatformLibraryProvider.notifier).refresh();
    expect(
      container.read(musicPlatformLibraryProvider).value!.likedTracks,
      hasLength(200),
    );

    api.moreGate.complete();
    await loadMore;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 旧的第 1 页响应被丢弃：不出现 200~399 的区间缺口式追加。
    expect(
      container.read(musicPlatformLibraryProvider).value!.likedTracks,
      hasLength(200),
    );
    // 新一轮续载仍可正常推进。
    await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadMoreLikedTracks(const <String>['netease']);
    expect(
      container.read(musicPlatformLibraryProvider).value!.likedTracks,
      hasLength(400),
    );
  });

  test('late search response cannot replace the latest query', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(search: true),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    await container.read(musicPlatformLibraryProvider.future);
    final searchSubscription = container.listen(
      musicDeckSearchProvider,
      (previous, next) {},
    );
    addTearDown(searchSubscription.close);
    final controller = container.read(musicDeckSearchProvider.notifier);
    const sources = <MusicPlatform>{MusicPlatform.netease};

    controller.updateQuery('older', sources);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    controller.updateQuery('newer', sources);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    api.completeSearch('newer');
    await Future<void>.delayed(Duration.zero);
    api.completeSearch('older');
    await Future<void>.delayed(Duration.zero);

    final state = container.read(musicDeckSearchProvider);
    expect(state.query, 'newer');
    expect(
      state.results[MusicPlatform.netease]?.single.track.title,
      'newer result',
    );
  });

  test('搜索最后一个监听者释放后丢弃迟到响应', () async {
    final api =
        _FakeMusicApi()
          ..platformStatuses = const <MusicPlatformStatus>[
            MusicPlatformStatus(
              platform: 'netease',
              displayName: 'NetEase Cloud Music',
              enabled: true,
              connected: true,
              capabilities: MusicPlatformCapabilities(search: true),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    await container.read(musicPlatformLibraryProvider.future);
    final subscription = container.listen(
      musicDeckSearchProvider,
      (previous, next) {},
    );
    final controller = container.read(musicDeckSearchProvider.notifier);

    controller.updateQuery('pending', const <MusicPlatform>{
      MusicPlatform.netease,
    });
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(api.pendingSearches, contains('pending'));

    subscription.close();
    await container.pump();
    api.completeSearch('pending');
    await Future<void>.delayed(Duration.zero);

    final nextSubscription = container.listen(
      musicDeckSearchProvider,
      (previous, next) {},
    );
    addTearDown(nextSubscription.close);
    expect(container.read(musicDeckSearchProvider).query, isEmpty);
  });

  testWidgets('移动搜索页面卸载时不修改 Provider', (tester) async {
    final api = _FakeMusicApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicApiProvider.overrideWithValue(api),
          musicPlatformLibraryProvider.overrideWith(
            _EmptyMusicPlatformLibraryController.new,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MusicDeckMobileSearchPage(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
