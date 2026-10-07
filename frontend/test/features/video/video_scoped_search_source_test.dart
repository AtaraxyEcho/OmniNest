// 影视档来源回归：关键词必须进请求（覆盖全库，而不是本地过滤已加载分页），
// 结果映射到影视详情路由。原页内搜索条用例撤除后，这条覆盖由本文件承接。
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

class _LibraryAdapter implements HttpClientAdapter {
  /// 最近一次 `/video/library/page` 收到的 `q`。
  String? lastLibraryKeyword;
  int? lastPage;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/video/library/page') {
      requestCount++;
      lastLibraryKeyword = options.queryParameters['q'] as String?;
      lastPage = options.queryParameters['page'] as int?;
    }
    final data = options.path == '/video/library/page' ? _page() : _empty();
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, Object> _page() {
    return <String, Object>{
      'items': <Map<String, Object>>[
        <String, Object>{
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
          'posterUrl': 'https://cdn.example.test/v-1.jpg',
        },
      ],
      'page': 0,
      'size': ScopedSearchLimits.perSource,
      'totalElements': 1,
      'totalPages': 1,
    };
  }

  Map<String, Object> _empty() {
    return <String, Object>{
      'stats': <String, Object>{
        'movieCount': 0,
        'episodeCount': 0,
        'seriesCount': 0,
        'scrapeFailedCount': 0,
      },
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
  test('关键词进请求并映射到影视详情路由', () async {
    final (adapter, container) = _openContainer();

    final results = await const VideoScopedSearchSource().search(
      _captureRef(container),
      'mirage',
    );

    expect(adapter.lastLibraryKeyword, 'mirage');
    expect(results, hasLength(1));
    expect(results.single.title, 'Mirage');
    expect(results.single.scope, ScopedSearchId.video);
    expect(results.single.detailRoute, '/video/v-1');
    expect(results.single.subtitle, '2024 · 122 min · ★ 8.1');
  });

  test('分页号透传给数据侧，加载更多换页而不是本地翻页', () async {
    final (adapter, container) = _openContainer();

    await const VideoScopedSearchSource().search(
      _captureRef(container),
      'mirage',
      page: 2,
    );

    expect(adapter.lastPage, 2);
    expect(adapter.requestCount, 1);
  });

  test('空白查询不发请求', () async {
    final (adapter, container) = _openContainer();

    final results = await const VideoScopedSearchSource().search(
      _captureRef(container),
      '   ',
    );

    expect(results, isEmpty);
    expect(adapter.requestCount, 0);
  });
}
