part of 'music_controller_test.dart';

List<MusicPlayableItem> _fourTrackItems(_FakeMusicApi api) {
  return <MusicPlayableItem>[
    MusicPlayableItem.local(api.track),
    MusicPlayableItem.local(api.secondTrack),
    MusicPlayableItem.local(api.thirdTrack),
    MusicPlayableItem.local(api.fourthTrack),
  ];
}

void registerMusicQueueSourceTests() {
  test('playTrack binds the library source outside detail sections', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playTrack(api.track);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.queueSource.kind, MusicQueueSourceKind.library);
    expect(state.queueSource.platforms, ['local']);
    expect(state.playbackItems.map((item) => item.playableKey).toList(), [
      'local:track-1',
      'local:track-2',
    ]);
  });

  test('playTrack inside playlist detail binds the playlist source', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    await controller.openPlaylist(api.playlist);
    await controller.playTrack(api.secondTrack);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.queueSource.kind, MusicQueueSourceKind.playlist);
    expect(state.queueSource.id, 'playlist-1');
    expect(state.playbackItems.map((item) => item.playableKey).toList(), [
      'local:track-1',
      'local:track-2',
    ]);
    expect(state.playbackIndex, 1);
  });

  test('playTrack on a queued item keeps the bound queue and source', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    // 以歌单来源绑定单曲队列后，对队列内曲目按播放键不应重绑为曲库。
    await controller.playItems(
      <MusicPlayableItem>[MusicPlayableItem.local(api.track)],
      startIndex: 0,
      source: const MusicQueueSource(
        kind: MusicQueueSourceKind.playlist,
        id: 'playlist-1',
        title: 'Road Trip',
      ),
    );
    await controller.playTrack(api.track);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.queueSource.kind, MusicQueueSourceKind.playlist);
    expect(state.playbackItems, hasLength(1));
    expect(state.isPlaying, isTrue);
  });

  test(
    'nextTrack crosses the loaded page boundary via lazy pagination',
    () async {
      final api = _FakeMusicApi();
      for (var index = 0; index < 148; index++) {
        api.libraryTracks.add(
          MusicTrack(
            id: 'bulk-$index',
            fileNodeId: 'file-bulk-$index',
            title: 'Bulk $index',
            artistName: 'Bulk Artist',
            albumTitle: 'Bulk Album',
            format: 'mp3',
            favorite: false,
          ),
        );
      }
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final state = await container.read(musicCenterControllerProvider.future);
      final controller = container.read(musicCenterControllerProvider.notifier);
      final loadedItems = state.tracks
          .map(MusicPlayableItem.local)
          .toList(growable: false);

      await controller.playItems(
        loadedItems,
        startIndex: 99,
        source: MusicQueueSource.localLibrary(),
      );
      await controller.nextTrack();

      final next = container.read(musicCenterControllerProvider).asData!.value;
      expect(next.currentItem?.playableKey, 'local:bulk-98');
      expect(next.playbackItems, hasLength(150));
      expect(next.tracks, hasLength(150));
      expect(next.hasMoreTracks, isFalse);
      expect(next.isPlaying, isTrue);
      expect(api.tracksPageRequests, [0, 1]);
    },
  );

  test('page fetch failure stops playback without purging the queue', () async {
    final api = _FakeMusicApi();
    for (var index = 0; index < 148; index++) {
      api.libraryTracks.add(
        MusicTrack(
          id: 'bulk-$index',
          fileNodeId: 'file-bulk-$index',
          title: 'Bulk $index',
          artistName: 'Bulk Artist',
          albumTitle: 'Bulk Album',
          format: 'mp3',
          favorite: false,
        ),
      );
    }
    api.tracksPageErrors[1] = const AppException(
      code: 'REQUEST_TIMEOUT',
      message: '请求超时，请稍后重试',
    );
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final state = await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final loadedItems = state.tracks
        .map(MusicPlayableItem.local)
        .toList(growable: false);

    await controller.playItems(
      loadedItems,
      startIndex: 99,
      source: MusicQueueSource.localLibrary(),
    );
    await controller.nextTrack();

    final next = container.read(musicCenterControllerProvider).asData!.value;
    expect(next.currentItem?.playableKey, 'local:bulk-97');
    expect(next.playbackItems, hasLength(100));
    expect(next.isPlaying, isFalse);
    expect(next.errorMessage, contains('REQUEST_TIMEOUT'));
  });

  test('clearQueue then nextTrack is a no-op', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    await controller.playTrack(api.track);
    controller.clearQueue();
    await controller.nextTrack();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.playbackItems, isEmpty);
    expect(state.currentItem?.playableKey, 'local:track-1');
    expect(api.playbackPlanTrackIds, ['track-1']);
  });

  test(
    'playQueueIndex jumps within the queue without changing source',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);
      final controller = container.read(musicCenterControllerProvider.notifier);

      await controller.playItems(
        _fourTrackItems(api),
        startIndex: 0,
        source: const MusicQueueSource(
          kind: MusicQueueSourceKind.playlist,
          id: 'playlist-1',
          title: 'Road Trip',
        ),
      );
      await controller.playQueueIndex(3);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(state.currentItem?.playableKey, 'local:track-4');
      expect(state.playbackIndex, 3);
      expect(state.queueSource.kind, MusicQueueSourceKind.playlist);
      expect(state.playbackItems, hasLength(4));
    },
  );

  test(
    'openAlbum fetches full album tracks from the source endpoint',
    () async {
      final api = _FakeMusicApi();
      final albumTrack = MusicTrack(
        id: 'album-only',
        fileNodeId: 'file-album-only',
        title: 'Deep Cut',
        artistName: 'Omni Band',
        albumTitle: 'Unknown Album',
        format: 'flac',
        favorite: false,
      );
      api.albumTracksById['album-1'] = [albumTrack, api.track, api.secondTrack];
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);
      final controller = container.read(musicCenterControllerProvider.notifier);

      await controller.openAlbum(
        const MusicAlbum(
          id: 'album-1',
          title: 'Unknown Album',
          artistName: 'Omni Band',
          trackCount: 3,
        ),
      );

      final state = container.read(musicCenterControllerProvider).value!;
      expect(api.albumTracksRequests, ['album-1']);
      expect(state.selectedAlbumTracks.map((track) => track.id).toList(), [
        'album-only',
        'track-1',
        'track-2',
      ]);
    },
  );

  test(
    'startup rebuilds the playlist queue from the snapshot source',
    () async {
      final api = _FakeMusicApi();
      api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
        items: <MusicPlayableItem>[MusicPlayableItem.local(api.secondTrack)],
        currentIndex: 0,
        source: const MusicQueueSource(
          kind: MusicQueueSourceKind.playlist,
          id: 'playlist-1',
          title: 'Road Trip',
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(api),
          musicPlaybackQueueOwnerIdProvider.overrideWith(
            (ref) async => 'user-a',
          ),
        ],
      );
      addTearDown(container.dispose);

      final firstFrame = await container.read(
        musicCenterControllerProvider.future,
      );
      // 首帧不被来源重建拖住：先用窗口快照，来源已经标对。
      expect(firstFrame.playbackItems.map((item) => item.playableKey), [
        'local:track-2',
      ]);
      expect(firstFrame.queueSource.kind, MusicQueueSourceKind.playlist);

      await pumpEventQueue();
      final state = container.read(musicCenterControllerProvider).value!;

      expect(state.playbackItems.map((item) => item.playableKey).toList(), [
        'local:track-1',
        'local:track-2',
      ]);
      expect(state.playbackIndex, 1);
      expect(state.queueSource.kind, MusicQueueSourceKind.playlist);
      expect(state.currentItem?.playableKey, 'local:track-2');
    },
  );

  test(
    'startup falls back to the window snapshot when rebuild fails',
    () async {
      final api =
          _FakeMusicApi()
            ..playlistTracksError = const AppException(
              code: '5001',
              message: '歌单不存在',
            );
      api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
        items: <MusicPlayableItem>[MusicPlayableItem.local(api.secondTrack)],
        currentIndex: 0,
        source: const MusicQueueSource(
          kind: MusicQueueSourceKind.playlist,
          id: 'playlist-1',
          title: 'Road Trip',
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(api),
          musicPlaybackQueueOwnerIdProvider.overrideWith(
            (ref) async => 'user-a',
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(musicCenterControllerProvider.future);
      await pumpEventQueue();
      final state = container.read(musicCenterControllerProvider).value!;

      expect(state.playbackItems.map((item) => item.playableKey), [
        'local:track-2',
      ]);
      expect(state.playbackIndex, 0);
      // 重建失败仍保留声明来源：降级成 transient 会让下次重启再也没有可重建的线索。
      expect(state.queueSource.kind, MusicQueueSourceKind.playlist);
    },
  );

  test(
    'startup locates the current key across sequential library pages',
    () async {
      final api = _FakeMusicApi();
      for (var index = 0; index < 150; index++) {
        api.libraryTracks.add(
          MusicTrack(
            id: 'bulk-$index',
            fileNodeId: 'file-bulk-$index',
            title: 'Bulk $index',
            artistName: 'Bulk Artist',
            albumTitle: 'Bulk Album',
            format: 'mp3',
            favorite: false,
          ),
        );
      }
      api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
        items: <MusicPlayableItem>[
          MusicPlayableItem.local(api.libraryTracks[120]),
        ],
        currentIndex: 0,
        source: MusicQueueSource.localLibrary(),
      );
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(api),
          musicPlaybackQueueOwnerIdProvider.overrideWith(
            (ref) async => 'user-a',
          ),
        ],
      );
      addTearDown(container.dispose);

      final firstFrame = await container.read(
        musicCenterControllerProvider.future,
      );
      // 当前曲在首页之外：首帧只带窗口快照，不去串行取满 20 页。
      expect(firstFrame.playbackItems, hasLength(1));
      expect(firstFrame.queueSource.isPureLocalLibrary, isTrue);

      await pumpEventQueue();
      final state = container.read(musicCenterControllerProvider).value!;

      // fake 构造器自带 track-1/track-2，曲库共 152 首：页 0 = track-1、track-2、bulk-0..97。
      expect(state.playbackItems, hasLength(152));
      expect(state.playbackIndex, 120);
      expect(state.currentItem?.playableKey, 'local:bulk-118');
      expect(state.queueSource.isPureLocalLibrary, isTrue);
      expect(state.tracks, hasLength(152));
      expect(state.hasMoreTracks, isFalse);
    },
  );

  test('snapshot without source stays transient', () async {
    final api = _FakeMusicApi();
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[MusicPlayableItem.local(api.track)],
      currentIndex: 0,
    );
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(musicCenterControllerProvider.future);

    expect(state.queueSource.kind, MusicQueueSourceKind.transient);
    expect(state.playbackItems, hasLength(1));
  });
}

void registerMusicQueuePersistenceTests() {
  test('server timestamp echoes back into the local snapshot', () async {
    final api = _FakeMusicApi();
    final store = _MemoryMusicPlaybackQueueStore();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueStoreProvider.overrideWithValue(store),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playTrack(api.track);
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(api.savedPlaybackQueues, hasLength(1));
    final stored = store.snapshots['user-a'];
    expect(stored, isNotNull);
    // 落盘的是服务端回显时间戳，而非客户端时钟。
    expect(stored!.updatedAt, api.queueSaveServerTime);
    expect(stored.items.first.playableKey, 'local:track-1');
  });

  test('unsynced local snapshot wins regardless of remote timestamp', () async {
    final api = _FakeMusicApi();
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[MusicPlayableItem.local(api.track)],
      currentIndex: 0,
      updatedAt: DateTime.utc(2026, 9, 20, 12),
    );
    // 离线清空场景：本地空队列且无时间戳（未同步脏标志）。
    final store =
        _MemoryMusicPlaybackQueueStore()
          ..snapshots['user-a'] = const MusicPlaybackQueueSnapshot();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueStoreProvider.overrideWithValue(store),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(musicCenterControllerProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // 本地含未同步变更（清空）判胜，远端不复活已清空队列。
    expect(state.playbackItems, isEmpty);
    expect(api.savedPlaybackQueues, isNotEmpty);
    expect(api.savedPlaybackQueues.last.items, isEmpty);
  });

  test(
    'later pending snapshot is not overwritten by an in-flight echo',
    () async {
      final api = _FakeMusicApi();
      final store = _MemoryMusicPlaybackQueueStore();
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(api),
          musicPlaybackQueueStoreProvider.overrideWithValue(store),
          musicPlaybackQueueOwnerIdProvider.overrideWith(
            (ref) async => 'user-a',
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);
      final controller = container.read(musicCenterControllerProvider.notifier);

      api.queueSaveGate = Completer<void>();
      controller.enqueue(MusicPlayableItem.local(api.secondTrack));
      await Future<void>.delayed(const Duration(milliseconds: 220));
      controller.enqueue(MusicPlayableItem.local(api.thirdTrack));
      api.queueSaveGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(api.savedPlaybackQueues, hasLength(2));
      final stored = store.snapshots['user-a'];
      expect(stored, isNotNull);
      // 落盘的是后保存快照（identical 守卫生效，未回退到 in-flight 的旧回程）。
      expect(stored!.items.map((item) => item.playableKey).toList(), [
        'local:track-3',
        'local:track-2',
      ]);
      expect(stored.updatedAt, api.queueSaveServerTime);
    },
  );

  test('server-filtered items are adopted on echo-back', () async {
    final api = _FakeMusicApi();
    final store = _MemoryMusicPlaybackQueueStore();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueStoreProvider.overrideWithValue(store),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    await controller.playTrack(api.track);
    const bogusKey = 'online:netease:bad key';
    controller.enqueue(
      MusicPlayableItem(
        ref: const OnlineMusicRef(
          platform: MusicPlatform.netease,
          songId: 'bad key',
        ),
        track: MusicTrack(
          id: bogusKey,
          fileNodeId: '',
          title: 'Bogus',
          artistName: 'A',
          albumTitle: 'B',
          format: 'mp3',
          favorite: false,
        ),
      ),
    );
    api.serverFilteredKeys = const {bogusKey};
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(api.savedPlaybackQueues, hasLength(1));
    expect(api.savedPlaybackQueues.single.items, hasLength(3));
    // 回显整体采用服务端规范化结果：被过滤条目从本地副本移除。
    final stored = store.snapshots['user-a'];
    expect(stored, isNotNull);
    expect(stored!.items.map((item) => item.playableKey).toList(), [
      'local:track-1',
      'local:track-2',
    ]);
  });

  test('playOnlineTrack resets the source to transient', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    // 先绑定歌单来源，再从历史页点播在线单曲：来源必须重置为 transient。
    await controller.playItems(
      _fourTrackItems(api),
      startIndex: 0,
      source: const MusicQueueSource(
        kind: MusicQueueSourceKind.playlist,
        id: 'playlist-1',
        title: 'Road Trip',
      ),
    );
    await controller.playOnlineTrack(
      const OnlineTrack(
        platform: 'netease',
        songId: '188888',
        title: 'Cloud Song',
        artistName: 'Online Artist',
      ),
    );

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'online:netease:188888');
    expect(state.playbackItems.map((item) => item.playableKey).toList(), [
      'online:netease:188888',
    ]);
    expect(state.queueSource.kind, MusicQueueSourceKind.transient);
  });

  test(
    'snapshot source and truncated flag round-trip through local store',
    () async {
      final api = _FakeMusicApi();
      final store = _MemoryMusicPlaybackQueueStore();
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(api),
          musicPlaybackQueueStoreProvider.overrideWithValue(store),
          musicPlaybackQueueOwnerIdProvider.overrideWith(
            (ref) async => 'user-a',
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);
      final items = List<MusicPlayableItem>.generate(130, (index) {
        return MusicPlayableItem.local(
          MusicTrack(
            id: 'bulk-$index',
            fileNodeId: 'file-bulk-$index',
            title: 'Track $index',
            artistName: 'Artist',
            albumTitle: 'Album',
            format: 'mp3',
            favorite: false,
          ),
        );
      });

      await container
          .read(musicCenterControllerProvider.notifier)
          .playItems(
            items,
            startIndex: 129,
            source: const MusicQueueSource(
              kind: MusicQueueSourceKind.playlist,
              id: 'playlist-1',
              title: 'Road Trip',
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 220));

      final stored = store.snapshots['user-a'];
      expect(stored, isNotNull);
      expect(stored!.truncated, isTrue);
      expect(stored.source.kind, MusicQueueSourceKind.playlist);
      expect(stored.items, hasLength(100));

      final decoded = MusicPlaybackQueueSnapshot.fromJson(stored.toCacheJson());
      expect(decoded.truncated, isTrue);
      expect(decoded.source.kind, MusicQueueSourceKind.playlist);
      expect(decoded.items, hasLength(100));
    },
  );

  test('播放在线歌单入队整表而不是首屏页', () async {
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
    await container.read(musicCenterControllerProvider.future);
    await container.read(musicPlatformLibraryProvider.future);
    await pumpEventQueue();
    final library = container.read(musicPlatformLibraryProvider).value!;
    final playlist = library.playlists.first;
    final firstScreen = await container
        .read(musicPlatformLibraryProvider.notifier)
        .loadPlaylistTracks(playlist);
    expect(firstScreen, hasLength(200));
    final startItem = MusicPlayableItem.online(firstScreen[150]);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playPlatformPlaylist(playlist, startItem: startItem);

    // 在线歌单没有可重建的队列来源，入队必须已经补齐整表。
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.playbackItems, hasLength(800));
    expect(state.currentItem?.playableKey, startItem.playableKey);
    expect(state.queueSource.kind, MusicQueueSourceKind.transient);
  });
}

List<String> _shuffledKeys(List<String> keys, Random random) {
  final copy = List<String>.of(keys);
  for (var i = copy.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final swapped = copy[i];
    copy[i] = copy[j];
    copy[j] = swapped;
  }
  return copy;
}
