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
    final queue = _queueFor(current, item);
    final index = queue.indexWhere(
      (candidate) => candidate.playableKey == item.playableKey,
    );
    await _playItemInQueue(current, queue, index < 0 ? 0 : index);
  }

  /// 使用统一可播放对象替换当前队列并播放指定位置。
  Future<void> playItems(
    List<MusicPlayableItem> items, {
    int startIndex = 0,
  }) async {
    final current = _currentState;
    if (current == null || items.isEmpty) {
      return;
    }
    final uniqueItems = <MusicPlayableItem>[];
    final keys = <String>{};
    for (final item in items) {
      if (keys.add(item.playableKey)) {
        uniqueItems.add(item);
      }
    }
    final safeIndex = startIndex.clamp(0, uniqueItems.length - 1).toInt();
    await _playItemInQueue(current, uniqueItems, safeIndex);
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

  /// 按循环和随机模式播放下一项。
  Future<void> nextTrack() async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final activeItem = current.activeItem;
    if (current.playbackItems.isEmpty && activeItem == null) {
      return;
    }
    final queue =
        current.playbackItems.isEmpty
            ? _queueFor(current, activeItem!)
            : current.playbackItems;
    if (queue.isEmpty) {
      return;
    }
    if (current.repeatMode == MusicRepeatMode.one &&
        current.playbackIndex >= 0) {
      await _playItemInQueue(current, queue, current.playbackIndex);
      return;
    }
    if (current.shuffleEnabled && queue.length > 1) {
      final currentIndex =
          current.playbackIndex >= 0 && current.playbackIndex < queue.length
              ? current.playbackIndex
              : queue.indexWhere(
                (item) => item.playableKey == current.currentItem?.playableKey,
              );
      final nextIndexes = [
        for (var index = 0; index < queue.length; index++)
          if (index != currentIndex) index,
      ];
      final nextIndex = nextIndexes[Random().nextInt(nextIndexes.length)];
      await _playItemInQueue(current, queue, nextIndex);
      return;
    }
    final nextIndex = current.playbackIndex + 1;
    if (nextIndex < queue.length) {
      await _playItemInQueue(current, queue, nextIndex);
      return;
    }
    if (current.repeatMode == MusicRepeatMode.all) {
      await _playItemInQueue(current, queue, 0);
      return;
    }
    _replaceState(current.copyWith(isPlaying: false));
  }

  /// 播放上一项，并在全列表循环时回到队尾。
  Future<void> previousTrack() async {
    final current = _currentState;
    if (current == null || current.playbackItems.isEmpty) {
      return;
    }
    final previousIndex = current.playbackIndex - 1;
    if (previousIndex >= 0) {
      await _playItemInQueue(current, current.playbackItems, previousIndex);
    } else if (current.repeatMode == MusicRepeatMode.all) {
      await _playItemInQueue(
        current,
        current.playbackItems,
        current.playbackItems.length - 1,
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

  /// 切换随机播放状态。
  void toggleShuffle() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final nextState = current.copyWith(shuffleEnabled: !current.shuffleEnabled);
    _replaceState(nextState);
    _queuePersistence.schedule(nextState);
  }
}
