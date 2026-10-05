// 托管照片页返回钮回归：头部返回曾与 PopScope(canPop:false) 互相递归
// （maybePop 回落自身回调，真机无响应退出）。本测试验证头部返回能真正
// 弹出路由且不抛异常。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';

class _FakePhotoCenter extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: [
        PhotoItem(
          id: 'p1',
          fileNodeId: 'p1',
          title: 'West Lake dusk',
          format: 'IMAGE',
          fileSize: 2400000,
          metadataStatus: 'READY',
          favorite: false,
          createdAt: DateTime.now(),
        ),
      ],
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
      photoTotalElements: 1,
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadTimeline({bool force = false}) async {}
}

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
  canManageMediaLibrary: true,
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

void main() {
  testWidgets('托管照片页头部返回弹出路由不递归', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(
          path: '/library',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('library-home'))),
        ),
        GoRoute(
          path: '/photos',
          builder:
              (context, state) => const MobileShellScope(
                hosted: true,
                child: Scaffold(
                  backgroundColor: Color(0xFF0B1110),
                  body: PhotosPage(),
                ),
              ),
        ),
      ],
    );
    // 页内存在常驻动画（骨架/指示器），pumpAndSettle 不会收敛：
    // 一律用固定时长推进。
    Future<void> settleFix() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          userCapabilitiesProvider.overrideWithValue(_caps),
          photoCenterControllerProvider.overrideWith(() => _FakePhotoCenter()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          routerConfig: router,
        ),
      ),
    );
    await settleFix();
    expect(find.text('library-home'), findsOneWidget);

    // push 返回的 Future 要等路由弹出才完成，不能 await。
    unawaited(router.push('/photos'));
    await settleFix();
    expect(find.byType(PhotosPage), findsOneWidget);

    // 点击头部返回（MobileModuleHeader 内的返回圆钮）。
    final backButton = find.byType(MobileGlassIconButton).first;
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await settleFix();

    expect(tester.takeException(), isNull);
    expect(router.routeInformationProvider.value.uri.path, '/library');
  });
}
