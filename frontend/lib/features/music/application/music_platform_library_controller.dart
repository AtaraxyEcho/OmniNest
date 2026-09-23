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

/// 外部音乐平台账号曲库状态。
class MusicPlatformLibraryState {
  const MusicPlatformLibraryState({
    this.statuses = const <MusicPlatformStatus>[],
    this.playlistsByPlatform = const <String, List<OnlinePlaylist>>{},
    this.likedTracksByPlatform = const <String, List<OnlineTrack>>{},
    this.playlistTracks = const <String, List<OnlineTrack>>{},
    this.loadingPlaylistKeys = const <String>{},
    this.failures = const <String, String>{},
  });

  final List<MusicPlatformStatus> statuses;
  final Map<String, List<OnlinePlaylist>> playlistsByPlatform;
  final Map<String, List<OnlineTrack>> likedTracksByPlatform;
  final Map<String, List<OnlineTrack>> playlistTracks;
  final Set<String> loadingPlaylistKeys;
  final Map<String, String> failures;

  /// 返回已连接且可用的平台状态。
  List<MusicPlatformStatus> get connectedStatuses => statuses
      .where((status) => status.enabled && status.connected)
      .toList(growable: false);

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
    final tracks =
        playlistTracks['${playlist.platform}:${playlist.playlistId}'];
    if (tracks != null && tracks.isNotEmpty) {
      final firstTrackCover = tracks.first.coverUrl.trim();
      if (firstTrackCover.isNotEmpty) {
        return firstTrackCover;
      }
    }
    return playlist.coverUrl.trim();
  }

  MusicPlatformLibraryState copyWith({
    List<MusicPlatformStatus>? statuses,
    Map<String, List<OnlinePlaylist>>? playlistsByPlatform,
    Map<String, List<OnlineTrack>>? likedTracksByPlatform,
    Map<String, List<OnlineTrack>>? playlistTracks,
    Set<String>? loadingPlaylistKeys,
    Map<String, String>? failures,
  }) {
    return MusicPlatformLibraryState(
      statuses: statuses ?? this.statuses,
      playlistsByPlatform: playlistsByPlatform ?? this.playlistsByPlatform,
      likedTracksByPlatform:
          likedTracksByPlatform ?? this.likedTracksByPlatform,
      playlistTracks: playlistTracks ?? this.playlistTracks,
      loadingPlaylistKeys: loadingPlaylistKeys ?? this.loadingPlaylistKeys,
      failures: failures ?? this.failures,
    );
  }
}

/// 加载平台状态、账号歌单和喜欢歌曲，并隔离单来源失败。
class MusicPlatformLibraryController
    extends AsyncNotifier<MusicPlatformLibraryState> {
  static const int _playlistPreloadConcurrency = 3;

  /// 预热覆盖的歌单数量上限：超出的部分走按需加载路径。
  static const int _playlistPreloadLimit = 8;

  int _preloadGeneration = 0;

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
    final next = await AsyncValue.guard(_load);
    if (next.hasError && previous != null) {
      state = AsyncData(previous);
      return;
    }
    state = next;
  }

  /// 严格刷新实时事件涉及的平台账号曲库。
  Future<void> refreshForRealtime() async {
    final refreshed = await _load();
    state = AsyncData(refreshed);
  }

  /// 按需加载一个在线歌单的曲目。
  Future<List<OnlineTrack>> loadPlaylistTracks(OnlinePlaylist playlist) async {
    if (!ref.mounted) {
      return const <OnlineTrack>[];
    }
    final current = state.asData?.value;
    if (current == null) {
      return const <OnlineTrack>[];
    }
    final key = _playlistKey(playlist.platform, playlist.playlistId);
    final cached = current.playlistTracks[key];
    if (cached != null) {
      return cached;
    }
    state = AsyncData(
      current.copyWith(
        loadingPlaylistKeys: <String>{...current.loadingPlaylistKeys, key},
      ),
    );
    try {
      final tracks = await ref
          .read(musicApiProvider)
          .platformPlaylistTracks(playlist.platform, playlist.playlistId);
      if (!ref.mounted) {
        return const <OnlineTrack>[];
      }
      final latest = state.asData?.value ?? current;
      state = AsyncData(
        latest.copyWith(
          playlistTracks: <String, List<OnlineTrack>>{
            ...latest.playlistTracks,
            key: List<OnlineTrack>.unmodifiable(tracks),
          },
          loadingPlaylistKeys: <String>{...latest.loadingPlaylistKeys}
            ..remove(key),
        ),
      );
      return tracks;
    } on Object catch (error) {
      if (!ref.mounted) {
        return const <OnlineTrack>[];
      }
      final latest = state.asData?.value ?? current;
      state = AsyncData(
        latest.copyWith(
          loadingPlaylistKeys: <String>{...latest.loadingPlaylistKeys}
            ..remove(key),
          failures: <String, String>{
            ...latest.failures,
            key: describeUserFacingError(error).message,
          },
        ),
      );
      return const <OnlineTrack>[];
    }
  }

  Future<MusicPlatformLibraryState> _load() async {
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
              playlistsByPlatform[status
                  .platform] = List<OnlinePlaylist>.unmodifiable(
                await api.platformPlaylists(status.platform),
              );
            } on Object catch (error) {
              failures['${status.platform}:playlists'] =
                  describeUserFacingError(error).message;
            }
          }());
        }
        if (status.capabilities.likedTracks) {
          futures.add(() async {
            try {
              likedTracksByPlatform[status
                  .platform] = List<OnlineTrack>.unmodifiable(
                await api.platformLikedTracks(status.platform),
              );
            } on Object catch (error) {
              failures['${status.platform}:liked'] =
                  describeUserFacingError(error).message;
            }
          }());
        }
        await Future.wait(futures);
      }),
    );
    final nextState = MusicPlatformLibraryState(
      statuses: List<MusicPlatformStatus>.unmodifiable(statuses),
      playlistsByPlatform: Map<String, List<OnlinePlaylist>>.unmodifiable(
        playlistsByPlatform,
      ),
      likedTracksByPlatform: Map<String, List<OnlineTrack>>.unmodifiable(
        likedTracksByPlatform,
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
    state = AsyncData(
      before.copyWith(
        loadingPlaylistKeys: <String>{
          ...before.loadingPlaylistKeys,
          ...keyed.keys,
        },
      ),
    );
    var nextIndex = 0;
    final tracksByKey = <String, List<OnlineTrack>>{};
    final failures = <String, String>{};
    final queue = keyed.entries.toList(growable: false);
    Future<void> worker() async {
      while (ref.mounted &&
          generation == _preloadGeneration &&
          nextIndex < queue.length) {
        final entry = queue[nextIndex++];
        try {
          final tracks = await ref
              .read(musicApiProvider)
              .platformPlaylistTracks(
                entry.value.platform,
                entry.value.playlistId,
              );
          tracksByKey[entry.key] = List<OnlineTrack>.unmodifiable(tracks);
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
    state = AsyncData(
      latest.copyWith(
        playlistTracks: <String, List<OnlineTrack>>{
          ...latest.playlistTracks,
          ...tracksByKey,
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
