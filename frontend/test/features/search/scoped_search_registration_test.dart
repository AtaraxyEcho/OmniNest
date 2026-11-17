// 组合根与文件档来源回归：覆盖层换成注册表驱动后，`/search` 的文件全文命中
// 必须仍在（这是原本唯一能返回的结果），且落点不越 feature 边界。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/scoped_search_registration.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/search/scoped_search_registry.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/search/application/file_scoped_search_source.dart';
import 'package:omninest/features/search/application/search_controller.dart';
import 'package:omninest/features/search/data/search_api.dart';

class _FileHitsAdapter implements HttpClientAdapter {
  String? lastPath;
  Map<String, dynamic>? lastParams;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastParams = options.queryParameters;
    return ResponseBody.fromString(
      jsonEncode({
        'code': 200,
        'message': 'success',
        'data': <Map<String, Object>>[
          <String, Object>{
            'id': 'file-1',
            'title': '维修手册.pdf',
            'subtitle': '正文命中：液压',
            'type': 'file',
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 取一个活的 [Ref] 给来源用：来源签名要求 Ref，测试里不经过 provider 拿不到。
Ref _captureRef(ProviderContainer container) {
  final capture = Provider<Ref>((ref) => ref);
  return container.read(capture);
}

void main() {
  setUp(ScopedSearchRegistry.clearForTest);
  tearDown(ScopedSearchRegistry.clearForTest);

  test('组合根登记影视/相册/文件三档，文件档不得失踪', () {
    registerScopedSearchSources();

    expect(
      ScopedSearchRegistry.sources.map((source) => source.scope),
      containsAll(<ScopedSearchId>[
        ScopedSearchId.video,
        ScopedSearchId.photo,
        ScopedSearchId.file,
      ]),
      reason: '覆盖层原先只返回文件全文命中，换数据源后这一档不能静默消失',
    );
  });

  test('文件档走 /search 并回到文件浏览器', () async {
    final adapter = _FileHitsAdapter();
    final container = ProviderContainer.test(
      overrides: [
        searchApiProvider.overrideWithValue(
          SearchApi(
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

    final results = await const FileScopedSearchSource().search(
      _captureRef(container),
      '液压',
    );

    expect(adapter.lastPath, '/search');
    expect(adapter.lastParams, <String, Object>{
      'q': '液压',
      'limit': ScopedSearchLimits.perSource,
    });
    expect(results, hasLength(1));
    expect(results.single.title, '维修手册.pdf');
    expect(results.single.subtitle, '正文命中：液压');
    expect(results.single.detailRoute, '/files');
    expect(results.single.scope, ScopedSearchId.file);
  });

  test('文件档全文接口不分页，第二页起为空让加载更多停止', () async {
    final adapter = _FileHitsAdapter();
    final container = ProviderContainer.test(
      overrides: [
        searchApiProvider.overrideWithValue(
          SearchApi(
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

    final results = await const FileScopedSearchSource().search(
      _captureRef(container),
      '液压',
      page: 1,
    );

    expect(results, isEmpty);
    expect(adapter.lastPath, isNull, reason: '第二页不该再打全文索引接口');
  });

  test('空白查询不发请求', () async {
    final adapter = _FileHitsAdapter();
    final container = ProviderContainer.test(
      overrides: [
        searchApiProvider.overrideWithValue(
          SearchApi(
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

    final results = await const FileScopedSearchSource().search(
      _captureRef(container),
      '   ',
    );

    expect(results, isEmpty);
    expect(adapter.lastPath, isNull);
  });
}
