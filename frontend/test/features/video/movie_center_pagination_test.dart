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
  test(
    'movie center loads a bounded first page and deduplicates next page',
    () async {
      final adapter = _MovieLibraryAdapter();
      final api = MovieApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );
      final container = ProviderContainer.test(
        overrides: [movieApiProvider.overrideWithValue(api)],
      );

      final first = await container.read(movieCenterControllerProvider.future);

      expect(first.movies.map((item) => item.id), ['movie-1']);
      expect(first.movieHasMore, isTrue);
      // 初始加载现会并行预取剧集/动漫系列列表。
      expect(adapter.requestedPaths.take(2), [
        '/video/dashboard',
        '/video/library/page',
      ]);
      expect(
        adapter.requestedPaths.skip(2).toSet().difference({
          '/video/series/by-type',
        }),
        isEmpty,
      );

      await container
          .read(movieCenterControllerProvider.notifier)
          .loadNextLibraryPage();
      final next = container.read(movieCenterControllerProvider).requireValue;

      expect(next.movies.map((item) => item.id), ['movie-1', 'movie-2']);
      expect(next.movieHasMore, isFalse);
      expect(adapter.requestedPages, [0, 1]);
    },
  );
}

class _MovieLibraryAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = [];
  final List<int> requestedPages = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    final data = switch (options.path) {
      '/video/dashboard' => {
        'stats': {
          'movieCount': 2,
          'episodeCount': 0,
          'seriesCount': 0,
          'scrapeFailedCount': 0,
        },
        'recentlyAdded': <Object>[],
        'continueWatching': <Object>[],
        'series': <Object>[],
      },
      '/video/library/page' => _libraryPage(options),
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

  Map<String, Object> _libraryPage(RequestOptions options) {
    final page = int.tryParse(options.queryParameters['page'].toString()) ?? 0;
    requestedPages.add(page);
    final items =
        page == 0
            ? [_movie('movie-1')]
            : [_movie('movie-1'), _movie('movie-2')];
    return {
      'items': items,
      'page': page,
      'size': 36,
      'totalElements': 2,
      'totalPages': 2,
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
