// 托管态剩余分区（离线下载 / 外部存储 / 导入任务 / 与我共享）：原型
// `.feature-list` 形态——计数眉标 + 状态丸行 + 环境空态 + 「加载更多」，
// 不出现工位表格与分页条。
//
// 走 `FileBrowserPage(initialSection:)` 的深链入口：控制器 build 先交首页态，
// loadSection 换成目标分区态，页面因此离开首页态渲染分区子页。外部存储的翻页
// 与目录进入落在 FileBrowserController 的 extension 成员上，子类无法替换，
// 因此浏览态只把任务喂成已进入目录并断言形态。
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
import 'package:omninest/core/widgets/mobile_ui.dart';
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

FileNode _file(String id, String name, {int sizeBytes = 2048}) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/$name',
    sizeBytes: sizeBytes,
    updatedAt: DateTime.utc(2026, 9, 20),
  );
}

const _homeState = FileBrowserState(
  files: <FileNode>[],
  recycleBin: <FileNode>[],
  section: FileManagerSection.allFiles,
);

class _SectionsController extends FileBrowserController {
  _SectionsController(this.sectionState);

  /// 目标分区态：loadSection 用它替换首页态。
  final FileBrowserState sectionState;

  int? offlinePage;
  int? sharedPage;

  @override
  Future<FileBrowserState> build() async => _homeState;

  @override
  Future<void> loadSection(
    FileManagerSection target, {
    bool background = false,
  }) async {
    expect(target, sectionState.section);
    state = AsyncData(sectionState);
  }

  @override
  Future<void> showOfflineDownloads({int? page, int? size}) async {
    offlinePage = page;
  }

  @override
  Future<void> showSharedWithMe({int? page, int? size}) async {
    sharedPage = page;
  }
}

Future<_SectionsController> _pump(
  WidgetTester tester,
  FileBrowserState sectionState,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = _SectionsController(sectionState);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => MobileShellScope(
              hosted: true,
              child: Scaffold(
                backgroundColor: const Color(0xFF0B1110),
                body: FileBrowserPage(initialSection: sectionState.section),
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
        fileBrowserControllerProvider.overrideWith(() => controller),
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
  return controller;
}

void main() {
  testWidgets('离线下载：状态丸行 + 加载更多，不出现工位分页条', (tester) async {
    final controller = await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.offlineDownloads,
        offlineTasks: <OfflineDownloadTask>[
          OfflineDownloadTask(
            id: 'o1',
            sourceUri: 'https://example.test/files/spring.zip',
            fileName: 'spring.zip',
            status: 'DOWNLOADING',
            totalBytes: 4000000,
            completedBytes: 1000000,
          ),
          OfflineDownloadTask(
            id: 'o2',
            sourceUri: 'https://example.test/files/quiet.mkv',
            fileName: 'quiet.mkv',
            status: 'FAILED',
            errorSummary: '远端拒绝连接',
          ),
        ],
        offlineMeta: FilesSubPageMeta(
          page: 0,
          size: 20,
          totalElements: 30,
          totalPages: 2,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileFeatureListRow), findsNWidgets(2));
    expect(find.byType(MobileStatusPill), findsNWidgets(2));
    expect(find.text('spring.zip'), findsOneWidget);
    expect(find.text('远端拒绝连接'), findsOneWidget);
    expect(find.byType(WorkstationPaginationBar), findsNothing);
    expect(find.text('共 2 项'), findsOneWidget);

    await tester.tap(find.textContaining('加载更多'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.offlinePage, 1);
  });

  testWidgets('外部存储账户列表态：条目行 + 添加挂载，无工位表格', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.externalStorage,
        externalAccounts: <ExternalStorageAccount>[
          ExternalStorageAccount(
            id: 'acc-1',
            provider: 'WebDAV',
            displayName: 'Studio NAS',
            status: 'CONNECTED',
            credentialsConfigured: true,
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileFeatureListRow), findsOneWidget);
    expect(find.text('Studio NAS'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    expect(find.byType(MobileStatusPill), findsOneWidget);
    expect(find.text('添加挂载'), findsOneWidget);
    expect(find.byType(WorkstationPaginationBar), findsNothing);
  });

  testWidgets('外部存储浏览态：目录行 + 关闭浏览 + 加载更多', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.externalStorage,
        externalBrowseAccountId: 'acc-1',
        externalBrowsePath: '/media',
        externalFiles: <ExternalFileItem>[
          ExternalFileItem(name: 'RAW', path: '/media/RAW', isDir: true),
          ExternalFileItem(
            name: 'reel.mov',
            path: '/media/reel.mov',
            isDir: false,
            sizeBytes: 44800000,
          ),
        ],
        externalMeta: FilesSubPageMeta(
          page: 0,
          size: 20,
          totalElements: 25,
          totalPages: 2,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileFeatureListRow), findsNWidgets(2));
    expect(find.text('RAW'), findsOneWidget);
    expect(find.textContaining('/media · 共 2 项'), findsOneWidget);
    expect(find.text('关闭浏览'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.textContaining('加载更多'), findsOneWidget);
    expect(find.byType(WorkstationPaginationBar), findsNothing);
  });

  testWidgets('导入任务为空给出环境空态而不是空表格', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.importTasks,
        importTasks: <ImportTask>[],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('还没有导入任务'), findsOneWidget);
    expect(find.byType(WorkstationPaginationBar), findsNothing);
  });

  testWidgets('导入任务：来源与进度进副题，状态进状态丸', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.importTasks,
        importTasks: <ImportTask>[
          ImportTask(
            id: 'i1',
            externalAccountId: 'acc-1',
            sourcePath: '/media/RAW',
            sourceKind: 'DIRECTORY',
            status: 'RUNNING',
            fileName: 'bookshelf-import',
            totalFiles: 20,
            completedFiles: 6,
          ),
          ImportTask(
            id: 'i2',
            externalAccountId: 'acc-1',
            sourcePath: '/media/reel.mov',
            status: 'FAILED',
            fileName: 'reel.mov',
            errorSummary: '空间不足',
          ),
        ],
        importMeta: FilesSubPageMeta(
          page: 0,
          size: 20,
          totalElements: 24,
          totalPages: 2,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileFeatureListRow), findsNWidgets(2));
    expect(find.byType(MobileStatusPill), findsNWidgets(2));
    expect(find.text('已完成 6/20 个文件'), findsOneWidget);
    expect(find.text('空间不足'), findsOneWidget);
    expect(find.textContaining('加载更多'), findsOneWidget);
    expect(find.byType(WorkstationPaginationBar), findsNothing);
  });

  testWidgets('与我共享：文件行 + 计数眉标 + 翻页动作', (tester) async {
    final controller = await _pump(
      tester,
      FileBrowserState(
        files: const <FileNode>[],
        recycleBin: const <FileNode>[],
        section: FileManagerSection.sharedWithMe,
        sharedWithMe: <SharedFileItem>[
          SharedFileItem(
            shareId: 'sh-1',
            file: _file('f-1', 'launch-film.mov', sizeBytes: 44800000),
            ownerUserId: 'u-owner',
            sharedAt: DateTime.utc(2026, 9, 24),
          ),
        ],
        sharedWithMeMeta: const FilesSubPageMeta(
          page: 0,
          size: 20,
          totalElements: 25,
          totalPages: 2,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('launch-film.mov'), findsOneWidget);
    expect(find.text('共 1 项'), findsOneWidget);

    await tester.tap(find.textContaining('加载更多'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.sharedPage, 1);
  });
}
