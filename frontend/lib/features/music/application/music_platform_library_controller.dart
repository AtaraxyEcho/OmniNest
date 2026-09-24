import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';

final musicPlatformLibraryProvider = AsyncNotifierProvider<
  MusicPlatformLibraryController,
  MusicPlatformLibraryState
>(MusicPlatformLibraryController.new);

/// 平台未提供缩放地址时才回退原图，封面网格因此不必下载全尺寸图片。
String _coverUrl({required String coverUrl, required String thumbUrl}) {
  final thumb = thumbUrl.trim();
  return thumb.isNotEmpty ? thumb : coverUrl.trim();
}

/// 外部音乐平台账号曲库状态。
class MusicPlatformLibraryState {
  const MusicPlatformLibraryState({
    this.statuses = const <MusicPlatformStatus>[],
    this.playlistsByPlatform = const <String, List<OnlinePlaylist>>{},
    this.likedTracksByPlatform = const <String, List<OnlineTrack>>{},
    this.playlistTracks = const <String, MusicPagedResult<OnlineTrack>>{},
    this.loadingPlaylistKeys = const <String>{},
    this.appendingPlaylistKeys = const <String>{},
    this.failures = const <String, String>{},
  });

  final List<MusicPlatformStatus> statuses;
  final Map<String, List<OnlinePlaylist>> playlistsByPlatform;
  final Map<String, List<OnlineTrack>> likedTracksByPlatform;

  /// 已加载的平台歌单曲目分页：预热与首屏只落部分页，滚动续载按页追加。
  final Map<String, MusicPagedResult<OnlineTrack>> playlistTracks;
  final Set<String> loadingPlaylistKeys;

  /// 正在追加下一页的歌单键：详情页保留列表，只在底部提示续载。
  final Set<String> appendingPlaylistKeys;
  final Map<String, String> failures;

  /// 返回已连接且可用的平台状态。
  List<MusicPlatformStatus> get connectedStatuses =>
      musicConnectedPlatformStatuses(statuses);

  /// 返回所有已加载的账号歌单。
  List<OnlinePlaylist> get playlists => playlistsByPlatform.values
      .expand((items) => items)
      .toList(growable: false);

  /// 返回所有已加载的账号喜欢歌曲。
  List<OnlineTrack> get likedTracks => likedTracksByPlatform.values
      .expand((items) => items)
      .toList(growable: false);

  /// 返回歌单展示封面，已加载曲目时优先使用第一首歌曲封面。
  String coverUrlForPlaylist(OnlinePlaylist playlist) {
    final page = playlistTracks['${playlist.platform}:${playlist.playlistId}'];
    if (page != null && page.items.isNotEmpty) {
      final firstTrackCover = _coverUrl(
        coverUrl: page.items.first.coverUrl,
        thumbUrl: page.items.first.thumbUrl,
      );
      if (firstTrackCover.isNotEmpty) {
        return firstTrackCover;
      }
    }
    return _coverUrl(coverUrl: playlist.coverUrl, thumbUrl: playlist.thumbUrl);
  }

  MusicPlatformLibraryState copyWith({
    List<MusicPlatformStatus>? statuses,
    Map<String, List<OnlinePlaylist>>? playlistsByPlatform,
    Map<String, List<OnlineTrack>>? likedTracksByPlatform,
    Map<String, MusicPagedResult<OnlineTrack>>? playlistTracks,
    Set<String>? loadingPlaylistKeys,
    Set<String>? appendingPlaylistKeys,
    Map<String, String>? failures,
  }) {
    return MusicPlatformLibraryState(
      statuses: statuses ?? this.statuses,
      playlistsByPlatform: playlistsByPlatform ?? this.playlistsByPlatform,
      likedTracksByPlatform:
          likedTracksByPlatform ?? this.likedTracksByPlatform,
      playlistTracks: playlistTracks ?? this.playlistTracks,
      loadingPlaylistKeys: loadingPlaylistKeys ?? this.loadingPlaylistKeys,
      appendingPlaylistKeys:
          appendingPlaylistKeys ?? this.appendingPlaylistKeys,
      failures: failures ?? this.failures,
    );
  }
}

/// 「已启用且已连接」的平台状态：甲板与现在面板只需要这一片，单独暴露
/// 是为了让消费方按切片订阅，而不是订阅整个状态对象。
List<MusicPlatformStatus> musicConnectedPlatformStatuses(
  List<MusicPlatformStatus> statuses,
) => statuses
    .where((status) => status.enabled && status.connected)
    .toList(growable: false);

/// 加载平台状态、账号歌单和喜欢歌曲，并隔离单来源失败。
class MusicPlatformLibraryController
    extends AsyncNotifier<MusicPlatformLibraryState> {
  static const int _playlistPreloadConcurrency = 3;

  /// 预热覆盖的歌单数量上限：超出的部分走按需加载路径。
  static const int _playlistPreloadLimit = 8;

  /// 预热每个歌单只取封面与预览够用的条数：整表下发会在设备侧解析数百 KB JSON。
  static const int _playlistPreloadTrackPageSize = 50;

  /// 打开歌单只取首屏页，其余页由详情滚动续载。
  static const int _playlistTrackPageSize = 200;

  /// 播放整队时一次取满后端单页上限，保持"整个歌单入队"的既有语义。
  static const int _playlistFullTrackPageSize = 1000;

  int _preloadGeneration = 0;

  /// 每个歌单最近一次发起的曲目请求序号。只有最新发起的响应可以写状态：
  /// 预热首页、首屏、续载和整表共用同一个键，晚到的首页不能把更大的结果截断。
  final Map<String, int> _trackRequestSeq = <String, int>{};

  /// 整表加载按歌单去重，连续点击播放只回源一次。
  final Map<String, Future<List<OnlineTrack>>> _fullTrackFlights =
      <String, Future<List<OnlineTrack>>>{};

  @override
  Future<MusicPlatformLibraryState> build() {
    ref.watch(sessionEpochProvider);
    ref.onDispose(() => _preloadGeneration++);
    return _load();
  }

  /// 重新加载全部平台账号内容。
  ///
  /// 刷新期间保留上一次成功数据，避免 UI 回落空状态闪烁。
  Future<void> refresh() async {
    final previous = state.asData?.value;
    final next = await AsyncValue.guard(() => _load(forceRefresh: true));
    if (next.hasError && previous != null) {
      state = AsyncData(previous);
      return;
    }
    state = next;
  }

  /// 严格刷新实时事件涉及的平台账号曲库。
  Future<void> refreshForRealtime() async {
    final refreshed = await _load(forceRefresh: true);
    state = AsyncData(refreshed);
  }

  /// 按需加载一个在线歌单的首屏曲目。
  ///
  /// 命中预热首页（页数不足首屏）时补齐首屏；已有首屏或续载页时直接复用，
  /// 剩余页由 [loadMorePlaylistTracks] 续载，整表由 [loadAllPlaylistTracks] 补齐。
  /// [forceRefresh] 用于用户点开歌单：跳过该歌单的后端短期缓存，拿到改动后的曲目。
  Future<List<OnlineTrack>> loadPlaylistTracks(
    OnlinePlaylist playlist, {
    bool forceRefresh = false,
  }) async {
    final current = state.asData?.value;
    if (current == null || !ref.mounted) {
      return const <OnlineTrack>[];
    }
    final key = _playlistKey(playlist.platform, playlist.playlistId);
    final cached = current.playlistTracks[key];
    final coversFirstScreen =
        cached != null &&
        cached.size >= _playlistTrackPageSize &&
        (cached.items.isNotEmpty || !cached.hasMore);
    if (coversFirstScreen && !forceRefresh) {
      return cached.items;
    }
    final seq = _beginTrackRequest(key);
    _setPlaylistLoading(key, loading: true);
    try {
      final page = await ref
          .read(musicApiProvider)
          .platformPlaylistTracks(
            playlist.platform,
            playlist.playlistId,
            size: _playlistTrackPageSize,
            refresh: forceRefresh,
          );
      if (!ref.mounted) {
        return const <OnlineTrack>[];
      }
      if (_ownsTrackRequest(key, seq)) {
        _publishTrackPage(key, page);
      }
      return page.items;
    } on Object catch (error) {
      if (!ref.mounted) {
        return const <OnlineTrack>[];
      }
      _recordPlaylistFailure(key, describeUserFacingError(error).message);
      return cached?.items ?? const <OnlineTrack>[];
    } finally {
      _setPlaylistLoading(key, loading: false);
    }
  }

  /// 详情页滚动到底时追加下一页。
  ///
  /// 无更多页、已有请求在途或该歌单已按整表页落地时不发请求：整表页页数与
  /// 续载页页数不同，混用会让 `hasMore` 按错误的页宽推导。
  Future<void> loadMorePlaylistTracks(OnlinePlaylist playlist) async {
    final current = state.asData?.value;
    if (current == null ||
        !ref.mounted ||
        _fullTrackFlights.containsKey(
          _playlistKey(playlist.platform, playlist.playlistId),
        )) {
      return;
    }
    final key = _playlistKey(playlist.platform, playlist.playlistId);
    final cached = current.playlistTracks[key];
    if (cached == null ||
        !cached.hasMore ||
        cached.size != _playlistTrackPageSize ||
        current.loadingPlaylistKeys.contains(key) ||
        current.appendingPlaylistKeys.contains(key)) {
      return;
    }
    final seq = _beginTrackRequest(key);
    _setPlaylistAppending(key, appending: true);
    try {
      final page = await ref
          .read(musicApiProvider)
          .platformPlaylistTracks(
            playlist.platform,
            playlist.playlistId,
            page: cached.page + 1,
            size: _playlistTrackPageSize,
          );
      if (!ref.mounted || !_ownsTrackRequest(key, seq)) {
        return;
      }
      final latest = state.asData?.value;
      final base = latest?.playlistTracks[key];
      // 页序仍是发起时那一页之后才追加：期间若有首屏或整表结果落地，本页作废。
      if (latest == null ||
          base == null ||
          base.page != cached.page ||
          base.size != cached.size) {
        return;
      }
      _publishTrackPage(
        key,
        MusicPagedResult(
          items: <OnlineTrack>[...base.items, ...page.items],
          page: page.page,
          size: page.size,
          totalElements: page.totalElements,
        ),
      );
    } on Object catch (error) {
      if (!ref.mounted || !_ownsTrackRequest(key, seq)) {
        return;
      }
      _recordPlaylistFailure(key, describeUserFacingError(error).message);
    } finally {
      _setPlaylistAppending(key, appending: false);
    }
  }

  /// 补齐整个在线歌单供入队播放，返回可直接播放的曲目列表。
  ///
  /// 在线歌单的队列来源是瞬态的（重启后无法按来源重建），因此入队必须持有
  /// 完整列表；整表按后端单页上限一次取回，与历史行为一致。
  Future<List<OnlineTrack>> loadAllPlaylistTracks(OnlinePlaylist playlist) {
    final key = _playlistKey(playlist.platform, playlist.playlistId);
    return _fullTrackFlights[key] ??= _trackAllFlight(key, playlist);
  }

  Future<List<OnlineTrack>> _trackAllFlight(
    String key,
    OnlinePlaylist playlist,
  ) async {
    final cached = state.asData?.value.playlistTracks[key];
    if (!ref.mounted) {
      return const <OnlineTrack>[];
    }
    final seq = _beginTrackRequest(key);
    _setPlaylistLoading(key, loading: true);
    try {
      final page = await ref
          .read(musicApiProvider)
          .platformPlaylistTracks(
            playlist.platform,
            playlist.playlistId,
            size: _playlistFullTrackPageSize,
          );
      if (!ref.mounted) {
        return const <OnlineTrack>[];
      }
      if (_ownsTrackRequest(key, seq)) {
        _publishTrackPage(key, page);
      }
      return page.items;
    } on Object catch (error) {
      if (!ref.mounted) {
        return const <OnlineTrack>[];
      }
      _recordPlaylistFailure(key, describeUserFacingError(error).message);
      // 整表失败时退回已加载页，点击播放不至于空队列。
      return cached?.items ?? const <OnlineTrack>[];
    } finally {
      _fullTrackFlights.remove(key);
      _setPlaylistLoading(key, loading: false);
    }
  }

  int _beginTrackRequest(String key) {
    final seq = (_trackRequestSeq[key] ?? 0) + 1;
    _trackRequestSeq[key] = seq;
    return seq;
  }

  bool _ownsTrackRequest(String key, int seq) => _trackRequestSeq[key] == seq;

  void _publishTrackPage(String key, MusicPagedResult<OnlineTrack> page) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        playlistTracks: <String, MusicPagedResult<OnlineTrack>>{
          ...current.playlistTracks,
          key: page,
        },
      ),
    );
  }

  void _setPlaylistLoading(String key, {required bool loading}) {
    _setPlaylistFlag(key, loading: loading, appending: null);
  }

  void _setPlaylistAppending(String key, {required bool appending}) {
    _setPlaylistFlag(key, loading: null, appending: appending);
  }

  void _setPlaylistFlag(
    String key, {
    required bool? loading,
    required bool? appending,
  }) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final loadingKeys = <String>{...current.loadingPlaylistKeys};
    final appendingKeys = <String>{...current.appendingPlaylistKeys};
    if (loading ?? false) {
      loadingKeys.add(key);
    } else if (loading != null) {
      loadingKeys.remove(key);
    }
    if (appending ?? false) {
      appendingKeys.add(key);
    } else if (appending != null) {
      appendingKeys.remove(key);
    }
    state = AsyncData(
      current.copyWith(
        loadingPlaylistKeys: loadingKeys,
        appendingPlaylistKeys: appendingKeys,
      ),
    );
  }

  void _recordPlaylistFailure(String key, String message) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        loadingPlaylistKeys: <String>{...current.loadingPlaylistKeys}
          ..remove(key),
        appendingPlaylistKeys: <String>{...current.appendingPlaylistKeys}
          ..remove(key),
        failures: <String, String>{...current.failures, key: message},
      ),
    );
  }

  /// 加载平台账号内容。
  ///
  /// [forceRefresh] 用于用户显式刷新与平台变更事件：只让歌单与喜欢列表跳过后端短期缓存
  /// 回源；歌单曲目页保持复用，需要新页由打开该歌单时单独强制回源。
  Future<MusicPlatformLibraryState> _load({bool forceRefresh = false}) async {
    final preloadGeneration = ++_preloadGeneration;
    final api = ref.read(musicApiProvider);
    final failures = <String, String>{};
    List<MusicPlatformStatus> statuses;
    try {
      statuses = await api.musicPlatforms();
    } on Object catch (error) {
      return MusicPlatformLibraryState(
        failures: <String, String>{
          'platforms': describeUserFacingError(error).message,
        },
      );
    }

    final playlistsByPlatform = <String, List<OnlinePlaylist>>{};
    final likedTracksByPlatform = <String, List<OnlineTrack>>{};
    await Future.wait(
      statuses.where((status) => status.enabled && status.connected).map((
        status,
      ) async {
        // 同平台内歌单与喜欢曲目并行加载，避免串行叠加外部延迟。
        final futures = <Future<void>>[];
        if (status.capabilities.playlists) {
          futures.add(() async {
            try {
              final page = await api.platformPlaylists(
                status.platform,
                refresh: forceRefresh,
              );
              playlistsByPlatform[status
                  .platform] = List<OnlinePlaylist>.unmodifiable(page.items);
            } on Object catch (error) {
              failures['${status.platform}:playlists'] =
                  describeUserFacingError(error).message;
            }
          }());
        }
        if (status.capabilities.likedTracks) {
          futures.add(() async {
            try {
              final page = await api.platformLikedTracks(
                status.platform,
                refresh: forceRefresh,
              );
              likedTracksByPlatform[status
                  .platform] = List<OnlineTrack>.unmodifiable(page.items);
            } on Object catch (error) {
              failures['${status.platform}:liked'] =
                  describeUserFacingError(error).message;
            }
          }());
        }
        await Future.wait(futures);
      }),
    );
    final previous = state.asData?.value;
    final nextState = MusicPlatformLibraryState(
      statuses: List<MusicPlatformStatus>.unmodifiable(statuses),
      playlistsByPlatform: Map<String, List<OnlinePlaylist>>.unmodifiable(
        playlistsByPlatform,
      ),
      likedTracksByPlatform: Map<String, List<OnlineTrack>>.unmodifiable(
        likedTracksByPlatform,
      ),
      // 刷新保留上一轮已加载的歌单曲目：丢掉它们会让封面回退一帧，并让预热
      // 把全部歌单重新回源一遍第三方接口。需要新页由打开歌单时显式强制回源。
      playlistTracks: Map<String, MusicPagedResult<OnlineTrack>>.unmodifiable(
        <String, MusicPagedResult<OnlineTrack>>{...?previous?.playlistTracks},
      ),
      failures: Map<String, String>.unmodifiable(failures),
    );
    final playlists = playlistsByPlatform.values
        .expand((items) => items)
        .toList(growable: false);
    unawaited(
      Future<void>.delayed(
        Duration.zero,
        () => _preloadPlaylistTracks(playlists, preloadGeneration),
      ),
    );
    return nextState;
  }

  Future<void> _preloadPlaylistTracks(
    List<OnlinePlaylist> playlists,
    int generation,
  ) async {
    if (playlists.isEmpty) {
      return;
    }
    // 预热只覆盖前若干歌单：其余按 `loadPlaylistTracks` 的按需路径加载。
    // 每个响应都要在 UI isolate 里反序列化，无上限预热会在平台数据到达后
    // 连续抢占主线程。
    final targets = playlists
        .take(_playlistPreloadLimit)
        .toList(growable: false);
    if (targets.isEmpty || !ref.mounted || generation != _preloadGeneration) {
      return;
    }
    // 先把全部键标记为加载中（一次发布），使预热期间的按需调用复用同一状态，
    // 再合并结果一次性发布：逐个发布会让首页按歌单数量连续整页重建。
    final before = state.asData?.value;
    if (before == null) {
      return;
    }
    final keyed = <String, OnlinePlaylist>{
      for (final playlist in targets)
        // 已缓存的歌单不再回源：刷新时只补新的或缺失的。
        if (!before.playlistTracks.containsKey(
          _playlistKey(playlist.platform, playlist.playlistId),
        ))
          _playlistKey(playlist.platform, playlist.playlistId): playlist,
    };
    if (keyed.isEmpty) {
      return;
    }
    final seqByKey = <String, int>{
      for (final key in keyed.keys) key: _beginTrackRequest(key),
    };
    state = AsyncData(
      before.copyWith(
        loadingPlaylistKeys: <String>{
          ...before.loadingPlaylistKeys,
          ...keyed.keys,
        },
      ),
    );
    var nextIndex = 0;
    final tracksByKey = <String, MusicPagedResult<OnlineTrack>>{};
    final failures = <String, String>{};
    final queue = keyed.entries.toList(growable: false);
    Future<void> worker() async {
      while (ref.mounted &&
          generation == _preloadGeneration &&
          nextIndex < queue.length) {
        final entry = queue[nextIndex++];
        try {
          final page = await ref
              .read(musicApiProvider)
              .platformPlaylistTracks(
                entry.value.platform,
                entry.value.playlistId,
                size: _playlistPreloadTrackPageSize,
              );
          tracksByKey[entry.key] = page;
        } on Object catch (error) {
          failures[entry.key] = describeUserFacingError(error).message;
        }
      }
    }

    final workerCount = queue.length.clamp(1, _playlistPreloadConcurrency);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    if (!ref.mounted || generation != _preloadGeneration) {
      return;
    }
    final latest = state.asData?.value;
    if (latest == null) {
      return;
    }
    // 期间被首屏或整表请求接管的键丢弃预热结果：预热页更小，合并会把
    // 已经加载好的列表截回首页条数。
    final fresh = <String, MusicPagedResult<OnlineTrack>>{
      for (final entry in tracksByKey.entries)
        if (_ownsTrackRequest(entry.key, seqByKey[entry.key]!))
          entry.key: entry.value,
    };
    state = AsyncData(
      latest.copyWith(
        playlistTracks: <String, MusicPagedResult<OnlineTrack>>{
          ...latest.playlistTracks,
          ...fresh,
        },
        loadingPlaylistKeys: <String>{...latest.loadingPlaylistKeys}
          ..removeAll(keyed.keys),
        failures:
            failures.isEmpty
                ? latest.failures
                : <String, String>{...latest.failures, ...failures},
      ),
    );
  }

  String _playlistKey(String platform, String playlistId) {
    return '$platform:$playlistId';
  }
}
