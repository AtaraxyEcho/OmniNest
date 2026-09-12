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
    expect(state.repeatMode, MusicRepeatMode.all);
    expect(state.shuffleEnabled, isTrue);
    expect(api.onlinePlaybackRequests, ['netease:188888:']);
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
}
