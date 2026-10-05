// 托管 Files 首页验证：目录原地展开（保留首页 chrome + 内联返回上级栏）。
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
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

FileNode _folder(String id, String name) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: true,
    nodeType: 'FOLDER',
    normalizedPath: '/$name',
    sizeBytes: 0,
    updatedAt: DateTime(2026, 10, 1),
  );
}

FileNode _file(String id, String name) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/$name',
    sizeBytes: 2100000,
    updatedAt: DateTime(2026, 9, 24, 18, 2),
  );
}

class _FakeFileBrowserController extends FileBrowserController {
  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      files: [_folder('f1', 'Spring trip'), _file('n0', 'Sheet.jpg')],
      recycleBin: const [],
    );
  }

  @override
  Future<void> openFolder(FileNode folder) async {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        files: [_file('leaf-1', 'Poster.png')],
        parentId: folder.id,
        breadcrumbs: [folder],
      ),
    );
  }

  @override
  Future<void> goToBreadcrumb(int index) async {}

  @override
  Future<void> goToRoot() async {
    state = AsyncData(await build());
  }
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
  testWidgets('目录原地展开：首页 chrome 保留 + 内联返回上级栏', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => const MobileShellScope(
                hosted: true,
                child: Scaffold(
                  backgroundColor: Color(0xFF0B1110),
                  body: FileBrowserPage(),
                ),
              ),
        ),
        GoRoute(
          path: '/portal',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('portal-home'))),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          userCapabilitiesProvider.overrideWithValue(_caps),
          fileBrowserControllerProvider.overrideWith(
            () => _FakeFileBrowserController(),
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Spring trip'), findsOneWidget);

    // 点目录：原地展开，不出现工作区模块横幅，出现内联返回上级栏。
    await tester.tap(find.text('Spring trip'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileModuleHeader), findsNothing);
    expect(find.text('返回上一级'), findsOneWidget);
    expect(find.text('Poster.png'), findsOneWidget);
  });
}
