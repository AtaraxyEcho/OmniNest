part of 'music_controller.dart';

/// 管理音乐播放队列和播放导航命令。
extension MusicPlaybackQueueCommands on MusicCenterController {
  /// 选择并播放本地曲目。
  Future<void> selectTrack(MusicTrack track) async {
    await playTrack(track);
  }

  /// 播放本地曲目并解析对应队列位置。
  Future<void> playTrack(MusicTrack track) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final item = _itemForTrack(current, track);
    // 目标已在当前队列内：按队列内跳播处理，不重绑上下文，
    // 防止恢复队列后按播放键把"播放自"上下文覆盖成曲库。
    final inQueueIndex = current.playbackItems.indexWhere(
      (candidate) => candidate.playableKey == item.playableKey,
    );
    if (inQueueIndex >= 0) {
      await _playItemInQueue(current, current.playbackItems, inQueueIndex);
      return;
    }
    final (queue, source) = _resolveQueueContext(current, item);
    final index = queue.indexWhere(
      (candidate) => candidate.playableKey == item.playableKey,
    );
    await _playItemInQueue(
      current,
      queue,
      index < 0 ? 0 : index,
      source: source,
    );
  }

  /// 播放当前队列中的指定位置：不改变队列与来源，仅切换当前曲并入历史。
  Future<void> playQueueIndex(int index) async {
    final current = _currentState;
    if (current == null || index < 0 || index >= current.playbackItems.length) {
      return;
    }
    await _playItemInQueue(current, current.playbackItems, index);
  }

  /// 使用统一可播放对象替换当前队列并播放指定位置。
  ///
  /// [startIndex] 以调用方传入的原始列表为准取目标曲目，再按 key 在去重后的
  /// 队列中定位，避免重复曲目导致起始位偏移。[source] 显式声明队列来源。
  Future<void> playItems(
    List<MusicPlayableItem> items, {
    int startIndex = 0,
    MusicQueueSource source = MusicQueueSource.transient,
  }) async {
    final current = _currentState;
    if (current == null || items.isEmpty) {
      return;
    }
    final startKey =
        items[startIndex.clamp(0, items.length - 1).toInt()].playableKey;
    final uniqueItems = <MusicPlayableItem>[];
    final keys = <String>{};
    for (final item in items) {
      if (keys.add(item.playableKey)) {
        uniqueItems.add(item);
      }
    }
    final targetIndex = uniqueItems.indexWhere(
      (candidate) => candidate.playableKey == startKey,
    );
    final resolvedTarget = targetIndex < 0 ? 0 : targetIndex;
    if (current.shuffleEnabled &&
        (!_samePlayableKeySet(current.playbackItems, uniqueItems) ||
            current.queueSource.identityKey != source.identityKey)) {
      // 整队替换且 key 集合或来源变化：按新队列重开一轮洗牌序。
      _startShuffleRound(uniqueItems, uniqueItems[resolvedTarget].playableKey);
    }
    await _playItemInQueue(
      current,
      uniqueItems,
      resolvedTarget,
      source: source,
    );
  }

  /// 将可播放对象插入当前曲目之后（下一首播放），已存在时不重复添加。
  void enqueue(MusicPlayableItem item) {
    final current = _currentState;
    if (current == null ||
        current.playbackItems.any(
          (candidate) => candidate.playableKey == item.playableKey,
        )) {
      return;
    }
    final items = [...current.playbackItems];
    final insertAt = (current.playbackIndex + 1).clamp(0, items.length);
    items.insert(insertAt, item);
    if (current.shuffleEnabled) {
      // 下一首播放语义：洗牌序队头同步插入。
      _shuffleUpcoming.insert(0, item.playableKey);
    }
    final next = current.copyWith(playbackItems: items);
    _replaceState(next);
    _queuePersistence.schedule(next);
  }

  /// 从当前队列移除指定对象，但不停止正在播放的音频。
  void removeFromQueue(String playableKey) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final next =
        current.playbackItems
            .where((item) => item.playableKey != playableKey)
            .toList();
    final nextIndex = next.indexWhere(
      (item) => item.playableKey == current.currentItem?.playableKey,
    );
    final nextState = current.copyWith(
      playbackItems: next,
      playbackIndex: nextIndex,
    );
    _purgeShuffleKey(playableKey);
    _replaceState(nextState);
    _queuePersistence.schedule(nextState);
  }

  /// 清空播放队列并停止播放，当前曲目仅保留展示。
  void clearQueue() {
    final current = _currentState;
    if (current == null || current.playbackItems.isEmpty) {
      return;
    }
    final nextState = current.copyWith(
      playbackItems: const <MusicPlayableItem>[],
      playbackIndex: -1,
      isPlaying: false,
    );
    _shuffleUpcoming.clear();
    _playHistory.clear();
    _shuffleRoundConsumed = true;
    _replaceState(nextState);
    _queuePersistence.schedule(nextState);
  }

  /// 调整统一播放队列顺序。
  void reorderQueue(int oldIndex, int newIndex) {
    final current = _currentState;
    if (current == null ||
        oldIndex < 0 ||
        oldIndex >= current.playbackItems.length ||
        newIndex < 0 ||
        newIndex > current.playbackItems.length) {
      return;
    }
    final next = List<MusicPlayableItem>.of(current.playbackItems);
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = next.removeAt(oldIndex);
    next.insert(adjustedIndex, item);
    final activeIndex = next.indexWhere(
      (candidate) => candidate.playableKey == current.currentItem?.playableKey,
    );
    final nextState = current.copyWith(
      playbackItems: next,
      playbackIndex: activeIndex,
    );
    _replaceState(nextState);
    _queuePersistence.schedule(nextState);
  }

  /// 播放当前选中的曲目。
  Future<void> playActiveTrack() async {
    final track = _currentState?.activeTrack;
    if (track == null) {
      return;
    }
    await playTrack(track);
  }

  /// 设置播放状态，缺少播放计划时先解析当前曲目。
  Future<void> setPlaying(bool playing) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    if (current.playbackPlan == null && playing) {
      await playActiveTrack();
      return;
    }
    _replaceState(current.copyWith(isPlaying: playing));
  }

  /// 切换播放和暂停状态。
  Future<void> togglePlayback() async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    await setPlaying(!current.isPlaying);
  }

  /// 按循环和随机模式播放下一项；清空后的队列不会复活。
  Future<void> nextTrack() async {
    final current = _currentState;
    if (current == null || current.playbackItems.isEmpty) {
      return;
    }
    final queue = current.playbackItems;
    if (current.repeatMode == MusicRepeatMode.one &&
        current.playbackIndex >= 0) {
      await _playItemInQueue(current, queue, current.playbackIndex);
      return;
    }
    if (current.shuffleEnabled && queue.length > 1) {
      if (await _nextShuffledTrack(current, queue)) {
        return;
      }
      // 洗牌序耗尽且无法重生成（repeat=off）：按停播收尾。
      _replaceState(current.copyWith(isPlaying: false));
      return;
    }
    final nextIndex = current.playbackIndex + 1;
    if (nextIndex < queue.length) {
      await _playItemInQueue(current, queue, nextIndex);
      return;
    }
    // 队列末端：纯本地曲库来源先续页（F4 优先级：有页续播，无页才回绕）。
    final extendApplicable =
        current.queueSource.isPureLocalLibrary &&
        current.hasMoreTracks &&
        !_libraryFetchingMore;
    if (extendApplicable) {
      final extended = await _extendLibraryQueueIfPossible(current);
      if (extended) {
        final latest = _currentState;
        if (latest != null && nextIndex < latest.playbackItems.length) {
          await _playItemInQueue(latest, latest.playbackItems, nextIndex);
        }
      }
      // 续页失败时 _appendLibraryPage 已停播并报错，不能用旧状态覆盖。
      return;
    }
    if (current.repeatMode == MusicRepeatMode.all) {
      await _playItemInQueue(current, queue, 0);
      return;
    }
    _replaceState(current.copyWith(isPlaying: false));
  }

  /// 洗牌推进：消费未播洗牌序；repeat=all 时先尝试续页再重生成一轮。
  Future<bool> _nextShuffledTrack(
    MusicCenterState current,
    List<MusicPlayableItem> queue,
  ) async {
    if (_shuffleUpcoming.isEmpty && !_shuffleRoundConsumed) {
      // 尚未开轮（如恢复场景）：按需生成。
      _startShuffleRound(queue, current.currentItem?.playableKey);
    }
    if (await _consumeShuffleUpcoming(current, queue)) {
      return true;
    }
    if (current.repeatMode == MusicRepeatMode.all) {
      if (await _extendLibraryQueueIfPossible(current)) {
        final latest = _currentState;
        if (latest != null) {
          _startShuffleRound(
            latest.playbackItems,
            latest.currentItem?.playableKey,
          );
          return _consumeShuffleUpcoming(latest, latest.playbackItems);
        }
      }
      _startShuffleRound(queue, current.currentItem?.playableKey);
      return _consumeShuffleUpcoming(current, queue);
    }
    return false;
  }

  /// 依次消费洗牌序，跳过已不在队列中的 key；耗尽即标记本轮结束。
  Future<bool> _consumeShuffleUpcoming(
    MusicCenterState current,
    List<MusicPlayableItem> queue,
  ) async {
    while (_shuffleUpcoming.isNotEmpty) {
      final key = _shuffleUpcoming.removeAt(0);
      final index = queue.indexWhere((item) => item.playableKey == key);
      if (index < 0) {
        continue;
      }
      await _playItemInQueue(current, queue, index);
      if (_shuffleUpcoming.isEmpty) {
        _shuffleRoundConsumed = true;
      }
      return true;
    }
    _shuffleRoundConsumed = true;
    return false;
  }

  /// 以 Fisher-Yates 生成洗牌未播序（排除当前曲）并开启新一轮。
  void _startShuffleRound(List<MusicPlayableItem> queue, String? currentKey) {
    final keys = <String>[
      for (final item in queue)
        if (item.playableKey != currentKey) item.playableKey,
    ];
    for (var i = keys.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final swapped = keys[i];
      keys[i] = keys[j];
      keys[j] = swapped;
    }
    _shuffleUpcoming
      ..clear()
      ..addAll(keys);
    _shuffleRoundConsumed = false;
  }

  /// 将 key 从洗牌序与已播历史中剔除（移除/删除/跳过坏曲时调用）。
  void _purgeShuffleKey(String playableKey) {
    _shuffleUpcoming.remove(playableKey);
    _playHistory.remove(playableKey);
  }

  /// 播放切换时维护洗牌序与历史：新曲移出未播序，被替换的当前曲入历史栈。
  void _recordQueueTransitions(
    MusicCenterState current,
    MusicPlayableItem item, {
    required bool pushHistory,
  }) {
    if (_shuffleUpcoming.remove(item.playableKey) && _shuffleUpcoming.isEmpty) {
      _shuffleRoundConsumed = true;
    }
    final previousKey = current.currentItem?.playableKey;
    if (!pushHistory ||
        previousKey == null ||
        previousKey == item.playableKey) {
      return;
    }
    if (_playHistory.isNotEmpty && _playHistory.last == previousKey) {
      return;
    }
    _playHistory.add(previousKey);
    if (_playHistory.length > MusicCenterController._playHistoryLimit) {
      _playHistory.removeAt(0);
    }
  }

  bool _samePlayableKeySet(
    List<MusicPlayableItem> left,
    List<MusicPlayableItem> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    final keys = left.map((item) => item.playableKey).toSet();
    return right.every((item) => keys.contains(item.playableKey));
  }

  /// 播放上一项：优先沿已播历史回退，历史为空时按线性回退。
  Future<void> previousTrack() async {
    final current = _currentState;
    if (current == null || current.playbackItems.isEmpty) {
      return;
    }
    while (_playHistory.isNotEmpty) {
      final key = _playHistory.removeLast();
      final index = current.playbackItems.indexWhere(
        (item) => item.playableKey == key,
      );
      if (index >= 0) {
        await _playItemInQueue(
          current,
          current.playbackItems,
          index,
          pushHistory: false,
        );
        return;
      }
    }
    final previousIndex = current.playbackIndex - 1;
    if (previousIndex >= 0) {
      await _playItemInQueue(
        current,
        current.playbackItems,
        previousIndex,
        pushHistory: false,
      );
    } else if (current.repeatMode == MusicRepeatMode.all) {
      await _playItemInQueue(
        current,
        current.playbackItems,
        current.playbackItems.length - 1,
        pushHistory: false,
      );
    }
  }

  /// 轮换播放循环模式。
  void toggleRepeatMode() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final next = switch (current.repeatMode) {
      MusicRepeatMode.off => MusicRepeatMode.all,
      MusicRepeatMode.all => MusicRepeatMode.one,
      MusicRepeatMode.one => MusicRepeatMode.off,
    };
    final nextState = current.copyWith(repeatMode: next);
    _replaceState(nextState);
    _queuePersistence.schedule(nextState);
  }

  /// 切换随机播放状态；开启时按当前队列生成洗牌序，关闭时仅清空未播序。
  void toggleShuffle() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final enabled = !current.shuffleEnabled;
    final nextState = current.copyWith(shuffleEnabled: enabled);
    _replaceState(nextState);
    if (enabled) {
      _startShuffleRound(
        nextState.playbackItems,
        nextState.currentItem?.playableKey,
      );
    } else {
      _shuffleUpcoming.clear();
    }
    _queuePersistence.schedule(nextState);
  }
}
