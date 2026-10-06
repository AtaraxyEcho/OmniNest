// 影视托管空态形态回归：库内无条目时落样例 `.empty-action` 玻璃空态族，
// 不再落工位重设计卡；同时守住空态在托管内容列内不产生布局溢出。
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
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_empty_state.dart';

class _EmptyLibraryAdapter implements HttpClientAdapter {
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

  Map<String, Object> _page() {
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

Future<void> _pumpHostedLibrary(
  WidgetTester tester, {
  required MovieSection section,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        movieApiProvider.overrideWithValue(
          MovieApi(
            ApiClient(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                wsBaseUrl: 'ws://localhost:8080/ws',
              ),
              httpClientAdapter: _EmptyLibraryAdapter(),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: _HostedShell(child: MovieCenterPage(initialSection: section)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 空壳只挂托管标记并铺环境底色，与 `MobileHostedRoute` 同形态。
class _HostedShell extends StatelessWidget {
  const _HostedShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MobileShellScope(
      hosted: true,
      child: Scaffold(backgroundColor: const Color(0xFF0B1110), body: child),
    );
  }
}

void main() {
  testWidgets('托管 For you 空库走玻璃空态且不溢出', (tester) async {
    await _pumpHostedLibrary(tester, section: MovieSection.continueWatching);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.byType(MovieRedesignEmptyState), findsNothing);
    expect(find.text('这里还没有媒体条目。'), findsOneWidget);
    expect(find.text('开始观看后记录将在此显示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('托管 Films 无匹配走玻璃空态且不溢出', (tester) async {
    await _pumpHostedLibrary(tester, section: MovieSection.movies);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.byType(MovieRedesignEmptyState), findsNothing);
    expect(find.text('无匹配条目'), findsOneWidget);
    expect(find.text('尝试调整筛选条件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('托管 Series 空列表走玻璃空态且不溢出', (tester) async {
    await _pumpHostedLibrary(tester, section: MovieSection.tvShows);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.byType(MovieRedesignEmptyState), findsNothing);
    expect(find.text('这里还没有媒体条目。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
