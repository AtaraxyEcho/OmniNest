import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_track_filter.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

final musicDeckSearchProvider = NotifierProvider.autoDispose<
  MusicDeckSearchController,
  MusicDeckSearchState
>(MusicDeckSearchController.new);

/// Music Deck 搜索状态。
class MusicDeckSearchState {
  const MusicDeckSearchState({
    this.query = '',
    this.sources = const <MusicPlatform>{MusicPlatform.local},
    this.results = const <MusicPlatform, List<MusicPlayableItem>>{},
    this.loadingSources = const <MusicPlatform>{},
    this.failures = const <MusicPlatform, String>{},
  });

  final String query;
  final Set<MusicPlatform> sources;
  final Map<MusicPlatform, List<MusicPlayableItem>> results;
  final Set<MusicPlatform> loadingSources;
  final Map<MusicPlatform, String> failures;

  bool get visible => query.trim().length >= 2;

  MusicDeckSearchState copyWith({
    String? query,
    Set<MusicPlatform>? sources,
    Map<MusicPlatform, List<MusicPlayableItem>>? results,
    Set<MusicPlatform>? loadingSources,
    Map<MusicPlatform, String>? failures,
  }) {
    return MusicDeckSearchState(
      query: query ?? this.query,
      sources: sources ?? this.sources,
      results: results ?? this.results,
      loadingSources: loadingSources ?? this.loadingSources,
      failures: failures ?? this.failures,
    );
  }
}

/// 对本地和在线来源执行可取消、可丢弃迟到结果的歌曲搜索。
class MusicDeckSearchController extends Notifier<MusicDeckSearchState> {
  Timer? _debounce;
  final Map<MusicPlatform, CancelToken> _cancelTokens =
      <MusicPlatform, CancelToken>{};
  int _generation = 0;

  @override
  MusicDeckSearchState build() {
    ref.onDispose(() {
      _generation++;
      _debounce?.cancel();
      _cancelPending();
    });
    return const MusicDeckSearchState();
  }

  /// 更新搜索词和当前来源筛选。
  void updateQuery(String query, Set<MusicPlatform> sources) {
    _debounce?.cancel();
    _cancelPending();
    _generation++;
    final normalizedSources = Set<MusicPlatform>.unmodifiable(sources);
    state = MusicDeckSearchState(query: query, sources: normalizedSources);
    if (query.trim().length < 2 || normalizedSources.isEmpty) {
      return;
    }
    final generation = _generation;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_search(query.trim(), normalizedSources, generation));
    });
  }

  /// 清空搜索状态并取消未完成请求。
  void clear() {
    _debounce?.cancel();
    _cancelPending();
    _generation++;
    state = const MusicDeckSearchState();
  }

  Future<void> _search(
    String query,
    Set<MusicPlatform> sources,
    int generation,
  ) async {
    final center = ref.read(musicCenterControllerProvider).asData?.value;
    if (center == null || generation != _generation) {
      return;
    }
    final platformLibrary =
        ref.read(musicPlatformLibraryProvider).asData?.value ??
        const MusicPlatformLibraryState();
    final connectedPlatforms =
        platformLibrary.connectedStatuses
            .where((status) => status.capabilities.search)
            .map((status) => status.platform)
            .toSet();
    final loading = <MusicPlatform>{
      for (final source in sources)
        if (source != MusicPlatform.local &&
            connectedPlatforms.contains(source.apiValue))
          source,
    };
    state = state.copyWith(
      loadingSources: Set<MusicPlatform>.unmodifiable(loading),
    );

    final results = <MusicPlatform, List<MusicPlayableItem>>{};
    final failures = <MusicPlatform, String>{};
    if (sources.contains(MusicPlatform.local)) {
      results[MusicPlatform.local] = filterLoadedTracks(
        center.tracks,
        query,
      ).take(40).map(MusicPlayableItem.local).toList(growable: false);
    }

    await Future.wait(
      loading.map((platform) async {
        final token = CancelToken();
        _cancelTokens[platform] = token;
        try {
          final tracks = await ref
              .read(musicApiProvider)
              .onlineSearch(
                query,
                limit: 30,
                platform: platform.apiValue,
                cancelToken: token,
              );
          results[platform] = tracks
              .map(MusicPlayableItem.online)
              .toList(growable: false);
        } on DioException catch (error) {
          if (!CancelToken.isCancel(error)) {
            failures[platform] = describeUserFacingError(error).message;
          }
        } on Exception catch (error) {
          failures[platform] = describeUserFacingError(error).message;
        } finally {
          if (identical(_cancelTokens[platform], token)) {
            _cancelTokens.remove(platform);
          }
        }
      }),
    );
    if (generation != _generation) {
      return;
    }
    state = MusicDeckSearchState(
      query: query,
      sources: sources,
      results: Map<MusicPlatform, List<MusicPlayableItem>>.unmodifiable(
        results,
      ),
      failures: Map<MusicPlatform, String>.unmodifiable(failures),
    );
  }

  void _cancelPending() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('搜索条件已更新');
      }
    }
    _cancelTokens.clear();
  }
}
