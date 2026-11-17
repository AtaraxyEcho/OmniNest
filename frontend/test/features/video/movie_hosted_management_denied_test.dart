// 托管态「无管理权限」块回归：落环境空态族，不再用工位图标+文案块；
// 桌面分支保持原密度。
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
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';

/// 除媒体库管理外全部放开：命中托管管理分区的权限门。
const _caps = UserCapabilities(
  canBrowseContent: true,
  canContributeContent: true,
  canManageOwnActivity: true,
  canManagePreferences: true,
  canManageAccount: true,
  canUseBackdropLibrary: true,
  canUploadBackdrop: true,
  canViewOwnTasks: true,
  canAdminTasks: true,
  canManageMediaLibrary: false,
  canManagePhotos: true,
  canAdminUsers: true,
  canReadSystemConfig: true,
  canManageSystemConfig: true,
  canAccessAdminConsole: true,
  canSharedBrowse: true,
  canSharedUpload: true,
  canReadWeather: true,
  canReportLocation: true,
  canManageTwoFactor: true,
  canReadActivity: true,
);

class _EmptyLibraryAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/video/dashboard' => <String, Object>{
        'stats': <String, Object>{
          'movieCount': 0,
          'episodeCount': 0,
          'seriesCount': 0,
          'scrapeFailedCount': 0,
        },
        'recentlyAdded': <Object>[],
        'continueWatching': <Object>[],
        'series': <Object>[],
      },
      '/video/library/page' || '/video/series/by-type/page' => <String, Object>{
        'items': <Object>[],
        'page': 0,
        'size': 36,
        'totalElements': 0,
        'totalPages': 0,
      },
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

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpHostedManagement(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_caps),
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
        home: MobileShellScope(
          hosted: true,
          child: Scaffold(
            backgroundColor: const Color(0xFF0B1110),
            body: MovieCenterPage(initialSection: MovieSection.management),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('托管管理分区无权限时走环境空态族', (tester) async {
    await _pumpHostedManagement(tester);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('管理工具仅管理员可见'), findsOneWidget);
    // 工位图标块只在桌面形态保留，托管态不得再出现。
    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
