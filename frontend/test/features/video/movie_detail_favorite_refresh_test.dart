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
import 'package:omninest/features/video/presentation/pages/movie_detail_page.dart';

void main() {
  testWidgets('详情页收藏走控制器并触发中心数据回调刷新', (tester) async {
    final adapter = _FavoriteApiAdapter();
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
          movieDetailProvider('video-1').overrideWith((ref) async => _item),
          videoFavoriteStatusProvider(
            'video-1',
          ).overrideWith((ref) async => false),
          authSessionProvider.overrideWith(() => _AdminSessionNotifier()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const MovieDetailPage(videoItemId: 'video-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_outline_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(adapter.favoriteCalls, 1);
    // 初始 build 一次 + toggleFavorite 内 refresh 一次：回调刷新确实发生。
    expect(adapter.dashboardRequests, 2);
    // 收藏状态提供器被失效重取，星星变为点亮态。
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}

final MovieVideoItem _item = MovieVideoItem(
  id: 'video-1',
  fileNodeId: 'file-1',
  mediaType: 'MOVIE',
  title: 'Inception',
  metadataStatus: 'MATCHED',
  nfoStatus: 'READY',
  updatedAt: DateTime(2024, 6, 1),
  metadata: const <String, dynamic>{},
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

class _FavoriteApiAdapter implements HttpClientAdapter {
  bool _favorited = false;
  int favoriteCalls = 0;
  int dashboardRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/video/items/video-1/favorite') {
      favoriteCalls++;
      _favorited = options.queryParameters['favorite'] == 'true';
      return _ok({'videoItemId': 'video-1', 'favorite': _favorited});
    }
    if (options.path == '/video/items/video-1/favorite/status') {
      return _ok({'videoItemId': 'video-1', 'favorite': _favorited});
    }
    final data = switch (options.path) {
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _libraryPage(),
      '/video/series/by-type' => <Object>[],
      '/video/favorites' => <Object>[],
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
      'items': <Object>[
        {
          'id': 'video-1',
          'fileNodeId': 'file-1',
          'mediaType': 'MOVIE',
          'title': 'Inception',
          'metadataStatus': 'MATCHED',
          'availabilityStatus': 'AVAILABLE',
        },
      ],
      'page': 0,
      'size': 36,
      'totalElements': 1,
      'totalPages': 1,
    };
  }

  @override
  void close({bool force = false}) {}
}
