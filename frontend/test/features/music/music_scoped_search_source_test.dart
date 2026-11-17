// 音乐档来源回归：走 `/music/search?q=` 的服务端全库检索，不再只筛已加载列表；
// 服务端结果原样透出、无翻页语义、空白查询不打接口，结果行落回音乐空间。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_scoped_search_source.dart';
import 'package:omninest/features/music/data/music_api.dart';

class _SearchAdapter implements HttpClientAdapter {
  _SearchAdapter(this.tracks);

  /// `/music/search` 返回的曲目投影。
  final List<Map<String, Object>> tracks;

  String? lastPath;
  Map<String, dynamic>? lastParams;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/music/search') {
      requestCount++;
      lastPath = options.path;
      lastParams = options.queryParameters;
    }
    final data =
        options.path == '/music/search'
            ? <String, Object>{
              'tracks': tracks,
              'albums': <Object>[],
              'artists': <Object>[],
            }
            : <Object>[];
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> _trackJson(String id, String title, String artist) {
  return <String, Object>{
    'id': id,
    'fileNodeId': 'file-$id',
    'title': title,
    'artistName': artist,
    'albumTitle': 'Evening Drift',
    'format': 'FLAC',
    'favorite': false,
  };
}

Future<Ref> _open(_SearchAdapter adapter) async {
  final container = ProviderContainer.test(
    overrides: [
      musicApiProvider.overrideWithValue(
        MusicApi(
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
  final capture = Provider<Ref>((ref) => ref);
  return container.read(capture);
}

void main() {
  const source = MusicScopedSearchSource();

  test('关键词进服务端检索并映射到音乐空间', () async {
    final adapter = _SearchAdapter(<Map<String, Object>>[
      _trackJson('t-1', 'Amber', 'Marconi Union'),
    ]);

    final results = await source.search(await _open(adapter), 'amber');

    expect(adapter.lastPath, '/music/search');
    expect(adapter.lastParams, <String, Object>{'q': 'amber', 'type': 'all'});
    expect(results, hasLength(1));
    expect(results.single.title, 'Amber');
    expect(results.single.subtitle, 'Marconi Union · Evening Drift');
    expect(results.single.detailRoute, '/music');
    expect(results.single.scope, ScopedSearchId.music);
  });

  test('服务端结果原样透出，不叠加本地二次过滤', () async {
    // 标题不含关键词、靠歌手命中的曲目：本地复筛会把它删掉。
    final adapter = _SearchAdapter(<Map<String, Object>>[
      _trackJson('t-1', 'Zeta', 'Amber Lines'),
    ]);

    final results = await source.search(await _open(adapter), 'amber');

    expect(results.map((item) => item.title), <String>['Zeta']);
  });

  test('第二页起不发请求，让加载更多停止', () async {
    final adapter = _SearchAdapter(<Map<String, Object>>[]);

    final results = await source.search(await _open(adapter), 'amber', page: 1);

    expect(results, isEmpty);
    expect(adapter.requestCount, 0);
  });

  test('空白查询不打检索接口', () async {
    final adapter = _SearchAdapter(<Map<String, Object>>[]);

    final results = await source.search(await _open(adapter), '   ');

    expect(results, isEmpty);
    expect(adapter.requestCount, 0);
  });
}
