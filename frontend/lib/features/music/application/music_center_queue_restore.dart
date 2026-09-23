part of 'music_controller.dart';

/// 恢复播放队列时按快照来源重建全量队列的读路径。
///
/// 与 `music_playback_queue_commands.dart` 的播放命令相对：这里只负责
/// 「把持久化的窗口快照还原成可继续播放的完整队列」，重建失败一律返回 null，
/// 由调用方降级为窗口快照。
extension MusicCenterQueueRestore on MusicCenterController {
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
