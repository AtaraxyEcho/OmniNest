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
    final adapter = _CollectionApiAdapter(
      items: [_movie('movie-1', '盗梦空间')],
    );
    await tester.pumpWidget(_host(adapter));

    await tester.tap(find.text('周末片单'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('盗梦空间'), findsOneWidget);
    expect(find.text('合集为空'), findsNothing);
  });

  testWidgets('空合集弹窗展示空态而不是无限加载', (tester) async {
    final adapter = _CollectionApiAdapter(items: const []);
    await tester.pumpWidget(_host(adapter));

    await tester.tap(find.text('周末片单'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('合集为空'), findsOneWidget);
  });

  testWidgets('移除合集条目后弹窗列表即时更新', (tester) async {
    final adapter = _CollectionApiAdapter(
      items: [_movie('movie-1', '盗梦空间')],
    );
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

class _CollectionApiAdapter implements HttpClientAdapter {
  _CollectionApiAdapter({required List<Map<String, Object>> items})
    : _items = List.of(items);

  List<Map<String, Object>> _items;
  int removeCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE' &&
        options.path == '/video/collections/coll-1/items/movie-1') {
      removeCalls++;
      _items.clear();
      return _ok(<Object>[]);
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
      'items': <Object>[_movie('movie-1', '盗梦空间')],
      'page': 0,
      'size': 36,
      'totalElements': 1,
      'totalPages': 1,
    };
  }

  @override
  void close({bool force = false}) {}
}
