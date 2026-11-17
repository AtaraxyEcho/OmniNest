part of 'music_controller_test.dart';

/// 队列/洗牌/推进语义用例（自 music_controller_queue_test_part 拆出）。
void registerMusicQueueNavigationTests() {
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
