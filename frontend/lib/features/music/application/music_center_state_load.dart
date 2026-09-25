part of 'music_controller.dart';

/// 曲库状态装配：首帧/刷新路径的并行加载、队列水合与本地兜底解析。
extension MusicCenterStateLoad on MusicCenterController {
  Future<MusicCenterState> _loadState({
    MusicSection section = MusicSection.songs,
    MusicPlaybackView? playback,
    MusicScanJob? lastScanJob,
    bool restorePlaybackQueue = true,
    MusicPlaylist? selectedPlaylist,
    List<MusicTrack>? selectedPlaylistTracks,
    MusicAlbum? selectedAlbum,
    List<MusicTrack>? selectedAlbumTracks,
    MusicArtist? selectedArtist,
    List<MusicTrack>? selectedArtistTracks,
    int tracksPageSize = MusicCenterController.musicLibraryPageSize,
    bool includeSecondary = true,
  }) async {
    final currentItem = playback?.currentItem;
    final playbackPlan = playback?.playbackPlan;
    final isPlaying = playback?.isPlaying ?? false;
    final playbackItems =
        playback?.playbackItems ?? const <MusicPlayableItem>[];
    final playbackIndex = playback?.playbackIndex ?? -1;
    final playMode = playback?.playMode ?? MusicPlayMode.sequential;
    _partialErrors.clear();
    // 首帧只等本分区必需的请求：曲库首页、歌单、最近播放与恢复队列快照。
    // 仪表盘点、专辑/歌手全量列表与平台账号资料不参与首页渲染，
    // 交给 `_backfillSecondary` 在首帧之后补齐（`includeSecondary` 为 true 时
    // 仍按一次栅栏取齐，供手动刷新与实时事件刷新使用）。
    Future<Object?> deferred(Object? value) => Future<Object?>.value(value);
    final results = await Future.wait(<Future<Object?>>[
      includeSecondary
          ? _safe(_api.dashboard, MusicDashboard.empty())
          : deferred(MusicDashboard.empty()),
      includeSecondary
          ? _safe(
            () async => (await _api.albums(size: 200)).items,
            <MusicAlbum>[],
          )
          : deferred(const <MusicAlbum>[]),
      includeSecondary
          ? _safe(
            () async => (await _api.artists(size: 200)).items,
            <MusicArtist>[],
          )
          : deferred(const <MusicArtist>[]),
      _safe(() async {
        final page = await _api.tracks(size: tracksPageSize);
        return _LibraryTracksPage(
          items: page.items,
          totalElements: page.totalElements,
          page: page.page,
          size: page.size,
        );
      }, _LibraryTracksPage.empty()),
      _safe(_api.playlists, <MusicPlaylist>[]),
      _safe(_api.recentItems, <MusicRecentEntry>[]),
      _safe(_api.lastPlayed, null),
      _queuePersistence.load(),
      includeSecondary
          ? _safePlatformInfo()
          : deferred(const <String, PlatformUserInfo?>{}),
    ]);
    final dashboard = results[0] as MusicDashboard;
    final albums = results[1] as List<MusicAlbum>;
    final artists = results[2] as List<MusicArtist>;
    final tracksPage = results[3] as _LibraryTracksPage;
    var tracks = tracksPage.items;
    var hasMoreTracks = tracksPage.hasMore;
    final playlists = results[4] as List<MusicPlaylist>;
    final recentEntries = results[5] as List<MusicRecentEntry>;
    final lastPlayed = results[6] as MusicTrack?;
    final queueSnapshot = results[7] as MusicPlaybackQueueSnapshot;
    final platformInfo = results[8] as Map<String, PlatformUserInfo?>;
    final recentItems = _toRecentItems(recentEntries);
    var resolvedQueue = List<MusicPlayableItem>.of(playbackItems);
    var resolvedQueueIndex = playbackIndex;
    var resolvedPlayMode = playMode;
    var resolvedQueueSource =
        playback?.queueSource ?? MusicQueueSource.transient;
    if (restorePlaybackQueue && resolvedQueue.isEmpty) {
      resolvedQueue = _restorePlaybackQueue(
        queueSnapshot,
        tracks,
        libraryLoadedCompletely: !hasMoreTracks,
      );
      final restoredKey = queueSnapshot.currentItem?.playableKey;
      resolvedQueueIndex = resolvedQueue.indexWhere(
        (item) => item.playableKey == restoredKey,
      );
      if (resolvedQueueIndex < 0 && resolvedQueue.isNotEmpty) {
        resolvedQueueIndex = 0;
      }
      resolvedPlayMode = _playModeFromSnapshotFields(
        repeatMode: queueSnapshot.repeatMode,
        shuffleEnabled: queueSnapshot.shuffleEnabled,
      );
      // 来源重建最多要串行取 20 页曲库，压在首帧里会让整个模块停在加载态；
      // 首帧先用窗口快照可用，回填在帧后完成（_completePendingQueueRebuild）。
      // 来源不可重建时才降级为 transient。
      final rebuildIntent =
          queueSnapshot.source.rebuildable && restoredKey != null
              ? _QueueRebuildIntent(
                source: queueSnapshot.source,
                currentKey: restoredKey,
              )
              : null;
      _pendingQueueRebuild = rebuildIntent;
      resolvedQueueSource = rebuildIntent?.source ?? MusicQueueSource.transient;
    }
    final restoredCurrentItem =
        currentItem ??
        (resolvedQueueIndex >= 0 && resolvedQueueIndex < resolvedQueue.length
            ? resolvedQueue[resolvedQueueIndex]
            : null);
    var selectedItem = _refreshPlayableItem(
      restoredCurrentItem,
      recentItems: recentItems,
      lastPlayed: lastPlayed,
      tracks: tracks,
    );
    MusicPlaybackPlan? resolvedPlan = playbackPlan;
    if (resolvedPlan != null &&
        resolvedPlan.expiresAt != null &&
        DateTime.now().isAfter(resolvedPlan.expiresAt!)) {
      // 过期播放计划不保留，避免 UI 走"重新解析"自触发循环。
      resolvedPlan = null;
    }
    if (resolvedPlan == null && selectedItem != null) {
      try {
        resolvedPlan = await _playbackResolver.resolve(selectedItem);
      } on Object catch (error) {
        final unavailable = _isUnavailableResource(error);
        if (unavailable) {
          final failedKey = selectedItem.playableKey;
          resolvedQueue.removeWhere((item) => item.playableKey == failedKey);
          final fallback = _resolveLocalFallback(
            recentItems: recentItems,
            lastPlayed: lastPlayed,
            tracks: tracks,
            excludedKeys: {failedKey},
          );
          if (fallback != null) {
            selectedItem = fallback;
            resolvedQueueIndex = resolvedQueue.indexWhere(
              (item) => item.playableKey == fallback.playableKey,
            );
            if (resolvedQueueIndex < 0) {
              resolvedQueue.insert(0, fallback);
              resolvedQueueIndex = 0;
            }
            try {
              resolvedPlan = await _playbackResolver.resolve(fallback);
            } on Object catch (fallbackError) {
              _partialErrors.add(
                describeUserFacingError(fallbackError).message,
              );
            }
          } else {
            _partialErrors.add(describeUserFacingError(error).message);
          }
        } else {
          _partialErrors.add(describeUserFacingError(error).message);
        }
      }
    }
    final resolvedPlaylist =
        selectedPlaylist == null
            ? null
            : playlists
                    .where((item) => item.id == selectedPlaylist.id)
                    .firstOrNull ??
                selectedPlaylist;
    final resolvedAlbum =
        selectedAlbum == null
            ? null
            : albums.where((item) => item.id == selectedAlbum.id).firstOrNull ??
                selectedAlbum;
    final resolvedArtist =
        selectedArtist == null
            ? null
            : artists
                    .where((item) => item.id == selectedArtist.id)
                    .firstOrNull ??
                selectedArtist;
    final trackById = <String, MusicTrack>{
      for (final track in tracks) track.id: track,
    };
    // 恢复分支的队列项来自窗口快照，这里统一按曲库投影补齐；当前曲可能落在已加载
    // 页之外（此时 selectedItem 已由 lastPlayed 等来源水合），要回写到队列位上，
    // 否则切到下一首再切回来又退回缺歌词的快照项。重建分支返回的是不可变列表，
    // 后续按失败剔除还需要可写，因此这里一律以可写副本承载。
    resolvedQueue = List<MusicPlayableItem>.of(
      _hydrateQueueFromLibrary(resolvedQueue, trackById),
    );
    final selectedKey = selectedItem?.playableKey;
    if (selectedItem != null && selectedKey != null) {
      final selectedIndex = resolvedQueue.indexWhere(
        (item) => item.playableKey == selectedKey,
      );
      if (selectedIndex >= 0) {
        resolvedQueue[selectedIndex] = selectedItem;
      }
    }
    // 保留打开中的歌单曲目，同步收藏状态并剔除已删除曲目。
    final resolvedPlaylistTracks =
        selectedPlaylistTracks == null
            ? const <MusicTrack>[]
            : [
              for (final track in selectedPlaylistTracks)
                if (trackById.containsKey(track.id)) trackById[track.id]!,
            ];
    // 详情曲目：优先沿用已拉取的全量列表（覆盖收藏态、剔除已删曲），
    // 未携带时回退客户端对已加载页的标题过滤（离线/旧路径）。
    final resolvedAlbumTracks = _resolveDetailTracks(
      selectedAlbumTracks,
      tracks,
      resolvedAlbum == null
          ? null
          : (track) => track.albumTitle == resolvedAlbum.title,
    );
    final resolvedArtistTracks = _resolveDetailTracks(
      selectedArtistTracks,
      tracks,
      resolvedArtist == null
          ? null
          : (track) => track.artistName == resolvedArtist.name,
    );
    if (_pendingQueueRebuild != null) {
      // 让首帧先落地，再在帧后补齐来源队列。
      unawaited(
        Future<void>.delayed(Duration.zero, _completePendingQueueRebuild),
      );
    }
    return MusicCenterState(
      dashboard: dashboard,
      tracks: tracks,
      albums: albums,
      artists: artists,
      playlists: playlists,
      hasMoreTracks: hasMoreTracks,
      recentItems: recentItems,
      section: section,
      currentItem: selectedItem,
      playbackPlan: resolvedPlan,
      isPlaying: isPlaying && resolvedPlan != null,
      playbackItems: List<MusicPlayableItem>.unmodifiable(resolvedQueue),
      playbackIndex: resolvedQueueIndex,
      playMode: resolvedPlayMode,
      queueSource: resolvedQueueSource,
      selectedPlaylist: resolvedPlaylist,
      selectedPlaylistTracks: resolvedPlaylistTracks,
      selectedAlbum: resolvedAlbum,
      selectedAlbumTracks: resolvedAlbumTracks,
      selectedArtist: resolvedArtist,
      selectedArtistTracks: resolvedArtistTracks,
      lastScanJob: lastScanJob,
      neteaseUserInfo: platformInfo['netease'],
      errorMessage: _partialErrors.isEmpty ? null : _partialErrors.join('；'),
    );
  }

  /// 详情曲目解析：有全量列表时按当前曲库覆盖收藏态并剔除已删曲，否则标题过滤。
  List<MusicTrack> _resolveDetailTracks(
    List<MusicTrack>? carriedTracks,
    List<MusicTrack> tracks,
    bool Function(MusicTrack track)? filter,
  ) {
    if (filter == null) {
      return const <MusicTrack>[];
    }
    if (carriedTracks != null) {
      final trackById = <String, MusicTrack>{
        for (final track in tracks) track.id: track,
      };
      return [
        for (final track in carriedTracks)
          if (trackById.containsKey(track.id)) trackById[track.id]!,
      ];
    }
    return tracks.where(filter).toList(growable: false);
  }

  /// 用曲库投影替换队列里的窗口快照项。
  ///
  /// 快照只带标题/艺人/封面等少数字段，歌词、收藏与码率都在曲目实体上；恢复的
  /// 会话若不补齐，详情页就取不到歌词（内嵌封面被快照剔除后也靠这里回填）。
  List<MusicPlayableItem> _hydrateQueueFromLibrary(
    List<MusicPlayableItem> items,
    Map<String, MusicTrack> trackById,
  ) {
    if (items.isEmpty || trackById.isEmpty) {
      return items;
    }
    var changed = false;
    final hydrated = <MusicPlayableItem>[];
    for (final item in items) {
      final ref = item.ref;
      final refreshed = ref is LocalMusicRef ? trackById[ref.trackId] : null;
      if (refreshed == null) {
        hydrated.add(item);
        continue;
      }
      changed = true;
      hydrated.add(MusicPlayableItem.local(refreshed));
    }
    return changed ? hydrated : items;
  }

  MusicPlayableItem? _refreshPlayableItem(
    MusicPlayableItem? currentItem, {
    required List<MusicPlayableItem> recentItems,
    required MusicTrack? lastPlayed,
    required List<MusicTrack> tracks,
  }) {
    if (currentItem == null) {
      if (recentItems.isNotEmpty) {
        final recentItem = recentItems.first;
        if (recentItem.ref case LocalMusicRef(:final trackId)) {
          final refreshed = _findTrack(tracks, trackId);
          return MusicPlayableItem.local(refreshed ?? recentItem.track);
        }
        return recentItem;
      }
      if (lastPlayed != null) {
        return MusicPlayableItem.local(
          _findTrack(tracks, lastPlayed.id) ?? lastPlayed,
        );
      }
      return null;
    }
    final playableRef = currentItem.ref;
    if (playableRef is OnlineMusicRef) {
      return currentItem;
    }
    final trackId = (playableRef as LocalMusicRef).trackId;
    final refreshed = _findTrack(tracks, trackId);
    if (refreshed != null) {
      return MusicPlayableItem.local(refreshed);
    }
    if (lastPlayed != null && lastPlayed.id == trackId) {
      // 恢复的当前曲常在已加载页之外（曲库按 100 条分页），lastPlayed 就是它的
      // 完整投影，缺了这一步重启后详情页取不到歌词。
      return MusicPlayableItem.local(lastPlayed);
    }
    return _resolveLocalFallback(
      recentItems: recentItems,
      lastPlayed: lastPlayed,
      tracks: tracks,
    );
  }

  /// 本地兜底候选；[excludedKeys] 用于排除刚解析失败的曲目，避免兜底选中坏曲。
  MusicPlayableItem? _resolveLocalFallback({
    required List<MusicPlayableItem> recentItems,
    required MusicTrack? lastPlayed,
    required List<MusicTrack> tracks,
    Set<String> excludedKeys = const <String>{},
  }) {
    for (final item in recentItems) {
      if (excludedKeys.contains(item.playableKey)) {
        continue;
      }
      if (item.ref case LocalMusicRef(:final trackId)) {
        return MusicPlayableItem.local(
          _findTrack(tracks, trackId) ?? item.track,
        );
      }
    }
    if (lastPlayed != null &&
        !excludedKeys.contains('local:${lastPlayed.id}')) {
      return MusicPlayableItem.local(
        _findTrack(tracks, lastPlayed.id) ?? lastPlayed,
      );
    }
    final available = tracks.where(
      (track) => !excludedKeys.contains('local:${track.id}'),
    );
    for (final track in available) {
      return MusicPlayableItem.local(track);
    }
    return null;
  }

  MusicTrack? _findTrack(List<MusicTrack> tracks, String trackId) {
    for (final track in tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  /// 判断解析失败是否属于资源确定性不可用（已删除/已下架等），可安全自动跳过；
  /// 网络瞬断类错误不匹配，会停播报错而不是移除队列条目。
  bool _isUnavailableResource(Object error) {
    final described = describeUserFacingError(error);
    final code = described.code?.trim().toUpperCase();
    if (code == '5001' || code == 'MEDIA_NOT_FOUND' || code == '404') {
      return true;
    }
    const unavailableMarkers = <String>[
      '资源不存在',
      '歌曲不存在',
      '已删除',
      '已下架',
      '所有音质均不可用',
      '播放URL为空',
      '播放URL数据缺失',
      '无法获取在线播放地址',
    ];
    return unavailableMarkers.any(described.message.contains);
  }
}

/// 曲库加载内部使用的曲目分页载体，用于区分加载失败与空结果。
class _LibraryTracksPage {
  const _LibraryTracksPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
  });

  const _LibraryTracksPage.empty()
    : items = const <MusicTrack>[],
      page = 0,
      size = MusicCenterController.musicLibraryPageSize,
      totalElements = 0;

  final List<MusicTrack> items;
  final int page;
  final int size;
  final int totalElements;

  bool get hasMore => size > 0 && (page + 1) * size < totalElements;
}
