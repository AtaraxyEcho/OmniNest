part of 'music_controller.dart';

/// library 纯本地来源的队列续页：游标推进、去重合并与失败停播。
extension MusicLibraryQueueMore on MusicCenterController {
  /// library 纯本地来源在队列末端尝试续页；成功追加后返回 true。
  Future<bool> _extendLibraryQueueIfPossible(MusicCenterState current) async {
    if (!current.queueSource.isPureLocalLibrary ||
        !current.hasMoreTracks ||
        _libraryFetchingMore) {
      return false;
    }
    return _appendLibraryPage(current);
  }

  /// 拉取曲库下一页，按 key 去重后合并进曲库与队列尾部；失败停播并报错。
  Future<bool> _appendLibraryPage(MusicCenterState current) async {
    final generation = ++_libraryFetchGeneration;
    _libraryNextPage ??=
        (current.tracks.length / MusicCenterController.musicLibraryPageSize)
            .ceil();
    final page = _libraryNextPage!;
    _libraryFetchingMore = true;
    _replaceState(current.copyWith(tracksLoadingMore: true));
    try {
      final result = await _api.tracks(
        page: page,
        size: MusicCenterController.musicLibraryPageSize,
      );
      if (_controllerDisposed || generation != _libraryFetchGeneration) {
        return false;
      }
      final latest = _currentState;
      if (latest == null) {
        return false;
      }
      // 游标按已请求页数推进，与去重结果无关，避免空页导致重复取同一页。
      _libraryNextPage = page + 1;
      final knownTrackIds = latest.tracks.map((track) => track.id).toSet();
      final knownKeys =
          latest.playbackItems.map((item) => item.playableKey).toSet();
      final freshTracks = <MusicTrack>[];
      final freshItems = <MusicPlayableItem>[];
      for (final track in result.items) {
        if (knownTrackIds.add(track.id)) {
          freshTracks.add(track);
        }
        if (knownKeys.add('local:${track.id}')) {
          freshItems.add(MusicPlayableItem.local(track));
        }
      }
      final mergedTracks = List<MusicTrack>.of(latest.tracks)
        ..addAll(freshTracks);
      final mergedQueue = List<MusicPlayableItem>.of(
        _hydrateQueueFromLibrary(latest.playbackItems, {
          for (final track in freshTracks) track.id: track,
        }),
      )..addAll(freshItems);
      _replaceState(
        latest.copyWith(
          tracks: List<MusicTrack>.unmodifiable(mergedTracks),
          playbackItems: List<MusicPlayableItem>.unmodifiable(mergedQueue),
          hasMoreTracks: result.hasMore,
          tracksLoadingMore: false,
        ),
      );
      return true;
    } on Exception catch (error) {
      if (_controllerDisposed || generation != _libraryFetchGeneration) {
        return false;
      }
      final latest = _currentState;
      if (latest != null) {
        _replaceState(
          latest.copyWith(
            tracksLoadingMore: false,
            isPlaying: false,
            errorMessage: describeUserFacingError(error).message,
          ),
        );
      }
      return false;
    } finally {
      if (generation == _libraryFetchGeneration) {
        _libraryFetchingMore = false;
      }
    }
  }
}
