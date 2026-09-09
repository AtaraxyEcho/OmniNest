import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_playback_resolver.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

part 'music_center_state.dart';
part 'music_center_mapping.dart';
part 'music_library_content_commands.dart';
part 'music_library_maintenance_commands.dart';
part 'music_playback_queue_commands.dart';
part 'music_queue_persistence.dart';
part 'music_platform_account_commands.dart';
part 'music_providers.dart';

class MusicCenterController extends AsyncNotifier<MusicCenterState> {
  int _playRequestGeneration = 0;
  int _refreshGeneration = 0;
  late _MusicQueuePersistenceCoordinator _queuePersistence;
  String? _queuePersistenceErrorMessage;
  bool _controllerDisposed = false;

  MusicApi get _api => ref.read(musicApiProvider);

  MusicCenterState? get _currentState => state.asData?.value;

  void _replaceState(MusicCenterState value) {
    state = AsyncData(value);
  }

  Future<void> _refreshTaskState() async {
    if (_controllerDisposed || !ref.mounted) {
      return;
    }
    ref.invalidate(activeTaskSummaryProvider);
    await ref.read(taskListProvider.notifier).load();
  }

  late final MusicPlaybackResolver _playbackResolver = MusicPlaybackResolver(
    _api,
  );

  @override
  Future<MusicCenterState> build() async {
    _controllerDisposed = false;
    final ownerId = await ref.read(musicPlaybackQueueOwnerIdProvider.future);
    final api = ref.read(musicApiProvider);
    final queueStore = ref.read(musicPlaybackQueueStoreProvider);
    _queuePersistence = _MusicQueuePersistenceCoordinator(
      api: api,
      store: queueStore,
      ownerId: ownerId,
      onRemoteFailure: _reportQueuePersistenceFailure,
      onRemoteSuccess: _clearQueuePersistenceError,
    );
    ref.onDispose(() {
      _controllerDisposed = true;
      _queuePersistence.dispose();
    });
    final loaded = await _loadState();
    if (_queuePersistence.restoreRequiresRemoteSync) {
      _queuePersistence.schedule(loaded, delay: Duration.zero);
    }
    return loaded;
  }

  Future<void> refresh() async {
    await _refreshState(strict: false);
  }

  /// 严格刷新实时事件涉及的音乐数据并保留播放器与当前队列。
  Future<void> refreshForRealtime() async {
    await _refreshState(strict: true);
  }

  Future<void> _refreshState({required bool strict}) async {
    final generation = ++_refreshGeneration;
    final current = state.asData?.value;
    final next = await _loadState(
      section: current?.section ?? MusicSection.songs,
      currentItem: current?.currentItem,
      playbackPlan: current?.playbackPlan,
      isPlaying: current?.isPlaying ?? false,
      playbackItems: current?.playbackItems ?? const [],
      playbackIndex: current?.playbackIndex ?? -1,
      repeatMode: current?.repeatMode ?? MusicRepeatMode.off,
      shuffleEnabled: current?.shuffleEnabled ?? false,
      lastScanJob: current?.lastScanJob,
      restorePlaybackQueue: false,
      selectedPlaylist: current?.selectedPlaylist,
      selectedPlaylistTracks: current?.selectedPlaylistTracks,
      selectedAlbum: current?.selectedAlbum,
      selectedArtist: current?.selectedArtist,
    );
    if (_controllerDisposed ||
        !ref.mounted ||
        generation != _refreshGeneration) {
      return;
    }
    if (strict && next.errorMessage != null) {
      throw StateError(next.errorMessage!);
    }
    state = AsyncData(next);
  }

  final List<String> _partialErrors = [];

  Future<MusicCenterState> _loadState({
    MusicSection section = MusicSection.songs,
    MusicPlayableItem? currentItem,
    MusicPlaybackPlan? playbackPlan,
    bool isPlaying = false,
    List<MusicPlayableItem> playbackItems = const [],
    int playbackIndex = -1,
    MusicRepeatMode repeatMode = MusicRepeatMode.off,
    bool shuffleEnabled = false,
    MusicScanJob? lastScanJob,
    bool restorePlaybackQueue = true,
    MusicPlaylist? selectedPlaylist,
    List<MusicTrack>? selectedPlaylistTracks,
    MusicAlbum? selectedAlbum,
    MusicArtist? selectedArtist,
  }) async {
    _partialErrors.clear();
    final results = await Future.wait([
      _safe(_api.dashboard, MusicDashboard.empty()),
      _safe(_api.tracks, <MusicTrack>[]),
      _safe(_api.albums, <MusicAlbum>[]),
      _safe(_api.artists, <MusicArtist>[]),
      _safe(_api.playlists, <MusicPlaylist>[]),
      _safe(_api.recentItems, <MusicRecentEntry>[]),
      _safe(_api.lastPlayed, null),
      _queuePersistence.load(),
      _safePlatformInfo(),
    ]);
    final dashboard = results[0] as MusicDashboard;
    final tracks = results[1] as List<MusicTrack>;
    final albums = results[2] as List<MusicAlbum>;
    final artists = results[3] as List<MusicArtist>;
    final playlists = results[4] as List<MusicPlaylist>;
    final recentEntries = results[5] as List<MusicRecentEntry>;
    final lastPlayed = results[6] as MusicTrack?;
    final queueSnapshot = results[7] as MusicPlaybackQueueSnapshot;
    final platformInfo = results[8] as Map<String, PlatformUserInfo?>;
    final recentItems = _toRecentItems(recentEntries);
    var resolvedQueue = List<MusicPlayableItem>.of(playbackItems);
    var resolvedQueueIndex = playbackIndex;
    var resolvedRepeatMode = repeatMode;
    var resolvedShuffleEnabled = shuffleEnabled;
    if (restorePlaybackQueue && resolvedQueue.isEmpty) {
      resolvedQueue = _restorePlaybackQueue(queueSnapshot, tracks);
      final restoredKey = queueSnapshot.currentItem?.playableKey;
      resolvedQueueIndex = resolvedQueue.indexWhere(
        (item) => item.playableKey == restoredKey,
      );
      if (resolvedQueueIndex < 0 && resolvedQueue.isNotEmpty) {
        resolvedQueueIndex = 0;
      }
      resolvedRepeatMode = _repeatModeFromValue(queueSnapshot.repeatMode);
      resolvedShuffleEnabled = queueSnapshot.shuffleEnabled;
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
        final unavailable =
            selectedItem.ref is OnlineMusicRef &&
            _isUnavailableOnlineResource(error);
        if (unavailable) {
          resolvedQueue.removeWhere(
            (item) => item.playableKey == selectedItem?.playableKey,
          );
          final fallback = _resolveLocalFallback(
            recentItems: recentItems,
            lastPlayed: lastPlayed,
            tracks: tracks,
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
    // 保留打开中的歌单曲目，同步收藏状态并剔除已删除曲目。
    final resolvedPlaylistTracks =
        selectedPlaylistTracks == null
            ? const <MusicTrack>[]
            : [
              for (final track in selectedPlaylistTracks)
                if (trackById.containsKey(track.id)) trackById[track.id]!,
            ];
    final resolvedAlbumTracks =
        resolvedAlbum == null
            ? const <MusicTrack>[]
            : tracks
                .where((track) => track.albumTitle == resolvedAlbum.title)
                .toList(growable: false);
    final resolvedArtistTracks =
        resolvedArtist == null
            ? const <MusicTrack>[]
            : tracks
                .where((track) => track.artistName == resolvedArtist.name)
                .toList(growable: false);
    return MusicCenterState(
      dashboard: dashboard,
      tracks: tracks,
      albums: albums,
      artists: artists,
      playlists: playlists,
      recentItems: recentItems,
      section: section,
      currentItem: selectedItem,
      playbackPlan: resolvedPlan,
      isPlaying: isPlaying && resolvedPlan != null,
      playbackItems: List<MusicPlayableItem>.unmodifiable(resolvedQueue),
      playbackIndex: resolvedQueueIndex,
      repeatMode: resolvedRepeatMode,
      shuffleEnabled: resolvedShuffleEnabled,
      selectedPlaylist: resolvedPlaylist,
      selectedPlaylistTracks: resolvedPlaylistTracks,
      selectedAlbum: resolvedAlbum,
      selectedAlbumTracks: resolvedAlbumTracks,
      selectedArtist: resolvedArtist,
      selectedArtistTracks: resolvedArtistTracks,
      lastScanJob: lastScanJob,
      neteaseUserInfo: platformInfo['netease'],
      qqUserInfo: platformInfo['qq'],
      errorMessage: _partialErrors.isEmpty ? null : _partialErrors.join('；'),
    );
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
    return _resolveLocalFallback(
      recentItems: recentItems,
      lastPlayed: lastPlayed,
      tracks: tracks,
    );
  }

  MusicPlayableItem? _resolveLocalFallback({
    required List<MusicPlayableItem> recentItems,
    required MusicTrack? lastPlayed,
    required List<MusicTrack> tracks,
  }) {
    for (final item in recentItems) {
      if (item.ref case LocalMusicRef(:final trackId)) {
        return MusicPlayableItem.local(
          _findTrack(tracks, trackId) ?? item.track,
        );
      }
    }
    if (lastPlayed != null) {
      return MusicPlayableItem.local(
        _findTrack(tracks, lastPlayed.id) ?? lastPlayed,
      );
    }
    return tracks.isEmpty ? null : MusicPlayableItem.local(tracks.first);
  }

  MusicTrack? _findTrack(List<MusicTrack> tracks, String trackId) {
    for (final track in tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  bool _isUnavailableOnlineResource(Object error) {
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

  Future<T> _safe<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on Exception catch (e) {
      _partialErrors.add(describeUserFacingError(e).message);
      return fallback;
    }
  }

  void _setError(String message) {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(errorMessage: message));
    }
  }

  void clearError() {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(clearError: true));
    }
  }

  void selectSection(MusicSection section) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        section: section,
        clearSelectedPlaylist: section != MusicSection.playlistDetail,
        clearSelectedAlbum: section != MusicSection.albumDetail,
        clearSelectedArtist: section != MusicSection.artistDetail,
      ),
    );
  }

  Future<void> _playItemInQueue(
    MusicCenterState current,
    List<MusicPlayableItem> queue,
    int index,
  ) async {
    if (queue.isEmpty || index < 0 || index >= queue.length) {
      return;
    }
    final generation = ++_playRequestGeneration;
    final item = queue[index];
    final pendingState = current.copyWith(
      currentItem: item,
      clearPlaybackPlan: true,
      isPlaying: true,
      playbackItems: queue,
      playbackIndex: index,
    );
    state = AsyncData(pendingState);
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
      final latest = state.asData?.value;
      if (item.ref is OnlineMusicRef && _isUnavailableOnlineResource(error)) {
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
        state = AsyncData(
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
    final latest = state.asData?.value;
    if (latest == null || latest.currentItem?.playableKey != item.playableKey) {
      return;
    }
    state = AsyncData(
      latest.copyWith(
        playbackPlan: plan,
        isPlaying: true,
        playbackIndex: index,
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
      return;
    }
    final fallback = _resolveLocalFallback(
      recentItems: current.recentItems,
      lastPlayed: null,
      tracks: current.tracks,
    );
    if (fallback != null && fallback.playableKey != failedItem.playableKey) {
      await _playItemInQueue(current, <MusicPlayableItem>[fallback], 0);
      return;
    }
    final failedState = current.copyWith(
      playbackItems: const <MusicPlayableItem>[],
      playbackIndex: -1,
      isPlaying: false,
      errorMessage: describeUserFacingError(error).message,
    );
    state = AsyncData(failedState);
    _queuePersistence.schedule(failedState);
  }

  void _promoteRecentItem(MusicPlayableItem item) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final recentItems = <MusicPlayableItem>[
      item,
      ...current.recentItems.where(
        (candidate) => candidate.playableKey != item.playableKey,
      ),
    ].take(50).toList(growable: false);
    state = AsyncData(current.copyWith(recentItems: recentItems));
  }

  Future<void> _recordPlayableHistory(MusicPlayableItem item) async {
    final mediaMid = switch (item.ref) {
      OnlineMusicRef(:final mediaMid) => mediaMid,
      LocalMusicRef() => null,
    };
    try {
      await _api.recordPlayableHistory(
        playableKey: item.playableKey,
        title: item.track.title,
        artistName: item.track.artistName,
        albumTitle: item.track.albumTitle,
        coverUrl: item.track.coverUrl ?? '',
        durationSeconds: item.track.durationSeconds,
        mediaMid: mediaMid,
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
      final lyrics = await _api.platformTrackLyrics(
        ref.platform.apiValue,
        ref.songId,
      );
      if (lyrics == null || generation != _playRequestGeneration) {
        return;
      }
      final current = state.asData?.value;
      if (current?.currentItem?.playableKey != item.playableKey) {
        return;
      }
      final updatedItem = item.copyWith(
        track: item.track.copyWith(lyricsRaw: lyrics),
      );
      state = AsyncData(
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

  List<MusicPlayableItem> _queueFor(
    MusicCenterState state,
    MusicPlayableItem item,
  ) {
    if (item.ref is OnlineMusicRef) {
      if (state.playbackItems.any(
        (candidate) => candidate.playableKey == item.playableKey,
      )) {
        return state.playbackItems;
      }
      return [item];
    }
    // 歌单详情页使用歌单内歌曲作为队列。
    if (state.section == MusicSection.playlistDetail &&
        state.selectedPlaylistTracks.isNotEmpty &&
        state.selectedPlaylistTracks.any(
          (track) => track.id == item.track.id,
        )) {
      return state.selectedPlaylistTracks.map(MusicPlayableItem.local).toList();
    }
    // 专辑详情页使用专辑内歌曲作为队列。
    if (state.section == MusicSection.albumDetail &&
        state.selectedAlbumTracks.isNotEmpty &&
        state.selectedAlbumTracks.any((track) => track.id == item.track.id)) {
      return state.selectedAlbumTracks.map(MusicPlayableItem.local).toList();
    }
    // 歌手详情页使用歌手歌曲作为队列。
    if (state.section == MusicSection.artistDetail &&
        state.selectedArtistTracks.isNotEmpty &&
        state.selectedArtistTracks.any((track) => track.id == item.track.id)) {
      return state.selectedArtistTracks.map(MusicPlayableItem.local).toList();
    }
    if (state.tracks.any((track) => track.id == item.track.id)) {
      return state.tracks.map(MusicPlayableItem.local).toList();
    }
    return [item];
  }

  void _reportQueuePersistenceFailure(Object error) {
    if (kDebugMode) {
      debugPrint('[MusicQueue] 同步远端播放队列失败: $error');
    }
    if (_controllerDisposed) {
      return;
    }
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final message = describeUserFacingError(error).message;
    _queuePersistenceErrorMessage = message;
    state = AsyncData(current.copyWith(errorMessage: message));
  }

  void _clearQueuePersistenceError() {
    if (_controllerDisposed) {
      return;
    }
    final message = _queuePersistenceErrorMessage;
    final current = state.asData?.value;
    if (message != null && current?.errorMessage == message) {
      state = AsyncData(current!.copyWith(clearError: true));
    }
    _queuePersistenceErrorMessage = null;
  }

  /// 播放在线曲目。
  Future<void> playOnlineTrack(OnlineTrack track) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    try {
      final item = MusicPlayableItem.online(track);
      await _playItemInQueue(current, <MusicPlayableItem>[item], 0);
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
    }
  }
}
