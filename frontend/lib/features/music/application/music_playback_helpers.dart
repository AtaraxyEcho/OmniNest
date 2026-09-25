part of 'music_controller.dart';

/// 播放请求内部流程：入队播放、失败跳过、最近项提升与在线歌词补齐。
extension MusicPlaybackHelpers on MusicCenterController {
  Future<void> _playItemInQueue(
    MusicCenterState current,
    List<MusicPlayableItem> queue,
    int index, {
    bool pushHistory = true,
    MusicQueueSource? source,
  }) async {
    if (queue.isEmpty || index < 0 || index >= queue.length) {
      return;
    }
    final generation = ++_playRequestGeneration;
    final item = queue[index];
    _recordQueueTransitions(current, item, pushHistory: pushHistory);
    if (source != null &&
        source.isPureLocalLibrary &&
        source.identityKey != current.queueSource.identityKey) {
      // 绑定新的纯本地曲库来源：重置续页游标。
      _libraryNextPage = null;
    }
    final pendingState = current.copyWith(
      currentItem: item,
      clearPlaybackPlan: true,
      isPlaying: true,
      playbackItems: queue,
      playbackIndex: index,
      queueSource: source,
    );
    _replaceState(pendingState);
    _queuePersistence.schedule(pendingState);
    if (item.ref is OnlineMusicRef) {
      unawaited(_loadOnlineLyrics(item, generation));
    }
    MusicPlaybackPlan plan;
    try {
      plan = await _playbackResolver.resolve(item);
    } on Object catch (error) {
      if (generation != _playRequestGeneration) {
        return;
      }
      final latest = _currentState;
      if (_isUnavailableResource(error)) {
        await _skipUnavailableQueueItem(
          latest ?? pendingState,
          queue,
          index,
          item,
          error,
        );
        return;
      }
      if (latest?.currentItem?.playableKey == item.playableKey) {
        _replaceState(
          latest!.copyWith(
            isPlaying: false,
            errorMessage: describeUserFacingError(error).message,
          ),
        );
      }
      return;
    }
    if (generation != _playRequestGeneration) {
      return;
    }
    final latest = _currentState;
    if (latest == null || latest.currentItem?.playableKey != item.playableKey) {
      return;
    }
    // 解析期间队列可能已被 reorder/remove 改变，回写索引按 key 重定位而非沿用旧几何。
    final resolvedIndex = latest.playbackItems.indexWhere(
      (candidate) => candidate.playableKey == item.playableKey,
    );
    _replaceState(
      latest.copyWith(
        playbackPlan: plan,
        isPlaying: true,
        playbackIndex:
            resolvedIndex >= 0 ? resolvedIndex : latest.playbackIndex,
      ),
    );
    _promoteRecentItem(item);
    unawaited(_recordPlayableHistory(item));
    final nextIndex = index + 1;
    if (nextIndex < queue.length && queue[nextIndex].ref is OnlineMusicRef) {
      unawaited(_playbackResolver.prefetch(queue[nextIndex]));
    }
  }

  Future<void> _skipUnavailableQueueItem(
    MusicCenterState current,
    List<MusicPlayableItem> queue,
    int failedIndex,
    MusicPlayableItem failedItem,
    Object error,
  ) async {
    final remaining = <MusicPlayableItem>[
      for (final item in queue)
        if (item.playableKey != failedItem.playableKey) item,
    ];
    if (remaining.isNotEmpty) {
      final nextIndex = failedIndex.clamp(0, remaining.length - 1).toInt();
      await _playItemInQueue(
        current.copyWith(
          playbackItems: remaining,
          playbackIndex: nextIndex,
          isPlaying: false,
        ),
        remaining,
        nextIndex,
      );
      _purgeShuffleKey(failedItem.playableKey);
      return;
    }
    final fallback = _resolveLocalFallback(
      recentItems: current.recentItems,
      lastPlayed: null,
      tracks: current.tracks,
      excludedKeys: {failedItem.playableKey},
    );
    if (fallback != null && fallback.playableKey != failedItem.playableKey) {
      await _playItemInQueue(current, <MusicPlayableItem>[fallback], 0);
      _purgeShuffleKey(failedItem.playableKey);
      return;
    }
    final failedState = current.copyWith(
      playbackItems: const <MusicPlayableItem>[],
      playbackIndex: -1,
      isPlaying: false,
      errorMessage: describeUserFacingError(error).message,
    );
    _replaceState(failedState);
    _queuePersistence.schedule(failedState);
  }

  void _promoteRecentItem(MusicPlayableItem item) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final recentItems = <MusicPlayableItem>[
      item,
      ...current.recentItems.where(
        (candidate) => candidate.playableKey != item.playableKey,
      ),
    ].take(50).toList(growable: false);
    _replaceState(current.copyWith(recentItems: recentItems));
  }

  Future<void> _recordPlayableHistory(MusicPlayableItem item) async {
    try {
      await _api.recordPlayableHistory(
        playableKey: item.playableKey,
        title: item.track.title,
        artistName: item.track.artistName,
        albumTitle: item.track.albumTitle,
        coverUrl: item.track.coverUrl ?? '',
        durationSeconds: item.track.durationSeconds,
      );
    } on Object catch (error) {
      _partialErrors.add(describeUserFacingError(error).message);
    }
  }

  Future<void> _loadOnlineLyrics(MusicPlayableItem item, int generation) async {
    final ref = item.ref;
    if (ref is! OnlineMusicRef || item.track.lyricsRaw?.isNotEmpty == true) {
      return;
    }
    try {
      final result = await _api.platformTrackLyrics(
        ref.platform.apiValue,
        ref.songId,
      );
      if (result == null || generation != _playRequestGeneration) {
        return;
      }
      final current = _currentState;
      if (current?.currentItem?.playableKey != item.playableKey) {
        return;
      }
      // 原文、译文与逐字三轨保存：译文为空时行级 translation 全部为 null，
      // 逐字为空时词级 words 全部为空，渲染层退回行级显示。
      final updatedItem = item.copyWith(
        track: item.track.copyWith(
          lyricsRaw: result.lyrics,
          lyricsTranslation: result.translation,
          lyricsWords: result.words,
        ),
      );
      _replaceState(
        current!.copyWith(
          currentItem: updatedItem,
          playbackItems: current.playbackItems
              .map(
                (candidate) =>
                    candidate.playableKey == item.playableKey
                        ? updatedItem
                        : candidate,
              )
              .toList(growable: false),
        ),
      );
    } on Object catch (error) {
      _partialErrors.add(describeUserFacingError(error).message);
    }
  }

  MusicPlayableItem _itemForTrack(MusicCenterState state, MusicTrack track) {
    final currentItem = state.currentItem;
    if (currentItem?.track.id == track.id) {
      return currentItem!;
    }
    for (final item in state.playbackItems) {
      if (item.track.id == track.id) {
        return item;
      }
    }
    return MusicPlayableItem.local(track);
  }

  /// 解析曲目所在的播放队列与来源（playTrack 路径的上下文物化）。
  (List<MusicPlayableItem>, MusicQueueSource) _resolveQueueContext(
    MusicCenterState state,
    MusicPlayableItem item,
  ) {
    if (item.ref is OnlineMusicRef) {
      if (state.playbackItems.any(
        (candidate) => candidate.playableKey == item.playableKey,
      )) {
        return (state.playbackItems, state.queueSource);
      }
      return (<MusicPlayableItem>[item], MusicQueueSource.transient);
    }
    // 详情页使用对应列表与来源。
    if (state.section == MusicSection.playlistDetail &&
        state.selectedPlaylist != null &&
        state.selectedPlaylistTracks.any(
          (track) => track.id == item.track.id,
        )) {
      return (
        state.selectedPlaylistTracks.map(MusicPlayableItem.local).toList(),
        MusicQueueSource(
          kind: MusicQueueSourceKind.playlist,
          id: state.selectedPlaylist!.id,
          title: state.selectedPlaylist!.name,
        ),
      );
    }
    if (state.section == MusicSection.albumDetail &&
        state.selectedAlbum != null &&
        state.selectedAlbumTracks.any((track) => track.id == item.track.id)) {
      return (
        state.selectedAlbumTracks.map(MusicPlayableItem.local).toList(),
        MusicQueueSource(
          kind: MusicQueueSourceKind.album,
          id: state.selectedAlbum!.id,
          title: state.selectedAlbum!.title,
        ),
      );
    }
    if (state.section == MusicSection.artistDetail &&
        state.selectedArtist != null &&
        state.selectedArtistTracks.any((track) => track.id == item.track.id)) {
      return (
        state.selectedArtistTracks.map(MusicPlayableItem.local).toList(),
        MusicQueueSource(
          kind: MusicQueueSourceKind.artist,
          id: state.selectedArtist!.id,
          title: state.selectedArtist!.name,
        ),
      );
    }
    if (state.tracks.any((track) => track.id == item.track.id)) {
      return (
        state.tracks.map(MusicPlayableItem.local).toList(),
        MusicQueueSource.localLibrary(),
      );
    }
    return (<MusicPlayableItem>[item], MusicQueueSource.transient);
  }

  /// 播放在线曲目。
  Future<void> playOnlineTrack(OnlineTrack track) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final item = MusicPlayableItem.online(track);
      await _playItemInQueue(
        current,
        <MusicPlayableItem>[item],
        0,
        source: MusicQueueSource.transient,
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
    }
  }
}
