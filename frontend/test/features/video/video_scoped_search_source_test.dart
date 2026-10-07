// 影视档来源回归：关键词要同时进影片页与两种类型的系列页（覆盖全库，而不是本地
// 过滤已加载分页），档内份额 10/5/5 让系列不会被影片挤光，结果按粒度映射详情路由。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/video_scoped_search_source.dart';
import 'package:omninest/features/video/data/movie_api.dart';

class _CapturedRequest {
  _CapturedRequest(this.path, this.params);

  final String path;
  final Map<String, dynamic> params;

  String? get keyword => params['q'] as String?;

  String? get seriesType => params['seriesType'] as String?;

  int? get page => params['page'] as int?;

  int? get size => params['size'] as int?;
}

class _LibraryAdapter implements HttpClientAdapter {
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  /// 每个粒度返回的条数，用来验证档内份额。
  int movieItemCount = 1;
  int seriesItemCount = 1;

  List<_CapturedRequest> get seriesRequests => requests
      .where((request) => request.path == '/video/series/by-type/page')
      .toList(growable: false);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final params = options.queryParameters;
    if (options.path == '/video/library/page' ||
        options.path == '/video/series/by-type/page') {
      requests.add(_CapturedRequest(options.path, params));
    }
    final Object data;
    if (options.path == '/video/library/page') {
      final movie = <String, Object>{
        'id': 'v-1',
        'fileNodeId': 'n-1',
        'mediaType': 'MOVIE',
        'title': 'Mirage',
        'metadataStatus': 'READY',
        'nfoStatus': 'NONE',
        'updatedAt': '2026-10-01T00:00:00Z',
        'releaseDate': '2024-04-01',
        'rating': 8.1,
        'runtimeSeconds': 7320,
      };
      data = _page(
        List<Map<String, Object>>.generate(
          movieItemCount,
          (index) => <String, Object>{...movie, 'id': 'v-$index'},
        ),
      );
    } else if (options.path == '/video/series/by-type/page') {
      final seriesType = params['seriesType'] == 'ANIME' ? 'anime' : 'tv';
      data = _page(
        List<Map<String, Object>>.generate(
          seriesItemCount,
          (index) => <String, Object>{
            'id': 's-$seriesType-$index',
            'title': 'Northern Drift $seriesType $index',
            'seriesType': params['seriesType'],
            'metadataStatus': 'READY',
            'firstAirDate': '2019-06-01',
            'rating': 8.6,
          },
        ),
      );
    } else {
      data = _empty();
    }
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, Object> _page(List<Map<String, Object>> items) {
    return <String, Object>{
      'items': items,
      'page': 0,
      'size': ScopedSearchLimits.perSource,
      'totalElements': items.length,
      'totalPages': 1,
    };
  }

  Map<String, Object> _empty() {
    return <String, Object>{
      'stats': <String, Object>{},
      'recentlyAdded': <Object>[],
      'continueWatching': <Object>[],
      'series': <Object>[],
    };
  }

  @override
  void close({bool force = false}) {}
}

/// 建好带捕获适配器的容器并注册销毁；riverpod 3 不导出 Override 类型，
/// 因此把覆盖项就地组在这里，不再向外传。
(_LibraryAdapter, ProviderContainer) _openContainer() {
  final adapter = _LibraryAdapter();
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
  addTearDown(container.dispose);
  return (adapter, container);
}

Ref _captureRef(ProviderContainer container) {
  final capture = Provider<Ref>((ref) => ref);
  return container.read(capture);
}

void main() {
  test('关键词进影片页与两种类型系列页，并按粒度映射详情路由', () async {
    final (adapter, container) = _openContainer();

    final results = await const VideoScopedSearchSource().search(
      _captureRef(container),
      'mirage',
    );

    expect(adapter.requests.map((request) => request.keyword), <String>[
      'mirage',
      'mirage',
      'mirage',
    ]);
    expect(
      adapter.seriesRequests.map((request) => request.seriesType),
      <String>['TV', 'ANIME'],
    );
    expect(results.map((item) => item.detailRoute), <String>[
      '/video/v-0',
      '/video/series/s-tv-0',
      '/video/series/s-anime-0',
    ]);
    expect(results.every((item) => item.scope == ScopedSearchId.video), isTrue);
    expect(results[0].subtitle, '2024 · 122 min · ★ 8.1');
    expect(results[1].subtitle, '2019 · ★ 8.6');
  });

  test('档内份额 10/5/5：影片占满时系列仍有位置', () async {
    final (adapter, container) = _openContainer();
    adapter.movieItemCount = 10;
    adapter.seriesItemCount = 5;

    final results = await const VideoScopedSearchSource().search(
      _captureRef(container),
      'mirage',
    );

    expect(adapter.requests.map((request) => request.size), <int>[10, 5, 5]);
    expect(results, hasLength(ScopedSearchLimits.perSource));
    expect(
      results.where((item) => item.detailRoute.startsWith('/video/series/')),
      hasLength(10),
    );
  });

  test('分页号透传给三个请求，加载更多换页而不是本地翻页', () async {
    final (adapter, container) = _openContainer();

    await const VideoScopedSearchSource().search(
      _captureRef(container),
      'mirage',
      page: 2,
    );

    expect(adapter.requests.map((request) => request.page), <int>[2, 2, 2]);
  });

  test('空白查询不发请求', () async {
    final (adapter, container) = _openContainer();

    final results = await const VideoScopedSearchSource().search(
      _captureRef(container),
      '   ',
    );

    expect(results, isEmpty);
    expect(adapter.requests, isEmpty);
  });
}
