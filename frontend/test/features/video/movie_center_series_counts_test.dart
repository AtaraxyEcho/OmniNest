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
  test('初始加载并行预取剧集与动漫系列列表', () async {
    final container = _container();

    final state = await container.read(movieCenterControllerProvider.future);

    expect(state.tvSeries.map((s) => s.id), ['tv-1']);
    expect(state.animeSeries.map((s) => s.id), ['anime-1']);
  });

  test('切换剧集分区只更新剧集列表，动漫列表保持不被覆盖', () async {
    final container = _container();
    container.listen(movieCenterControllerProvider, (_, _) {});
    await container.read(movieCenterControllerProvider.future);

    container
        .read(movieCenterControllerProvider.notifier)
        .selectSection(MovieSection.tvShows);
    final state = await _waitSectionLoaded(container, MovieSection.tvShows);

    expect(state.tvSeries.map((s) => s.id), ['tv-1']);
    expect(state.animeSeries.map((s) => s.id), ['anime-1']);
  });

  test('切换动漫分区只更新动漫列表，剧集列表保持不被覆盖', () async {
    final container = _container();
    container.listen(movieCenterControllerProvider, (_, _) {});
    await container.read(movieCenterControllerProvider.future);

    container
        .read(movieCenterControllerProvider.notifier)
        .selectSection(MovieSection.anime);
    final state = await _waitSectionLoaded(container, MovieSection.anime);

    expect(state.animeSeries.map((s) => s.id), ['anime-1']);
    expect(state.tvSeries.map((s) => s.id), ['tv-1']);
  });
}

/// 等待未 await 的分区加载完成：loadedSections 收录且不在 loadingSections。
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

ProviderContainer _container() {
  final adapter = _SeriesApiAdapter();
  return ProviderContainer.test(
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
}

class _SeriesApiAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _libraryPage(),
      '/video/series/by-type' => _seriesByType(options),
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

  Map<String, Object> _dashboard() {
    return {
      'stats': {
        'movieCount': 1,
        'episodeCount': 0,
        'seriesCount': 2,
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

  List<Object> _seriesByType(RequestOptions options) {
    final seriesType = options.queryParameters['seriesType']?.toString();
    return seriesType == 'ANIME'
        ? [_series('anime-1', 'ANIME')]
        : [_series('tv-1', 'TV')];
  }

  Map<String, Object> _series(String id, String seriesType) {
    return {
      'id': id,
      'title': id,
      'metadataStatus': 'MATCHED',
      'seriesType': seriesType,
      'metadata': <String, Object>{},
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
