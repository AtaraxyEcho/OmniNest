// 托管影视页内搜索条回归：玻璃横幅搜索钮展开样例输入胶囊，查询写入
// 中心控制器（防抖后），收起即清空；此前搜索钮只弹不查询。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';

class _LibraryAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _page(),
      '/video/series/by-type/page' => _page(),
      _ => <Object>[],
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
        'seriesCount': 0,
        'scrapeFailedCount': 0,
      },
      'recentlyAdded': <Object>[],
      'continueWatching': <Object>[],
      'series': <Object>[],
    };
  }

  Map<String, Object> _page() {
    return {
      'items': <Object>[
        {
          'id': 'movie-1',
          'fileNodeId': 'file-movie-1',
          'mediaType': 'MOVIE',
          'title': 'Mirage',
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

Future<ProviderContainer> _pumpHostedShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer.test(
    overrides: [
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
      movieApiProvider.overrideWithValue(
        MovieApi(
          ApiClient(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost:8080/api/v1',
              wsBaseUrl: 'ws://localhost:8080/ws',
            ),
            httpClientAdapter: _LibraryAdapter(),
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const MobileShellScope(
          hosted: true,
          child: Scaffold(
            backgroundColor: Color(0xFF0B1110),
            // 页面级泵入：搜索查询写入中心控制器，需要真实的构建链路。
            body: MovieCenterPage(initialSection: MovieSection.movies),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  const queryDebounce = Duration(milliseconds: 350);

  testWidgets('搜索钮展开页内玻璃搜索条而不是弹窗', (tester) async {
    await _pumpHostedShell(tester);

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入经防抖写入分区查询，收起即清空', (tester) async {
    final container = await _pumpHostedShell(tester);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'mirage');
    await tester.pump(queryDebounce);
    expect(
      container.read(movieCenterControllerProvider).requireValue.searchQuery,
      'mirage',
    );

    await tester.tap(find.byTooltip('关闭'));
    // 清空与输入同走防抖通道：条收起后 300ms 内列表回全量。
    await tester.pump(queryDebounce);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      container.read(movieCenterControllerProvider).requireValue.searchQuery,
      '',
    );
    expect(tester.takeException(), isNull);
  });
}
