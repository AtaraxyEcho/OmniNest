part of 'music_controller_test.dart';

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
