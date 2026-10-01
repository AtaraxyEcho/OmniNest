part of 'music_controller_test.dart';

void registerMusicQueueTests() {
  test('startup restores the previous mixed playback queue', () async {
    final api = _FakeMusicApi();
    final online = MusicPlayableItem.online(
      const OnlineTrack(
        platform: 'netease',
        songId: '188888',
        title: 'Cloud Song',
        artistName: 'Online Artist',
      ),
    );
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: [MusicPlayableItem.local(api.track), online],
      currentIndex: 1,
      repeatMode: 'all',
      shuffleEnabled: true,
    );
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(musicCenterControllerProvider.future);

    expect(state.playbackItems.map((item) => item.playableKey), [
      'local:track-1',
      'online:netease:188888',
    ]);
    expect(state.playbackIndex, 1);
    expect(state.currentItem?.playableKey, 'online:netease:188888');
    expect(state.playMode, MusicPlayMode.shuffle);
    expect(api.onlinePlaybackRequests, ['netease:188888']);
  });

  test('恢复的本地队列项按曲库投影补齐歌词与封面', () async {
    final api = _FakeMusicApi();
    final full = MusicTrack(
      id: 'track-9',
      fileNodeId: 'file-9',
      title: 'Deep Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
      lyricsRaw: '[00:01.00]Rolling',
      coverUrl: '/api/v1/music/covers/cover-9',
    );
    api.libraryTracks.add(full);
    // 快照窗口项只带标题等少数字段，与重启后从本地缓存读回的形状一致。
    final snapshotItem = MusicPlayableItem.fromQueueJson(
      MusicPlayableItem.local(full).toQueueJson(),
    );
    expect(snapshotItem.track.lyricsRaw, isNull);
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[snapshotItem],
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

    expect(state.currentItem?.track.lyricsRaw, '[00:01.00]Rolling');
    expect(state.playbackItems.single.track.lyricsRaw, '[00:01.00]Rolling');
    expect(
      state.playbackItems.single.track.coverUrl,
      '/api/v1/music/covers/cover-9',
    );
  });

  test('当前曲在已加载页之外时用最近播放投影补齐歌词', () async {
    final api = _FakeMusicApi();
    // 曲库超过一页：分页仍有剩余时"首页找不到"不等于"曲目已删除"。
    for (var index = 0; index < 120; index++) {
      api.libraryTracks.add(_fillerTrack('filler-$index'));
    }
    final full = MusicTrack(
      id: 'track-outside-page',
      fileNodeId: 'file-outside-page',
      title: 'Deep Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
      lyricsRaw: '[00:02.00]Far',
    );
    // 该曲不在曲库首页里，只有 last-played 接口带得出歌词。
    api.lastPlayedTrack = full;
    final snapshotItem = MusicPlayableItem.fromQueueJson(
      MusicPlayableItem.local(full).toQueueJson(),
    );
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[snapshotItem],
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

    // 未被首页命中也必须保留：否则每次重启都会丢掉首页之后的整段队列。
    expect(state.playbackItems, hasLength(1));
    expect(state.currentItem?.playableKey, 'local:track-outside-page');
    expect(state.currentItem?.track.lyricsRaw, '[00:02.00]Far');
    // 水合后的当前曲要回写队列位，否则再次切回该曲又退回缺歌词的快照项。
    expect(state.playbackItems.single.track.lyricsRaw, '[00:02.00]Far');
  });

  test('列表摘要投影缺歌词时起播补拉单曲详情', () async {
    final api = _FakeMusicApi();
    final summary = MusicTrack(
      id: 'track-lyric',
      fileNodeId: 'file-lyric',
      title: 'Summary Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    final full = summary.copyWith(lyricsRaw: '[00:03.00]Detail');
    api.libraryTracks
      ..clear()
      ..add(summary);
    api.trackDetailOverrides['track-lyric'] = full;
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playTrack(summary);
    await Future<void>.delayed(Duration.zero);

    expect(api.trackDetailRequests, ['track-lyric']);
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.track.lyricsRaw, '[00:03.00]Detail');
    expect(state.playbackItems.single.track.lyricsRaw, '[00:03.00]Detail');
  });

  test('列表摘要投影缺歌词时恢复后补拉单曲详情', () async {
    final api = _FakeMusicApi();
    final summary = MusicTrack(
      id: 'track-restore-lyric',
      fileNodeId: 'file-restore-lyric',
      title: 'Restored Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    api.libraryTracks
      ..clear()
      ..add(summary);
    api.trackDetailOverrides['track-restore-lyric'] = summary.copyWith(
      lyricsRaw: '[00:04.00]Restored',
    );
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[
        MusicPlayableItem.fromQueueJson(
          MusicPlayableItem.local(summary).toQueueJson(),
        ),
      ],
      currentIndex: 0,
    );
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);

    await container.read(musicCenterControllerProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(api.trackDetailRequests, ['track-restore-lyric']);
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.track.lyricsRaw, '[00:04.00]Restored');
    expect(state.playbackItems.single.track.lyricsRaw, '[00:04.00]Restored');
  });

  test('首页命中摘要曲目时仍优先保留 lastPlayed 完整投影的歌词', () async {
    final api = _FakeMusicApi();
    final summary = MusicTrack(
      id: 'track-merge',
      fileNodeId: 'file-merge',
      title: 'Merge Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    api.libraryTracks
      ..clear()
      ..add(summary);
    api.lastPlayedTrack = summary.copyWith(lyricsRaw: '[00:05.00]Kept');
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[
        MusicPlayableItem.fromQueueJson(
          MusicPlayableItem.local(summary).toQueueJson(),
        ),
      ],
      currentIndex: 0,
    );
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(musicCenterControllerProvider.future);

    expect(state.currentItem?.track.lyricsRaw, '[00:05.00]Kept');
    expect(api.trackDetailRequests, isEmpty);
  });

  test('本地歌词补拉失败写入 errorMessage 且不阻断播放', () async {
    final api = _FakeMusicApi();
    final summary = MusicTrack(
      id: 'track-lyric-fail',
      fileNodeId: 'file-lyric-fail',
      title: 'Fail Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    api.libraryTracks
      ..clear()
      ..add(summary);
    api.trackDetailErrors['track-lyric-fail'] = Exception('detail down');
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playTrack(summary);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'local:track-lyric-fail');
    expect(state.isPlaying, isTrue);
    expect(state.currentItem?.track.lyricsRaw, isNull);
    expect(state.errorMessage, 'MUSIC_LYRICS_LOAD_FAILED');
  });

  test('在线歌词补拉失败写入 errorMessage 且不阻断播放', () async {
    final api =
        _FakeMusicApi()
          ..onlineLyricsErrors['188888'] = Exception('lyrics down');
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playOnlineTrack(
          const OnlineTrack(
            platform: 'netease',
            songId: '188888',
            title: 'Cloud Song',
            artistName: 'Online Artist',
          ),
        );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'online:netease:188888');
    expect(state.isPlaying, isTrue);
    expect(state.currentTrack?.lyricsRaw, isNull);
    expect(state.errorMessage, 'MUSIC_LYRICS_LOAD_FAILED');
    expect(state.currentItem?.lyricsLoadFailed, isTrue);
  });

  test('切歌后迟到的歌词补拉失败不串台', () async {
    final api = _FakeMusicApi();
    final first = MusicTrack(
      id: 'track-fail-target',
      fileNodeId: 'file-fail-target',
      title: 'Fail Target',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    final second = MusicTrack(
      id: 'track-keep-clean',
      fileNodeId: 'file-keep-clean',
      title: 'Keep Clean',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
      lyricsRaw: '[00:08.00]Clean',
    );
    api.libraryTracks
      ..clear()
      ..addAll([first, second]);
    final gate = Completer<void>();
    api.trackDetailGates['track-fail-target'] = gate;
    api.trackDetailErrors['track-fail-target'] = Exception('detail down');
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    await controller.playTrack(first);
    // 补拉仍在途时切到下一曲，再放行失败：旧失败不得写入 errorMessage 或标记任何曲。
    await controller.playTrack(second);
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'local:track-keep-clean');
    expect(state.currentItem?.lyricsLoadFailed, isFalse);
    expect(state.errorMessage, isNull);
    final firstItem = state.playbackItems.firstWhere(
      (item) => item.playableKey == 'local:track-fail-target',
    );
    expect(firstItem.lyricsLoadFailed, isFalse);
  });

  test('ensureTrackDetail 缺歌词时补拉并回写曲库投影', () async {
    final api = _FakeMusicApi();
    final summary = MusicTrack(
      id: 'track-ensure',
      fileNodeId: 'file-ensure',
      title: 'Ensure Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    api.libraryTracks
      ..clear()
      ..add(summary);
    api.trackDetailOverrides['track-ensure'] = summary.copyWith(
      lyricsRaw: '[00:06.00]Ensured',
    );
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final detail = await container
        .read(musicCenterControllerProvider.notifier)
        .ensureTrackDetail('track-ensure');

    expect(api.trackDetailRequests, ['track-ensure']);
    expect(detail?.lyricsRaw, '[00:06.00]Ensured');
    final state = container.read(musicCenterControllerProvider).value!;
    expect(
      state.tracks.singleWhere((track) => track.id == 'track-ensure').lyricsRaw,
      '[00:06.00]Ensured',
    );
  });

  test('ensureTrackDetail 已有歌词时直接返回本地投影', () async {
    final api = _FakeMusicApi();
    final full = MusicTrack(
      id: 'track-ensure-kept',
      fileNodeId: 'file-ensure-kept',
      title: 'Kept Cut',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
      lyricsRaw: '[00:07.00]Kept',
    );
    api.libraryTracks
      ..clear()
      ..add(full);
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final detail = await container
        .read(musicCenterControllerProvider.notifier)
        .ensureTrackDetail('track-ensure-kept');

    expect(api.trackDetailRequests, isEmpty);
    expect(detail?.lyricsRaw, '[00:07.00]Kept');
  });

  test('ensureTrackDetail 失败时写入 errorMessage 并返回已知摘要', () async {
    final api = _FakeMusicApi();
    final summary = MusicTrack(
      id: 'track-ensure-fail',
      fileNodeId: 'file-ensure-fail',
      title: 'Ensure Fail',
      artistName: 'Omni Band',
      albumTitle: 'City Lights',
      format: 'flac',
      favorite: false,
    );
    api.libraryTracks
      ..clear()
      ..add(summary);
    api.trackDetailErrors['track-ensure-fail'] = Exception('detail down');
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        userCapabilitiesProvider.overrideWithValue(_activityCapable),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final detail = await container
        .read(musicCenterControllerProvider.notifier)
        .ensureTrackDetail('track-ensure-fail');

    expect(detail?.id, 'track-ensure-fail');
    expect(detail?.lyricsRaw, isNull);
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.errorMessage, isNotNull);
  });

  test('曲库已完整加载时才把找不到的本地曲按已删除剪掉', () async {
    final api = _FakeMusicApi();
    api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[
        MusicPlayableItem.local(api.track),
        MusicPlayableItem.fromQueueJson(
          MusicPlayableItem.local(_fillerTrack('gone')).toQueueJson(),
        ),
      ],
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

    expect(state.playbackItems.map((item) => item.playableKey), <String>[
      'local:track-1',
    ]);
  });

  test(
    'startup prefers a newer local queue and synchronizes it remotely',
    () async {
      final api = _FakeMusicApi();
      api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
        items: <MusicPlayableItem>[MusicPlayableItem.local(api.track)],
        currentIndex: 0,
        updatedAt: DateTime.utc(2026, 7, 13, 10),
      );
      final store =
          _MemoryMusicPlaybackQueueStore()
            ..snapshots['user-a'] = MusicPlaybackQueueSnapshot(
              items: <MusicPlayableItem>[
                MusicPlayableItem.local(api.secondTrack),
              ],
              currentIndex: 0,
              updatedAt: DateTime.utc(2026, 7, 13, 11),
            );
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

      final state = await container.read(musicCenterControllerProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(state.currentItem?.playableKey, 'local:track-2');
      expect(api.savedPlaybackQueues, hasLength(1));
      expect(
        api.savedPlaybackQueues.single.currentItem?.playableKey,
        'local:track-2',
      );
    },
  );

  test(
    'unauthenticated startup does not access playback queue storage',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(musicCenterControllerProvider.future);
      container
          .read(musicCenterControllerProvider.notifier)
          .enqueue(MusicPlayableItem.local(api.secondTrack));
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(api.playbackQueueLoadAttempts, 0);
      expect(api.savedPlaybackQueues, isEmpty);
    },
  );

  test('queue mutation persists a rebuildable snapshot', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    container
        .read(musicCenterControllerProvider.notifier)
        .enqueue(MusicPlayableItem.local(api.secondTrack));
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(api.savedPlaybackQueues, hasLength(1));
    expect(
      api.savedPlaybackQueues.single.items.single.playableKey,
      'local:track-2',
    );
  });

  test('reorderQueue supports moving a later item to the head', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playItems(<MusicPlayableItem>[
          MusicPlayableItem.local(api.track),
          MusicPlayableItem.local(api.secondTrack),
        ], startIndex: 0);
    container.read(musicCenterControllerProvider.notifier).reorderQueue(1, 0);
    final state = container.read(musicCenterControllerProvider).asData!.value;

    expect(state.playbackItems.map((item) => item.playableKey).toList(), [
      'local:track-2',
      'local:track-1',
    ]);
    expect(state.playbackIndex, 1);
  });

  test(
    'clearing the queue empties items, pauses and keeps current item',
    () async {
      final api = _FakeMusicApi();
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

      await container
          .read(musicCenterControllerProvider.notifier)
          .playItems(<MusicPlayableItem>[
            MusicPlayableItem.local(api.track),
            MusicPlayableItem.local(api.secondTrack),
          ], startIndex: 0);
      container.read(musicCenterControllerProvider.notifier).clearQueue();
      final state = container.read(musicCenterControllerProvider).asData!.value;

      expect(state.playbackItems, isEmpty);
      expect(state.playbackIndex, -1);
      expect(state.isPlaying, isFalse);
      expect(state.currentItem?.playableKey, 'local:track-1');
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(api.savedPlaybackQueues, isNotEmpty);
      expect(api.savedPlaybackQueues.last.items, isEmpty);
    },
  );

  test('playback queue persistence keeps at most one hundred items', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final items = List<MusicPlayableItem>.generate(130, (index) {
      return MusicPlayableItem.local(
        MusicTrack(
          id: 'bulk-$index',
          fileNodeId: 'file-$index',
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
        .playItems(items, startIndex: 129);
    await Future<void>.delayed(const Duration(milliseconds: 220));

    final saved = api.savedPlaybackQueues.single;
    expect(saved.items, hasLength(100));
    expect(saved.currentIndex, 99);
    expect(saved.currentItem?.playableKey, 'local:bulk-129');
  });

  test('playback queue retries transient remote save failures', () async {
    final api = _FakeMusicApi()..queueSaveFailuresRemaining = 2;
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    container
        .read(musicCenterControllerProvider.notifier)
        .enqueue(MusicPlayableItem.local(api.secondTrack));
    await Future<void>.delayed(const Duration(milliseconds: 760));

    expect(api.queueSaveAttempts, 3);
    expect(api.savedPlaybackQueues, hasLength(1));
  });

  test('disposing music center flushes the latest queue immediately', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
      ],
    );
    await container.read(musicCenterControllerProvider.future);

    container
        .read(musicCenterControllerProvider.notifier)
        .enqueue(MusicPlayableItem.local(api.secondTrack));
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(api.savedPlaybackQueues, hasLength(1));
  });

  test('reorder during pending resolve recomputes index by key', () async {
    final api = _DelayedMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    api.delayFirstTrack = true;

    final controller = container.read(musicCenterControllerProvider.notifier);
    final pending = controller.playItems(<MusicPlayableItem>[
      MusicPlayableItem.local(api.track),
      MusicPlayableItem.local(api.secondTrack),
    ], startIndex: 0);
    controller.reorderQueue(1, 0);
    api.releaseFirstTrack();
    await pending;

    final state = container.read(musicCenterControllerProvider).asData!.value;
    expect(state.playbackItems.map((item) => item.playableKey).toList(), [
      'local:track-2',
      'local:track-1',
    ]);
    expect(state.playbackIndex, 1);
  });

  test(
    'removing current track during resolve keeps the recomputed index',
    () async {
      final api = _DelayedMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);
      api.delayFirstTrack = true;

      final controller = container.read(musicCenterControllerProvider.notifier);
      final pending = controller.playItems(<MusicPlayableItem>[
        MusicPlayableItem.local(api.track),
        MusicPlayableItem.local(api.secondTrack),
      ], startIndex: 0);
      controller.removeFromQueue('local:track-1');
      api.releaseFirstTrack();
      await pending;

      final state = container.read(musicCenterControllerProvider).asData!.value;
      expect(state.playbackItems.map((item) => item.playableKey), [
        'local:track-2',
      ]);
      expect(state.playbackIndex, -1);
    },
  );

  test('local unavailable track auto-skips to the next queue item', () async {
    final api =
        _FakeMusicApi()
          ..playbackPlanErrors['track-1'] = const AppException(
            code: '5001',
            message: '媒体资源不存在',
          );
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playItems(<MusicPlayableItem>[
          MusicPlayableItem.local(api.track),
          MusicPlayableItem.local(api.secondTrack),
        ], startIndex: 0);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'local:track-2');
    expect(state.playbackItems.map((item) => item.playableKey), [
      'local:track-2',
    ]);
    expect(state.playbackIndex, 0);
    expect(state.isPlaying, isTrue);
    expect(api.playbackPlanTrackIds, ['track-1', 'track-2']);
  });

  test(
    'transient local failure stops playback without mutating the queue',
    () async {
      final api =
          _FakeMusicApi()
            ..playbackPlanErrors['track-1'] = const AppException(
              code: 'REQUEST_TIMEOUT',
              message: '请求超时，请稍后重试',
            );
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      await container
          .read(musicCenterControllerProvider.notifier)
          .playItems(<MusicPlayableItem>[
            MusicPlayableItem.local(api.track),
            MusicPlayableItem.local(api.secondTrack),
          ], startIndex: 0);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(state.currentItem?.playableKey, 'local:track-1');
      expect(state.playbackItems, hasLength(2));
      expect(state.isPlaying, isFalse);
      expect(state.errorMessage, contains('REQUEST_TIMEOUT'));
    },
  );

  test(
    'playItems resolves the start index against the original list before dedupe',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      // 原始列表第 1 位是重复曲目：旧实现先去重再取模会跳到第 2 首。
      await container
          .read(musicCenterControllerProvider.notifier)
          .playItems(<MusicPlayableItem>[
            MusicPlayableItem.local(api.track),
            MusicPlayableItem.local(api.track),
            MusicPlayableItem.local(api.secondTrack),
          ], startIndex: 1);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(state.currentItem?.playableKey, 'local:track-1');
      expect(state.playbackItems.map((item) => item.playableKey).toList(), [
        'local:track-1',
        'local:track-2',
      ]);
      expect(state.playbackIndex, 0);
    },
  );
}
