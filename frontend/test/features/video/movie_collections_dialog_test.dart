import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_collections.dart';

void main() {
  testWidgets('合集弹窗在条目数据到达后自动渲染列表', (tester) async {
    final adapter = _CollectionApiAdapter();
    await tester.pumpWidget(_host(adapter));

    await tester.tap(find.text('周末片单'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('盗梦空间'), findsOneWidget);
    expect(find.text('合集为空'), findsNothing);
  });

  testWidgets('空合集弹窗展示空态而不是无限加载', (tester) async {
    final adapter = _CollectionApiAdapter(itemIds: []);
    await tester.pumpWidget(_host(adapter));

    await tester.tap(find.text('周末片单'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('合集为空'), findsOneWidget);
  });

  testWidgets('移除合集条目后弹窗列表即时更新', (tester) async {
    final adapter = _CollectionApiAdapter();
    await tester.pumpWidget(_host(adapter));

    await tester.tap(find.text('周末片单'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('盗梦空间'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(adapter.removeCalls, 1);
    expect(find.text('盗梦空间'), findsNothing);
    expect(find.text('合集为空'), findsOneWidget);
  });

  testWidgets('添加影片入口可在选择器中把电影加入合集', (tester) async {
    // 选择器弹窗较高，默认 600 高视口会把关闭按钮挤出屏幕。
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _CollectionApiAdapter();
    await tester.pumpWidget(_host(adapter));

    await tester.tap(find.text('周末片单'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('添加影片'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('选择影片'), findsOneWidget);
    // 选择器与背后的合集弹窗各渲染一次。
    expect(find.text('盗梦空间'), findsNWidgets(2));
    expect(find.text('泰坦尼克号'), findsOneWidget);
    // 已在合集中的条目置灰打勾。
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('泰坦尼克号'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(adapter.addCalls, 1);
    // 新加入的条目在选择器中同样翻转为已添加。
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    // 叠层弹窗的关闭按钮受路由 offstage 语义影响，直接 pop 顶层选择器路由。
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('盗梦空间'), findsOneWidget);
    expect(find.text('泰坦尼克号'), findsOneWidget);
  });
}

Widget _host(_CollectionApiAdapter adapter) {
  return ProviderScope(
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
    child: MaterialApp(
      theme: OmniNestTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: const Scaffold(
        body: CollectionsSection(
          totalCount: 1,
          collections: [
            MovieCollection(
              id: 'coll-1',
              name: '周末片单',
              collectionType: 'MANUAL',
              itemCount: 1,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CollectionApiAdapter implements HttpClientAdapter {
  _CollectionApiAdapter({List<String> itemIds = const ['movie-1']})
    : _current = List.of(itemIds);

  static const _titles = {'movie-1': '盗梦空间', 'movie-2': '泰坦尼克号'};

  final List<String> _current;
  int removeCalls = 0;
  int addCalls = 0;

  List<Map<String, Object>> get _items => [
    for (final id in _current) _movie(id, _titles[id] ?? id),
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE' &&
        options.path == '/video/collections/coll-1/items/movie-1') {
      removeCalls++;
      _current.remove('movie-1');
      return _ok(<Object>[]);
    }
    if (options.method == 'POST' &&
        options.path == '/video/collections/coll-1/items') {
      addCalls++;
      final raw = options.data;
      final body =
          raw is String
              ? jsonDecode(raw) as Map<String, dynamic>
              : Map<String, dynamic>.from(raw as Map);
      final videoItemId = body['videoItemId'] as String;
      if (!_current.contains(videoItemId)) {
        _current.add(videoItemId);
      }
      return _ok(<Object, Object>{});
    }
    final data = switch (options.path) {
      '/video/collections/coll-1/items' => _items,
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _libraryPage(),
      '/video/series/by-type' => <Object>[],
      _ => throw StateError('未处理的测试请求: ${options.path}'),
    };
    return _ok(data);
  }

  ResponseBody _ok(Object data) {
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
      'items': [
        for (final entry in _titles.entries) _movie(entry.key, entry.value),
      ],
      'page': 0,
      'size': 100,
      'totalElements': _titles.length,
      'totalPages': 1,
    };
  }

  Map<String, Object> _movie(String id, String title) {
    return {
      'id': id,
      'fileNodeId': 'file-$id',
      'mediaType': 'MOVIE',
      'title': title,
      'metadataStatus': 'MATCHED',
      'availabilityStatus': 'AVAILABLE',
    };
  }

  @override
  void close({bool force = false}) {}
}
