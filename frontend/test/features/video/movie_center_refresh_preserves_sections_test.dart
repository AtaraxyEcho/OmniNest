import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';

void main() {
  test('refresh 保留懒加载分区列表，重进分区时重新拉取', () async {
    final adapter = _RefreshApiAdapter();
    final container = ProviderContainer.test(
      overrides: [
        movieApiProvider.overrideWithValue(
          MovieApi(
            ApiClient(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                wsBaseUrl: 'ws://localhost:8080/ws',
              ),
              httpClientAdapter: adapter,
            ),
          ),
        ),
      ],
    );
    container.listen(movieCenterControllerProvider, (_, _) {});
    await container.read(movieCenterControllerProvider.future);

    container
        .read(movieCenterControllerProvider.notifier)
        .selectSection(MovieSection.favorites);
    final loaded = await _waitSectionLoaded(container, MovieSection.favorites);
    expect(loaded.favoriteItems.map((item) => item.id), ['movie-1']);
    expect(adapter.favoritesRequests, 1);

    container
        .read(movieCenterControllerProvider.notifier)
        .selectSection(MovieSection.movies);
    await container.read(movieCenterControllerProvider.notifier).refresh();

    final afterRefresh =
        container.read(movieCenterControllerProvider).requireValue;
    // 刷新后未在展示的收藏列表保留旧值，不再被清成空列表。
    expect(afterRefresh.favoriteItems.map((item) => item.id), ['movie-1']);
    expect(afterRefresh.favoriteSeries.map((item) => item.id), ['series-1']);
    expect(afterRefresh.loadedSections, {MovieSection.movies});

    // loadedSections 已重置：重进收藏分区必须重新拉取。
    container
        .read(movieCenterControllerProvider.notifier)
        .selectSection(MovieSection.favorites);
    await _waitSectionLoaded(container, MovieSection.favorites);
    expect(adapter.favoritesRequests, 2);
  });
}

Future<MovieCenterState> _waitSectionLoaded(
  ProviderContainer container,
  MovieSection section,
) async {
  for (var i = 0; i < 100; i++) {
    await pumpEventQueue();
    final state = container.read(movieCenterControllerProvider).asData?.value;
    if (state != null &&
        state.loadedSections.contains(section) &&
        !state.loadingSections.contains(section)) {
      return state;
    }
  }
  fail('分区 $section 未在事件队列排空后完成加载');
}

class _RefreshApiAdapter implements HttpClientAdapter {
  int favoritesRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/video/favorites' => _favorites(),
      '/video/favorites/series' => <Object>[_series('series-1')],
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _libraryPage(),
      '/video/series/by-type' => <Object>[],
      _ => throw StateError('未处理的测试请求: ${options.path}'),
    };
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  List<Object> _favorites() {
    favoritesRequests++;
    return [_movie('movie-1')];
  }

  Map<String, Object> _series(String id) {
    return {
      'id': id,
      'title': id,
      'metadataStatus': 'MATCHED',
      'seriesType': 'TV',
      'metadata': <String, Object>{},
    };
  }

  Map<String, Object> _dashboard() {
    return {
      'stats': {
        'movieCount': 1,
        'episodeCount': 0,
        'seriesCount': 0,
        'scrapeFailedCount': 0,
      },
      'recentlyAdded': <Object>[],
      'continueWatching': <Object>[],
      'series': <Object>[],
    };
  }

  Map<String, Object> _libraryPage() {
    return {
      'items': <Object>[_movie('movie-1')],
      'page': 0,
      'size': 36,
      'totalElements': 1,
      'totalPages': 1,
    };
  }

  Map<String, Object> _movie(String id) {
    return {
      'id': id,
      'fileNodeId': 'file-$id',
      'mediaType': 'MOVIE',
      'title': id,
      'metadataStatus': 'MATCHED',
      'availabilityStatus': 'AVAILABLE',
    };
  }

  @override
  void close({bool force = false}) {}
}
