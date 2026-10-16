// 移动端子页态与分区取数的写入顺序契约。
//
// 入口时序是「先发起取数、再置子页态」（`_openMobileSection`），而取数完成回调若拿
// `await` 之前抓的快照整份发布，就会把子页态与视图模式无声写回旧值，真机表现为点
// 「最近使用」等四张分区卡后闪一下又弹回模块首页。控制器层锁机制，页面层锁时序。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

class _FakeFileRepository extends Mock implements FileRepository {}

class _HomeController extends FileBrowserController {
  _HomeController(this.initial);

  final FileBrowserState initial;

  @override
  Future<FileBrowserState> build() async => initial;
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

FileNode _node(String id) => FileNode(
  id: id,
  parentId: null,
  name: '$id.txt',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/$id.txt',
  sizeBytes: 1024,
  updatedAt: null,
);

/// 模块首页态：目录根、无子页、未选视图。
FileBrowserState _homeState() => FileBrowserState(
  files: <FileNode>[_node('f0')],
  recycleBin: const <FileNode>[],
  section: FileManagerSection.allFiles,
);

FileNodePage _recentPage() => FileNodePage(
  items: <FileNode>[_node('r0')],
  page: 0,
  size: 50,
  totalElements: 1,
  totalPages: 1,
);

FileNodePage _favoritePage() => FileNodePage(
  items: <FileNode>[_node('v0')],
  page: 0,
  size: 50,
  totalElements: 1,
  totalPages: 1,
);

FileNode _folder(String id) => FileNode(
  id: id,
  parentId: null,
  name: id,
  isFolder: true,
  nodeType: 'FOLDER',
  normalizedPath: '/$id',
  sizeBytes: 0,
  updatedAt: null,
);

FileNodePage _folderPage() => FileNodePage(
  items: <FileNode>[_node('inside')],
  page: 0,
  size: 10,
  totalElements: 1,
  totalPages: 1,
);

ProviderContainer _container(FileRepository repository) {
  final container = ProviderContainer.test(
    overrides: [
      fileRepositoryProvider.overrideWithValue(repository),
      fileBrowserControllerProvider.overrideWith(
        () => _HomeController(_homeState()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // 真实现状（修复前）：取数返回时 section 已换成 recent，但 mobileSubpage 被
  // await 前的快照写回 false，壳层顶栏与底部 tab 重新出现。
  test('分区取数完成后不覆盖取数期间的子页态写入', () async {
    final repository = _FakeFileRepository();
    final gate = Completer<FileNodePage>();
    when(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => gate.future);
    final container = _container(repository);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final pending = notifier.loadSection(FileManagerSection.recent);
    notifier.setMobileSubpage(true);
    expect(
      container.read(fileBrowserControllerProvider).value!.mobileSubpage,
      isTrue,
    );

    gate.complete(_recentPage());
    await pending;

    final state = container.read(fileBrowserControllerProvider).value!;
    expect(state.section, FileManagerSection.recent);
    expect(state.mobileSubpage, isTrue, reason: '子页态必须活过一次分区取数，否则用户被弹回模块首页');
  });

  // 同一条覆盖缺陷的第二个受害者：取数期间的视图切换。
  test('分区取数完成后不覆盖取数期间的视图模式', () async {
    final repository = _FakeFileRepository();
    final gate = Completer<FileNodePage>();
    when(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => gate.future);
    final container = _container(repository);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final pending = notifier.loadSection(FileManagerSection.recent);
    notifier.setViewMode(FileBrowserViewMode.grid);
    gate.complete(_recentPage());
    await pending;

    expect(
      container.read(fileBrowserControllerProvider).value!.viewMode,
      FileBrowserViewMode.grid,
    );
  });

  // 取数未回的那段窗口：分区必须已经落定，正文不能还停在上一分区，
  // 否则子页 chrome 收起后先闪一屏全部文件工作区。
  test('进入分区先把 section 落定，不等取数返回', () async {
    final repository = _FakeFileRepository();
    final gate = Completer<FileNodePage>();
    when(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => gate.future);
    final container = _container(repository);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final pending = notifier.loadSection(FileManagerSection.recent);
    expect(
      container.read(fileBrowserControllerProvider).value!.section,
      FileManagerSection.recent,
    );

    gate.complete(_recentPage());
    await pending;
  });

  // 页面层：真实入口时序（点首页卡片）+ 真实控制器。
  testWidgets('点首页分区卡后取数返回，仍留在该分区子页', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final repository = _FakeFileRepository();
    final gate = Completer<FileNodePage>();
    when(() => repository.listFilesPage()).thenAnswer(
      (_) async => FileNodePage(
        items: <FileNode>[_node('f0')],
        page: 0,
        size: 20,
        totalElements: 1,
        totalPages: 1,
      ),
    );
    when(() => repository.storageStats()).thenAnswer(
      (_) async => const FileStorageStats(
        totalFiles: 1,
        totalFolders: 0,
        usedBytes: 1024,
        quotaBytes: 10240,
        quotaStatus: 'OK',
        typeDistribution: <FileTypeStats>[],
      ),
    );
    when(
      () => repository.listUploadQueue(),
    ).thenAnswer((_) async => const <FileUploadQueueItem>[]);
    when(
      () => repository.listFavoriteFiles(),
    ).thenAnswer((_) async => const <FileNode>[]);
    when(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => gate.future);

    final container = ProviderContainer.test(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_caps),
        fileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => MobileShellScope(
                hosted: true,
                child: Scaffold(
                  backgroundColor: const Color(0xFF0B1110),
                  body: const FileBrowserPage(),
                ),
              ),
        ),
        GoRoute(
          path: '/portal',
          builder: (context, state) => const Scaffold(key: Key('portal-stub')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('最近使用').last);
    // 取数未回：子页已接管，且正文已是目标分区（不给全部文件工作区留中间帧）。
    await tester.pump();
    expect(
      container.read(fileBrowserControllerProvider).value!.mobileSubpage,
      isTrue,
    );
    expect(
      container.read(fileBrowserControllerProvider).value!.section,
      FileManagerSection.recent,
    );
    expect(find.text('我的文件'), findsNothing, reason: '首页工具栏不应仍在场');

    gate.complete(_recentPage());
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final after = container.read(fileBrowserControllerProvider).value!;
    expect(after.mobileSubpage, isTrue, reason: '取数返回后不得把用户弹回模块首页');
    expect(after.section, FileManagerSection.recent);
    expect(find.byKey(const Key('portal-stub')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 连点两张分区卡：分区由入口的乐观写定死，晚到的旧回包只能落自己那份数据。
  test('先发起的分区取数晚到，不把分区拖回旧值', () async {
    final repository = _FakeFileRepository();
    final recentGate = Completer<FileNodePage>();
    final favoriteGate = Completer<FileNodePage>();
    when(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => recentGate.future);
    when(
      () => repository.listFavoriteFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => favoriteGate.future);
    final container = _container(repository);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final recentPending = notifier.loadSection(FileManagerSection.recent);
    final favoritePending = notifier.loadSection(FileManagerSection.favorites);

    favoriteGate.complete(_favoritePage());
    await favoritePending;
    recentGate.complete(_recentPage());
    await recentPending;

    final state = container.read(fileBrowserControllerProvider).value!;
    expect(
      state.section,
      FileManagerSection.favorites,
      reason: '用户最后停在收藏，晚到的最近使用回包不得把分区拖回去',
    );
    expect(state.recentFiles, hasLength(1), reason: '数据仍可落地，只是不再决定分区');
  });

  // 目录取数在飞时切分区：目录导航的回包必须作废，否则会把已离开的目录压回栈顶。
  test('目录取数在飞时切分区，晚到回包不再压回目录', () async {
    final repository = _FakeFileRepository();
    final folderGate = Completer<FileNodePage>();
    when(
      () => repository.listFilesPage(
        parentId: any(named: 'parentId'),
        category: any(named: 'category'),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => folderGate.future);
    when(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => _recentPage());
    final container = _container(repository);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final folderPending = notifier.openFolder(_folder('d1'));
    await notifier.loadSection(FileManagerSection.recent);
    folderGate.complete(_folderPage());
    await folderPending;

    final state = container.read(fileBrowserControllerProvider).value!;
    expect(state.section, FileManagerSection.recent);
    expect(state.breadcrumbs, isEmpty, reason: '切分区已经作废这次目录导航，旧回包不能压回目录');
  });
}
