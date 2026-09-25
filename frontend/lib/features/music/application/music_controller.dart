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

  /// 平台账号曲库的当前快照：队列重建按值取用，不订阅平台状态变化。
  MusicPlatformLibraryState get _platformLibrarySnapshot =>
      ref.read(musicPlatformLibraryProvider).asData?.value ??
      const MusicPlatformLibraryState();

  MusicCenterState? get _currentState => state.asData?.value;

  /// 补齐外部平台歌单曲目：`ref` 只能在类体内取用，队列命令扩展经此转接。
  Future<List<OnlineTrack>> _loadAllPlatformPlaylistTracks(
    OnlinePlaylist playlist,
  ) async {
    final notifier = ref.read(musicPlatformLibraryProvider.notifier);
    final tracks = await notifier.loadAllPlaylistTracks(playlist);
    if (_controllerDisposed) {
      return const <OnlineTrack>[];
    }
    return tracks;
  }

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
    final loaded = await _loadState(includeSecondary: false);
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
    final knownErrorCount = _partialErrors.length;
    final results = await Future.wait(<Future<Object?>>[
      _safe(_api.dashboard, MusicDashboard.empty()),
      _safe(() async => (await _api.albums(size: 200)).items, <MusicAlbum>[]),
      _safe(() async => (await _api.artists(size: 200)).items, <MusicArtist>[]),
      _safePlatformInfo(),
    ]);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_controllerDisposed || !ref.mounted) {
        return;
      }
      if (state.asData?.value != null) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    final current = state.asData?.value;
    if (current == null ||
        _controllerDisposed ||
        !ref.mounted ||
        generation != _refreshGeneration) {
      return;
    }
    final freshErrors =
        knownErrorCount < _partialErrors.length
            ? _partialErrors.sublist(knownErrorCount)
            : const <String>[];
    final platformInfo = results[3] as Map<String, PlatformUserInfo?>;
    state = AsyncData(
      current.copyWith(
        dashboard: results[0] as MusicDashboard,
        albums: results[1] as List<MusicAlbum>,
        artists: results[2] as List<MusicArtist>,
        neteaseUserInfo: platformInfo['netease'],
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
}
