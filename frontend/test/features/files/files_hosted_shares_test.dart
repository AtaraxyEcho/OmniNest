// 托管态我的分享：发丝线行 + 状态丸，不出现工位表格与分页条。
// 走真实「更多分区 → 我的分享」入口。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

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

FileShareLink _share(
  String id,
  String name,
  String status, {
  DateTime? expiresAt,
}) {
  return FileShareLink(
    id: id,
    resourceType: 'FILE',
    resourceId: 'node-$id',
    resourceName: name,
    shareCode: 'code-$id',
    status: status,
    accessCount: 3,
    createdAt: DateTime(2026, 10, 1),
    expiresAt: expiresAt,
  );
}

class _SharesController extends FileBrowserController {
  _SharesController(this.shares);

  final List<FileShareLink> shares;

  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.myShares,
      myShares: shares,
      sharesMeta: const FilesSubPageMeta(
        page: 0,
        size: 20,
        totalElements: 40,
        totalPages: 2,
      ),
    );
  }

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}
}

Future<void> _pumpToShares(
  WidgetTester tester,
  List<FileShareLink> shares,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => const MobileShellScope(
              hosted: true,
              child: Scaffold(
                backgroundColor: Color(0xFF0B1110),
                body: FileBrowserPage(),
              ),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_caps),
        fileBrowserControllerProvider.overrideWith(
          () => _SharesController(shares),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  await tester.tap(find.byTooltip('更多分区'));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  await tester.tap(find.text('我的分享').last);
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('分享列表渲染发丝线行与状态丸，不出现工位分页条', (tester) async {
    await _pumpToShares(tester, [
      _share('s1', 'Golden hour', 'ACTIVE', expiresAt: DateTime(2026, 11, 1)),
      _share('s2', 'Raw set', 'EXPIRED'),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Golden hour'), findsOneWidget);
    expect(find.text('Raw set'), findsOneWidget);
    expect(find.byType(MobileStatusPill), findsNWidgets(2));
    expect(
      find.byType(WorkstationPaginationBar),
      findsNothing,
      reason: '托管态分页由眉标「加载更多」动作承接',
    );
    expect(find.textContaining('已过期 1'), findsOneWidget);
  });

  testWidgets('无分享链接时给出空态而不是空表格', (tester) async {
    await _pumpToShares(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('还没有创建分享链接'), findsOneWidget);
    expect(find.byType(WorkstationPaginationBar), findsNothing);
  });
}
