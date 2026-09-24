part of 'music_controller.dart';

/// 恢复播放队列时按快照来源重建全量队列的读路径。
///
/// 与 `music_playback_queue_commands.dart` 的播放命令相对：这里只负责
/// 「把持久化的窗口快照还原成可继续播放的完整队列」，重建失败一律返回 null，
/// 由调用方降级为窗口快照。
extension MusicCenterQueueRestore on MusicCenterController {
  /// 在首帧之后补齐恢复队列的完整来源。
  ///
  /// 首帧只带窗口快照（最多 100 条），补齐把「播放自某歌单/曲库」的真实全量队列接回来。
  /// 回填是整队替换，期间用户换了队列或曲目就丢弃结果，不能打断正在听的内容。
  Future<void> _completePendingQueueRebuild() async {
    final intent = _pendingQueueRebuild;
    _pendingQueueRebuild = null;
    if (intent == null || _controllerDisposed) {
      return;
    }
    final generation = ++_queueRebuildGeneration;
    // 等 `build()` 的返回值落地后再写状态，否则会用尚无数据的快照覆盖首帧。
    for (var attempt = 0; attempt < 5 && _currentState == null; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
    final baseline = _currentState;
    if (baseline == null ||
        _controllerDisposed ||
        generation != _queueRebuildGeneration) {
      return;
    }
    final windowLength = baseline.playbackItems.length;
    final playGeneration = _playRequestGeneration;
    final rebuilt = await _rebuildQueueFromSource(
      intent.source,
      intent.currentKey,
      baseline.tracks,
    );
    if (rebuilt == null ||
        _controllerDisposed ||
        generation != _queueRebuildGeneration) {
      return;
    }
    final latest = _currentState;
    if (latest == null ||
        latest.queueSource.identityKey != intent.source.identityKey ||
        // 播放请求或队列内容变过（插播、删除、切歌）就丢弃回填：整队替换会打断听歌。
        _playRequestGeneration != playGeneration ||
        latest.playbackItems.length != windowLength) {
      return;
    }
    if (latest.playMode == MusicPlayMode.shuffle) {
      // 洗牌序按全量队列重开一轮，与同步重建时的行为一致。
      _startShuffleRound(rebuilt.items, latest.currentItem?.playableKey);
    }
    if (rebuilt.nextPage != null) {
      _libraryNextPage = rebuilt.nextPage;
    }
    _replaceState(
      latest.copyWith(
        tracks: List<MusicTrack>.unmodifiable(rebuilt.tracks),
        hasMoreTracks: rebuilt.hasMore,
        playbackItems: List<MusicPlayableItem>.unmodifiable(rebuilt.items),
        playbackIndex: rebuilt.index,
        // 首帧可能用最近播放兜底过 currentItem，这里必须跟随重建结果纠正，
        // 否则队列指向全量而当前曲还是另一首。
        currentItem: rebuilt.items[rebuilt.index],
        queueSource: rebuilt.source,
      ),
    );
  }

  /// 按快照来源重建全量队列；来源不可重建或未命中当前曲时返回 null（降级窗口快照）。
  Future<_QueueSourceRebuild?> _rebuildQueueFromSource(
    MusicQueueSource source,
    String currentKey,
    List<MusicTrack> loadedTracks,
  ) async {
    try {
      switch (source.kind) {
        case MusicQueueSourceKind.playlist:
        case MusicQueueSourceKind.album:
        case MusicQueueSourceKind.artist:
          final tracks = await _fetchSourceTracks(source);
          if (tracks == null) {
            return null;
          }
          return _rebuildFromTrackList(tracks, source, currentKey);
        case MusicQueueSourceKind.library:
          if (source.isPureLocalLibrary) {
            return await _rebuildLibraryQueue(currentKey);
          }
          final likedItems = <MusicPlayableItem>[
            for (final platform in (source.platforms ?? const <String>[]).where(
              (item) => item != 'local',
            ))
              ...(_platformLibrarySnapshot.likedTracksByPlatform[platform] ??
                      const <OnlineTrack>[])
                  .map(MusicPlayableItem.online),
          ];
          if (likedItems.isEmpty) {
            return null;
          }
          final mergedItems = <MusicPlayableItem>[
            ...loadedTracks.map(MusicPlayableItem.local),
            ...likedItems,
          ];
          final index = mergedItems.indexWhere(
            (item) => item.playableKey == currentKey,
          );
          if (index < 0) {
            return null;
          }
          return _QueueSourceRebuild(
            items: mergedItems,
            index: index,
            source: source,
            tracks: loadedTracks,
            hasMore: false,
          );
        case MusicQueueSourceKind.transient:
          return null;
      }
    } on Exception {
      return null;
    }
  }

  Future<List<MusicTrack>?> _fetchSourceTracks(MusicQueueSource source) async {
    final id = source.id;
    if (id == null) {
      return null;
    }
    return switch (source.kind) {
      MusicQueueSourceKind.playlist => _api.playlistTracks(id),
      MusicQueueSourceKind.album => _api.albumTracks(id),
      MusicQueueSourceKind.artist => _api.artistTracks(id),
      _ => null,
    };
  }

  _QueueSourceRebuild? _rebuildFromTrackList(
    List<MusicTrack> tracks,
    MusicQueueSource source,
    String currentKey,
  ) {
    if (tracks.isEmpty) {
      return null;
    }
    final items = tracks.map(MusicPlayableItem.local).toList();
    final index = items.indexWhere((item) => item.playableKey == currentKey);
    if (index < 0) {
      return null;
    }
    return _QueueSourceRebuild(
      items: items,
      index: index,
      source: source,
      tracks: tracks,
      hasMore: false,
    );
  }

  /// 顺序取页重建纯本地曲库队列，直到命中当前曲或曲库取尽。
  Future<_QueueSourceRebuild?> _rebuildLibraryQueue(String currentKey) async {
    final items = <MusicPlayableItem>[];
    final tracks = <MusicTrack>[];
    final seenKeys = <String>{};
    var hasMore = false;
    int? hitIndex;
    for (var page = 0; page < _libraryPageLimit; page++) {
      final result = await _api.tracks(
        page: page,
        size: MusicCenterController.musicLibraryPageSize,
      );
      hasMore = result.hasMore;
      for (final track in result.items) {
        if (seenKeys.add('local:${track.id}')) {
          tracks.add(track);
          items.add(MusicPlayableItem.local(track));
          if (hitIndex == null && 'local:${track.id}' == currentKey) {
            hitIndex = items.length - 1;
          }
        }
      }
      if (hitIndex != null || !hasMore) {
        break;
      }
    }
    if (hitIndex == null) {
      return null;
    }
    return _QueueSourceRebuild(
      items: items,
      index: hitIndex,
      source: MusicQueueSource.localLibrary(),
      tracks: tracks,
      hasMore: hasMore,
      nextPage:
          hasMore
              ? (tracks.length / MusicCenterController.musicLibraryPageSize)
                  .ceil()
              : null,
    );
  }
}

/// 首帧之后待补齐的队列来源意图。
class _QueueRebuildIntent {
  const _QueueRebuildIntent({required this.source, required this.currentKey});

  final MusicQueueSource source;
  final String currentKey;
}

/// 按来源重建队列的结果载体。
class _QueueSourceRebuild {
  const _QueueSourceRebuild({
    required this.items,
    required this.index,
    required this.source,
    required this.tracks,
    required this.hasMore,
    this.nextPage,
  });

  final List<MusicPlayableItem> items;
  final int index;
  final MusicQueueSource source;
  final List<MusicTrack> tracks;
  final bool hasMore;

  /// library 重建后的续页游标（仍有更多页时非空）。
  final int? nextPage;
}

/// 纯本地曲库重建的最大取页数。
const int _libraryPageLimit = 20;
