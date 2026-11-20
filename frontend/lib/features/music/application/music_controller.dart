import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/errors/user_facing_error_locale.dart';
import 'package:omninest/core/network/capability_gate_interceptor.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_playback_resolver.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
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
part 'music_center_queue_restore.dart';
part 'music_queue_persistence.dart';
part 'music_platform_account_commands.dart';
part 'music_providers.dart';
part 'music_center_state_load.dart';
part 'music_playback_helpers.dart';
part 'music_library_queue_more.dart';

class MusicCenterController extends AsyncNotifier<MusicCenterState> {
  int _playRequestGeneration = 0;
  int _refreshGeneration = 0;

  /// 首帧之后待补齐的恢复队列来源，以及取消在途回填的代次。
  _QueueRebuildIntent? _pendingQueueRebuild;
  int _queueRebuildGeneration = 0;
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

  /// 平台歌单渐进播放使用的受保护依赖转接，避免扩展文件直接访问 [ref]。
  MusicPlatformLibraryController get _platformLibrary =>
      ref.read(musicPlatformLibraryProvider.notifier);

  MusicPlatformLibraryState? get _platformLibrarySnapshot =>
      ref.read(musicPlatformLibraryProvider).asData?.value;

  bool get _isControllerAlive => !_controllerDisposed && ref.mounted;

  MusicCenterState? get _currentState => state.asData?.value;

  /// 播放历史门控：`ref` 只能在类体内取用，播放流程扩展经此转接。
  bool get _canManageOwnActivity =>
      ref.read(userCapabilitiesProvider).canManageOwnActivity;

  /// 恢复曲内进度：`ref` 只能在类体内取用，队列命令扩展经此转接。
  Future<void> _primeResumePosition(String? playableKey) => ref
      .read(musicPlaybackSessionProvider.notifier)
      .primeResumePosition(playableKey);

  /// 补齐外部平台整个喜欢列表：队列重建经此转接，语义与歌单整队一致。
  Future<List<OnlineTrack>> _loadAllLikedTracks(String platform) async {
    final notifier = ref.read(musicPlatformLibraryProvider.notifier);
    final tracks = await notifier.loadAllLikedTracks(platform);
    if (_controllerDisposed) {
      return const <OnlineTrack>[];
    }
    return tracks;
  }

  void _replaceState(MusicCenterState value) {
    state = AsyncData(value);
  }

  void addWeekListeningSeconds(int seconds) {
    final current = _currentState;
    if (seconds <= 0 || current == null) {
      return;
    }
    _replaceState(
      current.copyWith(
        dashboard: current.dashboard.copyWith(
          weekListeningSeconds:
              current.dashboard.weekListeningSeconds + seconds,
        ),
      ),
    );
  }

  Future<void> attachListeningHistoryToPlaybackSession(
    String historyId,
    String playableKey,
  ) {
    return ref
        .read(musicPlaybackSessionProvider.notifier)
        .attachListeningHistory(historyId, playableKey);
  }

  /// 取数或远端动作完成后的回写基准。
  ///
  /// 完成回调不得把 `await` 之前抓的 `MusicCenterState` 快照整份发布：那段窗口里发生的
  /// 写入（播放队列、分页窗口、选中详情、加载标记）会被旧快照无声覆盖。发布基准取发布
  /// 时刻的实况，仅在实况尚未就绪（首帧取数、错误态）时退回快照。
  /// 调用方保留各自的快照判空提前返回，本助手不构造默认状态。
  MusicCenterState _liveOr(MusicCenterState captured) =>
      _currentState ?? captured;

  /// 平台登录/断开后的刷新：账号资料 + 曲库重新接入。
  ///
  /// 由 application 层持有完整流程，不随登录面板关闭而丢失——此前
  /// 面板在慢速资料回源期间被用户关闭，`mounted` 守卫会跳过曲库
  /// 失效，表现为"登录成功但首页/曲库/歌单/收藏全空"。
  ///
  /// [waitForConnectedProfile] 用于扫码确认路径。二维码确认时后端会先保存
  /// Cookie，再异步回源平台资料；若在 externalUserId 落地前就读取歌单，平台会
  /// 返回空列表，前端还会把这个空列表当作成功结果。确认路径因此先等待资料落地，
  /// 再触发一次完整曲库刷新，确保账号资料、歌单和喜欢列表属于同一轮接入。
  Future<void> refreshAfterPlatformChange({
    bool waitForConnectedProfile = false,
  }) async {
    if (waitForConnectedProfile) {
      final profile = await _waitForConnectedPlatformProfile();
      if (profile == null) {
        throw StateError('网易云账号资料同步失败，请稍后重试');
      }
      await _refreshPlatformLibrary(forceRefresh: true);
      // 中心控制器可能仍在首帧 build；曲库刷新完成后再回写一次资料，
      // 避免首帧结束时把已确认账号落成空状态。
      await _loadPlatformInfo();
      return;
    }

    final platformInfo = loadPlatformInfo();
    final library = _refreshPlatformLibrary();
    try {
      await platformInfo;
    } on Object {
      // 账号资料刷新失败不阻塞曲库刷新。
    }
    try {
      await library;
    } on Object {
      // 曲库状态自身保留失败原因，面板关闭或重试时会再次回源。
    }
  }

  /// 等待登录确认后由后端异步补齐的平台账号资料。
  Future<PlatformUserInfo?> _waitForConnectedPlatformProfile() async {
    const retryDelays = <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(milliseconds: 1000),
    ];
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (_controllerDisposed || !ref.mounted) {
        return null;
      }
      final profile = await _loadPlatformInfo();
      if (profile != null) {
        return profile;
      }
      if (attempt < retryDelays.length) {
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
    return null;
  }

  /// 重建平台曲库并等待 Provider 的新状态落地。
  Future<void> _refreshPlatformLibrary({bool forceRefresh = false}) async {
    if (_controllerDisposed || !ref.mounted) {
      return;
    }
    final library = await ref.refresh(musicPlatformLibraryProvider.future);
    if (!forceRefresh ||
        _controllerDisposed ||
        !ref.mounted ||
        library.connectedStatuses.isEmpty) {
      return;
    }
    // 登录确认后的第一次读取可能与后端预热并行，强刷再取一次完整喜欢列表，
    // 避免渐进首帧把空结果固定成账号刚接入时的最终状态。
    await ref.read(musicPlatformLibraryProvider.notifier).refresh();
  }

  /// 作废收藏列表：收藏分区读服务端完整列表，切换收藏后必须重取。
  ///
  /// 供同库扩展调用——扩展体内取受保护的 `ref` 会被分析器拒绝。
  void invalidateFavoriteTracks() {
    if (_controllerDisposed || !ref.mounted) {
      return;
    }
    ref.invalidate(musicFavoriteTracksProvider);
  }

  Future<void> _refreshTaskState() async {
    if (_controllerDisposed || !ref.mounted) {
      return;
    }
    ref.invalidate(activeTaskSummaryProvider);
    try {
      await ref.read(taskListProvider.notifier).load();
    } on Exception catch (error) {
      // 任务列表是辅助状态：删除等业务动作已经成功，列表刷新失败不应把动作判失败；
      // 列表自身保留上一次成功结果，下次刷新会自然重试。
      if (kDebugMode) {
        devLog('[MusicTask] 刷新任务列表失败: ${error.runtimeType}');
      }
    }
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
    final loaded = await _loadState(includeSecondary: false);
    if (loaded.playMode == MusicPlayMode.shuffle) {
      _startShuffleRound(loaded.playbackItems, loaded.currentItem?.playableKey);
    }
    if (_queuePersistence.restoreRequiresRemoteSync) {
      _queuePersistence.schedule(loaded, delay: Duration.zero);
    }
    // 恢复的会话不经过播放请求路径：列表投影与在线曲目恢复后歌词为空，
    // 此处补拉一次，与主动播放时的行为一致。
    final restoredItem = loaded.currentItem;
    if (restoredItem != null &&
        restoredItem.track.lyricsRaw?.isNotEmpty != true) {
      if (restoredItem.ref is OnlineMusicRef) {
        unawaited(_loadOnlineLyrics(restoredItem, _playRequestGeneration));
      } else if (restoredItem.ref is LocalMusicRef) {
        unawaited(_loadLocalLyrics(restoredItem, _playRequestGeneration));
      }
    }
    unawaited(_backfillSecondary());
    return loaded;
  }

  /// 首帧之后补齐次级数据：仪表盘点、专辑与歌手全量列表、各平台账号资料。
  ///
  /// 这些切片都不参与 Music 首页首帧，此前却与必需请求排在同一栅栏里，最慢的
  /// 第三方账号资料回源会把整页压在加载态——表现就是登录平台后与首次进入时的
  /// 明显卡顿。补齐结果只在没有新的刷新启动时发布，且必须等 `build()` 的返回值
  /// 落地后再写状态，否则会用尚无数据的快照覆盖首帧。
  Future<void> _backfillSecondary() async {
    final generation = _refreshGeneration;
    // `_partialErrors` 里是首帧已经发布过的错误，可能被用户关掉过；
    // 直接重新拼接会把旧错误再弹一次，因此只登记本轮新增的部分。
    var reportedErrorCount = _partialErrors.length;
    Future<bool> publish({
      MusicDashboard? dashboard,
      List<MusicAlbum>? albums,
      List<MusicArtist>? artists,
      Map<String, PlatformUserInfo?>? platformInfo,
    }) async {
      // 回填与 build 同时启动时，快速响应可能先于首帧状态落地；持续让出事件
      // 循环，直到首帧可合并，避免这类竞态把已经取到的专辑丢掉。
      while (true) {
        if (_controllerDisposed || !ref.mounted) {
          return false;
        }
        final pending = state;
        if (pending.asData?.value != null) {
          break;
        }
        if (pending.hasError) {
          return false;
        }
        await Future<void>.delayed(Duration.zero);
      }
      final current = state.asData?.value;
      if (current == null ||
          _controllerDisposed ||
          !ref.mounted ||
          generation != _refreshGeneration) {
        return false;
      }
      final freshErrors =
          reportedErrorCount < _partialErrors.length
              ? _partialErrors.sublist(reportedErrorCount)
              : const <String>[];
      final nextDashboard = dashboard;
      final nextAlbums = albums;
      final nextArtists = artists;
      final nextPlatformInfo = platformInfo;
      state = AsyncData(
        current.copyWith(
          // 次级请求失败时保留首帧小窗口，避免一次短暂 5xx 把首页专辑清空。
          dashboard:
              nextDashboard != null &&
                      (nextDashboard.trackCount > 0 ||
                          nextDashboard.albumCount > 0 ||
                          nextDashboard.recentTracks.isNotEmpty ||
                          nextDashboard.recentAlbums.isNotEmpty)
                  ? nextDashboard
                  : current.dashboard,
          albums:
              nextAlbums != null && nextAlbums.isNotEmpty
                  ? nextAlbums
                  : current.albums,
          artists:
              nextArtists != null && nextArtists.isNotEmpty
                  ? nextArtists
                  : current.artists,
          neteaseUserInfo: nextPlatformInfo?['netease'],
          // 无新错误时不传 errorMessage（copyWith 传 null 即保持原值）；
          // 有新错误时追加到尚未关闭的旧错误之后。
          errorMessage:
              freshErrors.isEmpty
                  ? null
                  : <String>[
                    if (current.errorMessage != null) current.errorMessage!,
                    ...freshErrors,
                  ].join('；'),
        ),
      );
      reportedErrorCount = _partialErrors.length;
      return true;
    }

    // 专辑是首页可见内容，先单独发布十张，避免被慢速账号资料或仪表盘请求
    // 阻塞；其余次级切片随后合并，仍然只取一次请求结果。
    final albumsFuture = _safe(
      () async => (await _api.albums(size: 10)).items,
      <MusicAlbum>[],
    );
    final dashboardFuture = _safe(_api.dashboard, MusicDashboard.empty());
    final artistsFuture = _safe(
      () async => (await _api.artists(size: 200)).items,
      <MusicArtist>[],
    );
    final platformInfoFuture = _safePlatformInfo();
    final albums = await albumsFuture;
    if (!await publish(albums: albums)) {
      return;
    }
    final results = await Future.wait<Object?>([
      dashboardFuture,
      artistsFuture,
      platformInfoFuture,
    ]);
    await publish(
      dashboard: results[0] as MusicDashboard,
      artists: results[1] as List<MusicArtist>,
      platformInfo: results[2] as Map<String, PlatformUserInfo?>,
    );
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
    // 刷新期间播放器仍在写入进度、缓冲与自动切歌；用最新状态覆盖回写，
    // 否则会把几百毫秒前的 playbackView 快照重新盖回去。
    final latest = state.asData?.value;
    if (latest != null) {
      next = next.copyWith(
        currentItem: latest.currentItem,
        playbackPlan: latest.playbackPlan,
        isPlaying: latest.isPlaying,
        playbackItems: latest.playbackItems,
        playbackIndex: latest.playbackIndex,
        playMode: latest.playMode,
        queueSource: latest.queueSource,
        clearCurrentTrack: latest.currentItem == null,
        clearPlaybackPlan: latest.playbackPlan == null,
      );
    }
    state = AsyncData(next);
  }

  final List<String> _partialErrors = [];

  Future<T> _safe<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on Exception catch (e) {
      _partialErrors.add(userFacingErrorText(e));
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
    final message = userFacingErrorText(error);
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
}
