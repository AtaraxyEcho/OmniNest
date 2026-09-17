import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/series_detail_page.dart';

void main() {
  testWidgets('系列详情页 EDIT 可编辑标题并触发中心数据回调刷新', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _SeriesApiAdapter();
    await tester.pumpWidget(
      ProviderScope(
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
          movieSeriesDetailProvider(
            'series-1',
          ).overrideWith((ref) async => _detail),
          seriesFavoriteProvider('series-1').overrideWith((ref) async => false),
          authSessionProvider.overrideWith(() => _AdminSessionNotifier()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SeriesDetailPage(seriesId: 'series-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, '新标题');
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(adapter.metadataCalls, 1);
    // 初始 build 一次 + updateSeriesMetadata 内 refresh 一次。
    expect(adapter.dashboardRequests, 2);
  });
}

final MovieSeries _series = MovieSeries(
  id: 'series-1',
  title: 'Old Title',
  metadataStatus: 'MATCHED',
  overview: '旧的简介',
  metadata: const <String, dynamic>{},
);

final MovieSeriesDetail _detail = MovieSeriesDetail(
  series: _series,
  seasons: const [],
  cast: const [],
  crew: const [],
);

class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-1',
      username: 'admin',
      role: 'ADMIN',
      permissions: const <String>{'media:write'},
    ),
  );
}

class _SeriesApiAdapter implements HttpClientAdapter {
  int metadataCalls = 0;
  int dashboardRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'PUT' &&
        options.path == '/admin/video/series/series-1/metadata') {
      metadataCalls++;
      return _ok(<String, Object>{
        'id': 'series-1',
        'title': '新标题',
        'metadataStatus': 'MATCHED',
        'seriesType': 'TV',
        'metadata': <String, Object>{},
      });
    }
    final data = switch (options.path) {
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _libraryPage(),
      '/video/series/by-type' => <Object>[],
      '/video/favorites' => <Object>[],
      '/video/favorites/series' => <Object>[],
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
    dashboardRequests++;
    return {
      'stats': {
        'movieCount': 0,
        'episodeCount': 0,
        'seriesCount': 1,
        'scrapeFailedCount': 0,
      },
      'recentlyAdded': <Object>[],
      'continueWatching': <Object>[],
      'series': <Object>[],
    };
  }

  Map<String, Object> _libraryPage() {
    return {
      'items': <Object>[],
      'page': 0,
      'size': 36,
      'totalElements': 0,
      'totalPages': 0,
    };
  }

  @override
  void close({bool force = false}) {}
}
