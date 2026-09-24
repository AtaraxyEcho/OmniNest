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

  test('seeded shuffle round plays each remaining key exactly once', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = _fourTrackItems(api);

    controller.random = Random(7);
    await controller.playItems(items, startIndex: 0);
    controller.setPlayMode(MusicPlayMode.shuffle);

    // 控制器对"队列 key − 当前曲"做洗牌，模拟须同构。
    final expected = _shuffledKeys(const [
      'local:track-2',
      'local:track-3',
      'local:track-4',
    ], Random(7));
    for (final key in expected) {
      await controller.nextTrack();
      final state = container.read(musicCenterControllerProvider).asData!.value;
      expect(state.currentItem?.playableKey, key);
    }
  });

  test('shuffle starts a fresh seeded round after exhaustion', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.random = Random(7);
    await controller.playItems(_fourTrackItems(api), startIndex: 0);
    controller.setPlayMode(MusicPlayMode.shuffle);

    final rng = Random(7);
    const allKeys = [
      'local:track-1',
      'local:track-2',
      'local:track-3',
      'local:track-4',
    ];
    final firstRound = _shuffledKeys(allKeys.sublist(1), rng);
    for (var round = 0; round < firstRound.length; round++) {
      await controller.nextTrack();
    }
    final secondRound = _shuffledKeys(
      allKeys.where((key) => key != firstRound.last).toList(),
      rng,
    );
    await controller.nextTrack();
    final state = container.read(musicCenterControllerProvider).asData!.value;
    expect(state.currentItem?.playableKey, secondRound.first);
  });

  test('previous under shuffle returns the actually played track', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.random = Random(7);
    await controller.playItems(_fourTrackItems(api), startIndex: 0);
    controller.setPlayMode(MusicPlayMode.shuffle);
    final expected = _shuffledKeys(const [
      'local:track-2',
      'local:track-3',
      'local:track-4',
    ], Random(7));

    await controller.nextTrack();
    await controller.nextTrack();
    await controller.previousTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      expected[0],
    );
    await controller.previousTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      'local:track-1',
    );
  });

  test('previous after manual jump returns the pre-jump track', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = _fourTrackItems(api);

    await controller.playItems(items, startIndex: 0);
    await controller.playItems(items, startIndex: 2);
    await controller.previousTrack();

    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      'local:track-1',
    );
  });

  test('previous with empty history wraps at the queue head', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = _fourTrackItems(api);

    // repeat=off 下手动上一首也总是回绕：队首回到队尾。
    await controller.playItems(items, startIndex: 0);
    await controller.previousTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      'local:track-4',
    );

    await controller.previousTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      'local:track-3',
    );
  });

  test('manual next wraps at the queue end', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = _fourTrackItems(api);

    await controller.playItems(items, startIndex: 3);
    await controller.nextTrack();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.playMode, MusicPlayMode.sequential);
    expect(state.currentItem?.playableKey, 'local:track-1');
    expect(state.playbackIndex, 0);
    expect(state.isPlaying, isTrue);
  });

  test('auto advance at the queue end wraps to the queue start', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = _fourTrackItems(api);

    await controller.playItems(items, startIndex: 3);
    await controller.nextTrack(autoAdvance: true);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'local:track-1');
    expect(state.isPlaying, isTrue);
  });

  test('auto advance replays the current track under repeat one', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = _fourTrackItems(api);

    await controller.playItems(items, startIndex: 3);
    controller.setPlayMode(MusicPlayMode.repeatOne);
    await controller.nextTrack(autoAdvance: true);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentItem?.playableKey, 'local:track-4');
    expect(state.playbackIndex, 3);
    expect(state.isPlaying, isTrue);
  });

  test('manual shuffle next regenerates the round when exhausted', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.random = Random(7);
    await controller.playItems(_fourTrackItems(api), startIndex: 0);
    controller.setPlayMode(MusicPlayMode.shuffle);
    final rng = Random(7);
    final firstRound = _shuffledKeys(const [
      'local:track-2',
      'local:track-3',
      'local:track-4',
    ], rng);
    // 播完一轮（自动推进语义下 repeat=off 会停，这里手动走完）。
    for (var round = 0; round < firstRound.length; round++) {
      await controller.nextTrack();
    }
    // 轮次耗尽后再手动下一首：重生成一轮（排除当前曲）并继续播放。
    final secondRound = _shuffledKeys(
      const [
        'local:track-1',
        'local:track-2',
        'local:track-3',
        'local:track-4',
      ].where((key) => key != firstRound.last).toList(),
      rng,
    );
    await controller.nextTrack();

    final state = container.read(musicCenterControllerProvider).asData!.value;
    expect(state.currentItem?.playableKey, secondRound.first);
    expect(state.isPlaying, isTrue);
  });

  test('enqueue under shuffle becomes the next played key', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.random = Random(7);
    await controller.playItems(_fourTrackItems(api), startIndex: 0);
    controller.setPlayMode(MusicPlayMode.shuffle);
    controller.enqueue(
      MusicPlayableItem.local(
        const MusicTrack(
          id: 'track-5',
          fileNodeId: 'file-5',
          title: 'Dawn Drive',
          artistName: 'Omni Band',
          albumTitle: 'Unknown Album',
          format: 'mp3',
          favorite: false,
        ),
      ),
    );

    await controller.nextTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      'local:track-5',
    );
  });

  test('removeFromQueue purges the key from the shuffle round', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.random = Random(7);
    await controller.playItems(_fourTrackItems(api), startIndex: 0);
    controller.setPlayMode(MusicPlayMode.shuffle);
    final expected = _shuffledKeys(const [
      'local:track-2',
      'local:track-3',
      'local:track-4',
    ], Random(7));

    controller.removeFromQueue(expected[0]);
    await controller.nextTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      expected[1],
    );
  });

  test(
    'row jump keeps the shuffle round while replacement regenerates',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);
      final controller = container.read(musicCenterControllerProvider.notifier);
      final items = _fourTrackItems(api);

      controller.random = Random(7);
      await controller.playItems(items, startIndex: 0);
      controller.setPlayMode(MusicPlayMode.shuffle);
      final round = _shuffledKeys(const [
        'local:track-2',
        'local:track-3',
        'local:track-4',
      ], Random(7));

      final jumpIndex = items.indexWhere(
        (item) => item.playableKey == round[0],
      );
      await controller.playItems(items, startIndex: jumpIndex);
      await controller.nextTrack();
      expect(
        container
            .read(musicCenterControllerProvider)
            .value!
            .currentItem
            ?.playableKey,
        round[1],
      );

      // 同集合之外的整队替换：重开一轮洗牌序（延续同一随机流）。
      final extended = [
        ...items,
        MusicPlayableItem.local(
          const MusicTrack(
            id: 'track-5',
            fileNodeId: 'file-5',
            title: 'Dawn Drive',
            artistName: 'Omni Band',
            albumTitle: 'Unknown Album',
            format: 'mp3',
            favorite: false,
          ),
        ),
      ];
      final rng = Random(7);
      _shuffledKeys(const [
        'local:track-2',
        'local:track-3',
        'local:track-4',
      ], rng);
      final regenerated = _shuffledKeys(const [
        'local:track-2',
        'local:track-3',
        'local:track-4',
        'local:track-5',
      ], rng);
      await controller.playItems(extended, startIndex: 0);
      await controller.nextTrack();
      expect(
        container
            .read(musicCenterControllerProvider)
            .value!
            .currentItem
            ?.playableKey,
        regenerated.first,
      );
    },
  );

  test(
    'restored shuffle state generates order on the first next track',
    () async {
      final api = _FakeMusicApi();
      api.restoredPlaybackQueue = MusicPlaybackQueueSnapshot(
        items: <MusicPlayableItem>[
          MusicPlayableItem.local(api.track),
          MusicPlayableItem.local(api.secondTrack),
          MusicPlayableItem.local(api.thirdTrack),
        ],
        currentIndex: 0,
        shuffleEnabled: true,
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
      final controller = container.read(musicCenterControllerProvider.notifier);

      await controller.nextTrack();
      final state = container.read(musicCenterControllerProvider).asData!.value;
      expect(state.playMode, MusicPlayMode.shuffle);
      expect(state.currentItem?.playableKey, isNot('local:track-1'));
      expect(
        state.playbackItems.map((item) => item.playableKey),
        contains(state.currentItem?.playableKey),
      );

      await controller.previousTrack();
      expect(
        container
            .read(musicCenterControllerProvider)
            .value!
            .currentItem
            ?.playableKey,
        'local:track-1',
      );
    },
  );

  test('play history caps at two hundred entries', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    final items = List<MusicPlayableItem>.generate(251, (index) {
      return MusicPlayableItem.local(
        MusicTrack(
          id: 'cap-$index',
          fileNodeId: 'file-cap-$index',
          title: 'Cap $index',
          artistName: 'Omni Band',
          albumTitle: 'Cap Album',
          format: 'mp3',
          favorite: false,
        ),
      );
    });

    await controller.playItems(items, startIndex: 0);
    for (var index = 1; index < items.length; index++) {
      await controller.playItems(items, startIndex: index);
    }
    // 历史保留最近 200 条：cap-50..cap-249，更早的已丢弃。
    for (var index = 249; index >= 50; index--) {
      await controller.previousTrack();
      expect(
        container
            .read(musicCenterControllerProvider)
            .value!
            .currentItem
            ?.playableKey,
        'local:cap-$index',
      );
    }
    // 历史耗尽后线性回退到 index-1。
    await controller.previousTrack();
    expect(
      container
          .read(musicCenterControllerProvider)
          .value!
          .currentItem
          ?.playableKey,
      'local:cap-49',
    );
  });
}

MusicTrack _fillerTrack(String id) {
  return MusicTrack(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Filler $id',
    artistName: 'Omni Band',
    albumTitle: 'City Lights',
    format: 'flac',
    favorite: false,
  );
}
