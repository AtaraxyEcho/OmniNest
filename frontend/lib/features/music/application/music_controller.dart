import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_playback_resolver.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:omninest/core/log/dev_log.dart';

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

  /// 洗牌随机源，测试可注入固定种子保证确定性。
  @visibleForTesting
  Random random = Random();

  /// 未播洗牌序（playableKey），洗牌开启时按轮次消费。
  final List<String> _shuffleUpcoming = <String>[];

  /// 已播历史栈，previousTrack 回退依据，超出上限丢弃栈底。
  final List<String> _playHistory = <String>[];

  /// 当前洗牌轮是否已耗尽；耗尽后仅 repeat=all 才重新生成。
  bool _shuffleRoundConsumed = false;

  /// 已播历史上限。
  static const int _playHistoryLimit = 200;

  /// library 来源队列重建与续页的单次取页上限。
  static const int _libraryPageLimit = 20;

  /// library 纯本地来源队列的续页游标（下一页页码，null=未初始化）。
  int? _libraryNextPage;
  int _libraryFetchGeneration = 0;
  bool _libraryFetchingMore = false;

  /// 曲库曲目分页大小，初始加载与增量加载保持一致。
  static const int musicLibraryPageSize = 100;

  /// 按已加载数量向上取整到分页大小，保证刷新请求完整覆盖已加载页。
  static int _tracksPageSizeFor(int? loadedCount) {
    if (loadedCount == null || loadedCount <= musicLibraryPageSize) {
      return musicLibraryPageSize;
    }
    final pages = (loadedCount / musicLibraryPageSize).ceil();
    return pages * musicLibraryPageSize;
  }

  MusicApi get _api => ref.read(musicApiProvider);

  MusicCenterState? get _currentState => state.asData?.value;

  void _replaceState(MusicCenterState value) {
    state = AsyncData(value);
  }

  /// 平台登录/断开后的后台刷新：账号资料 + 曲库全量失效。
  ///
  /// 由 application 层持有完整流程，不随登录面板关闭而丢失——此前
  /// 面板在慢速资料回源期间被用户关闭，`mounted` 守卫会跳过曲库
  /// 失效，表现为"登录成功但首页/曲库/歌单/收藏全空"。
  Future<void> refreshAfterPlatformChange() async {
    try {
      await loadPlatformInfo();
    } on Object {
      // 账号资料刷新失败不阻塞曲库刷新。
    }
    if (_controllerDisposed || !ref.mounted) {
      return;
    }
    ref.invalidate(musicPlatformLibraryProvider);
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
    preferredOnlineQuality:
        () =>
            ref.read(musicLocalPreferencesControllerProvider).asData?.value ??
            'exhigh',
  );

  @override
  Future<MusicCenterState> build() async {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧值。
    ref.watch(sessionEpochProvider);
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
    if (loaded.playMode == MusicPlayMode.shuffle) {
      _startShuffleRound(loaded.playbackItems, loaded.currentItem?.playableKey);
    }
    if (_queuePersistence.restoreRequiresRemoteSync) {
      _queuePersistence.schedule(loaded, delay: Duration.zero);
    }
    // 恢复的会话不经过播放请求路径：在线曲目恢复后歌词为空，
    // 此处补拉一次，与主动播放时的行为一致。
    final restoredItem = loaded.currentItem;
    if (restoredItem != null &&
        restoredItem.ref is OnlineMusicRef &&
        restoredItem.track.lyricsRaw?.isNotEmpty != true) {
      unawaited(_loadOnlineLyrics(restoredItem, _playRequestGeneration));
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
    var next = await _loadState(
      section: current?.section ?? MusicSection.songs,
      playback: current?.playbackView,
      lastScanJob: current?.lastScanJob,
      restorePlaybackQueue: false,
      selectedPlaylist: current?.selectedPlaylist,
      selectedPlaylistTracks: current?.selectedPlaylistTracks,
      selectedAlbum: current?.selectedAlbum,
      selectedAlbumTracks: current?.selectedAlbumTracks,
      selectedArtist: current?.selectedArtist,
      selectedArtistTracks: current?.selectedArtistTracks,
      // 刷新时对齐已加载页数，避免增量加载过的曲目列表被重置回首页。
      tracksPageSize: _tracksPageSizeFor(current?.tracks.length),
    );
    if (_controllerDisposed ||
        !ref.mounted ||
        generation != _refreshGeneration) {
      return;
    }
    if (strict && next.errorMessage != null) {
      throw StateError(next.errorMessage!);
    }
    // 打开中的详情以服务端曲目为准，覆盖跨端增删与分页限制。
    final openPlaylistId =
        current?.section == MusicSection.playlistDetail
            ? current?.selectedPlaylist?.id
            : null;
    if (openPlaylistId != null) {
      try {
        final remoteTracks = await _api.playlistTracks(openPlaylistId);
        if (_controllerDisposed ||
            !ref.mounted ||
            generation != _refreshGeneration) {
          return;
        }
        next = next.copyWith(selectedPlaylistTracks: remoteTracks);
      } on Exception {
        // 详情重拉失败时保留已缓存曲目，不打断中心刷新。
      }
    }
    final openAlbumId =
        current?.section == MusicSection.albumDetail
            ? current?.selectedAlbum?.id
            : null;
    if (openAlbumId != null) {
      try {
        final remoteTracks = await _api.albumTracks(openAlbumId);
        if (_controllerDisposed ||
            !ref.mounted ||
            generation != _refreshGeneration) {
          return;
        }
        next = next.copyWith(selectedAlbumTracks: remoteTracks);
      } on Exception {
        // 详情重拉失败时保留已缓存曲目，不打断中心刷新。
      }
    }
    final openArtistId =
        current?.section == MusicSection.artistDetail
            ? current?.selectedArtist?.id
            : null;
    if (openArtistId != null) {
      try {
        final remoteTracks = await _api.artistTracks(openArtistId);
        if (_controllerDisposed ||
            !ref.mounted ||
            generation != _refreshGeneration) {
          return;
        }
        next = next.copyWith(selectedArtistTracks: remoteTracks);
      } on Exception {
        // 详情重拉失败时保留已缓存曲目，不打断中心刷新。
      }
    }
    state = AsyncData(next);
  }

  final List<String> _partialErrors = [];

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
    int tracksPageSize = musicLibraryPageSize,
  }) async {
    final currentItem = playback?.currentItem;
    final playbackPlan = playback?.playbackPlan;
    final isPlaying = playback?.isPlaying ?? false;
    final playbackItems =
        playback?.playbackItems ?? const <MusicPlayableItem>[];
    final playbackIndex = playback?.playbackIndex ?? -1;
    final playMode = playback?.playMode ?? MusicPlayMode.sequential;
    _partialErrors.clear();
    final results = await Future.wait([
      _safe(_api.dashboard, MusicDashboard.empty()),
      _safe(() async {
        final page = await _api.tracks(size: tracksPageSize);
        return _LibraryTracksPage(
          items: page.items,
          totalElements: page.totalElements,
          page: page.page,
          size: page.size,
        );
      }, _LibraryTracksPage.empty()),
      _safe(() async => (await _api.albums(size: 200)).items, <MusicAlbum>[]),
      _safe(() async => (await _api.artists(size: 200)).items, <MusicArtist>[]),
      _safe(_api.playlists, <MusicPlaylist>[]),
      _safe(_api.recentItems, <MusicRecentEntry>[]),
      _safe(_api.lastPlayed, null),
      _queuePersistence.load(),
      _safePlatformInfo(),
    ]);
    final dashboard = results[0] as MusicDashboard;
    final tracksPage = results[1] as _LibraryTracksPage;
    var tracks = tracksPage.items;
    var hasMoreTracks = tracksPage.hasMore;
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
    var resolvedPlayMode = playMode;
    var resolvedQueueSource =
        playback?.queueSource ?? MusicQueueSource.transient;
    if (restorePlaybackQueue && resolvedQueue.isEmpty) {
      resolvedQueue = _restorePlaybackQueue(queueSnapshot, tracks);
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
      // 来源不可重建时降级为窗口快照（transient）。
      resolvedQueueSource = MusicQueueSource.transient;
      if (queueSnapshot.source.rebuildable && restoredKey != null) {
        final rebuilt = await _rebuildQueueFromSource(
          queueSnapshot.source,
          restoredKey,
          tracks,
        );
        if (rebuilt != null) {
          resolvedQueue = rebuilt.items;
          resolvedQueueIndex = rebuilt.index;
          resolvedQueueSource = rebuilt.source;
          tracks = rebuilt.tracks;
          hasMoreTracks = rebuilt.hasMore;
          if (rebuilt.nextPage != null) {
            _libraryNextPage = rebuilt.nextPage;
          }
        }
      }
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
    // 解析期间队列可能已被 reorder/remove 改变，回写索引按 key 重定位而非沿用旧几何。
    final resolvedIndex = latest.playbackItems.indexWhere(
      (candidate) => candidate.playableKey == item.playableKey,
    );
    state = AsyncData(
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
      final current = state.asData?.value;
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
              ...(((ref.read(musicPlatformLibraryProvider).asData?.value ??
                              const MusicPlatformLibraryState())
                          .likedTracksByPlatform[platform] ??
                      const <OnlineTrack>[])
                  .map(MusicPlayableItem.online)),
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
      final result = await _api.tracks(page: page, size: musicLibraryPageSize);
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
      nextPage: hasMore ? (tracks.length / musicLibraryPageSize).ceil() : null,
    );
  }

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
    _libraryNextPage ??= (current.tracks.length / musicLibraryPageSize).ceil();
    final page = _libraryNextPage!;
    _libraryFetchingMore = true;
    _replaceState(current.copyWith(tracksLoadingMore: true));
    try {
      final result = await _api.tracks(page: page, size: musicLibraryPageSize);
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
      final mergedQueue = List<MusicPlayableItem>.of(latest.playbackItems)
        ..addAll(freshItems);
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

  void _reportQueuePersistenceFailure(Object error) {
    if (kDebugMode) {
      devLog('[MusicQueue] 同步远端播放队列失败: $error');
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

/// 曲库加载内部使用的曲目分页载体，用于区分加载失败与空结果。
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
