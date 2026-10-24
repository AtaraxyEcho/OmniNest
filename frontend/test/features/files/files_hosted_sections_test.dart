// 托管态分区（外部存储 / 导入任务 / 与我共享）：原型
// `.feature-list` 形态——计数 + 状态丸行 + 环境空态 + 「加载更多」，
// 不出现工位表格与分页条。与我共享按样例 FeaturePage 只留
// 页头计数与纯列表，外部存储与导入任务
// 仍挂计数眉标条。
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
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
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
  _SectionsController(this.sectionState, {FileBrowserState? startState})
    : _startState = startState;

  /// 目标分区态：loadSection 用它替换首页态。
  final FileBrowserState sectionState;

  /// 首页态覆盖：目录态与分区同属 allFiles 时深链不会触发 loadSection，
  /// 需要直接把目标态作为起始态交出去。
  final FileBrowserState? _startState;

  int? sharedPage;
  int? wentToBreadcrumb;
  bool wentToRoot = false;

  @override
  Future<void> goToBreadcrumb(int index) async {
    // 系统返回逐级回目录：记录目标层级而不是真的取数。
    wentToBreadcrumb = index;
  }

  @override
  Future<void> goToRoot() async {
    wentToRoot = true;
  }

  @override
  Future<void> refreshFileNodesForCurrentSection() async {
    // 建夹后的原地刷新不在本用例范围内，仓储只备了 createFolder。
  }

  @override
  Future<FileBrowserState> build() async => _startState ?? _homeState;

  @override
  Future<void> loadSection(
    FileManagerSection target, {
    bool background = false,
  }) async {
    expect(target, sectionState.section);
    state = AsyncData(sectionState);
  }

  @override
  Future<void> showSharedWithMe({int? page, int? size}) async {
    sharedPage = page;
  }

  @override
  Future<void> loadMoreSharedWithMe() async {
    sharedPage = sectionState.sharedWithMeMeta.page + 1;
  }
}

/// 只备 `createFolder` 的仓储替身：`createFolder` 是控制器 extension 成员，
/// 子类桩拦不住（extension 不参与虚分派），所以建夹要断言到仓储边界。
class _RecordingFolderRepository implements FileRepository {
  final created = <({String? parentId, String name})>[];

  @override
  Future<List<ExternalStorageAccount>> listExternalStorages() async => const [];

  @override
  Future<FileNode> createFolder({
    String? parentId,
    required String name,
  }) async {
    created.add((parentId: parentId, name: name));
    return FileNode(
      id: 'new-folder',
      parentId: parentId,
      name: name,
      isFolder: true,
      nodeType: 'FOLDER',
      normalizedPath: '/$name',
      sizeBytes: 0,
      updatedAt: DateTime.utc(2026, 9, 20),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_SectionsController> _pump(
  WidgetTester tester,
  FileBrowserState sectionState, {
  FileBrowserState? startState,
  FileRepository? repository,
  String? oauthStatus,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = _SectionsController(sectionState, startState: startState);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => MobileShellScope(
              hosted: true,
              child: Scaffold(
                backgroundColor: const Color(0xFF0B1110),
                body: FileBrowserPage(
                  initialSection: sectionState.section,
                  initialOAuthStatus: oauthStatus,
                ),
              ),
            ),
      ),
      // 离站信号：`_onBack` 落到「回门户」分支时会出现这一页。
      GoRoute(
        path: '/portal',
        builder: (context, state) => const Scaffold(key: Key('portal-stub')),
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
        if (repository != null)
          fileRepositoryProvider.overrideWithValue(repository),
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

  testWidgets('与我共享：文件行 + 页头计数 + 列表尾翻页动作', (tester) async {
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
    // 页头副题给分区真实总数（meta.totalElements），不再是已载入条数。
    expect(find.text('共 25 项'), findsOneWidget);
    expect(find.byTooltip('上传'), findsNothing);

    await tester.tap(find.textContaining('加载更多'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.sharedPage, 1);
  });

  testWidgets('最近使用：页头副题用分区真实计数，正文无工位计数条', (tester) async {
    await _pump(
      tester,
      FileBrowserState(
        files: const <FileNode>[],
        recycleBin: const <FileNode>[],
        section: FileManagerSection.recent,
        recentFiles: <FileNode>[_file('r-1', 'quiet.mkv', sizeBytes: 2048)],
        recentMeta: const FilesSubPageMeta(
          page: 0,
          size: 20,
          totalElements: 18,
          totalPages: 1,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('quiet.mkv'), findsOneWidget);
    // 页头副题 = recentMeta 总数；不是工位列表的 state.files.length。
    expect(find.text('共 18 项'), findsOneWidget);
    expect(find.byTooltip('上传'), findsNothing);
  });

  // 系统返回（Android 侧滑/返回键）：真实模型里根是**空列表**不是根节点，
  // 所以「进了一个目录」= length 1——上一版只处理 length>1，一级目录下返回
  // 直接 go('/portal')，再按一次就是分支首路由的 bubble → 退出应用。
  testWidgets('一级目录：系统返回回根列表而不是离站', (tester) async {
    final state = FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.allFiles,
      breadcrumbs: <FileNode>[_file('d1', '工作室')],
    );
    final controller = await _pump(tester, state, startState: state);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.wentToRoot, isTrue, reason: '一级目录返回 = 回根列表');
    expect(controller.wentToBreadcrumb, isNull);
    expect(find.byKey(const Key('portal-stub')), findsNothing, reason: '不得离站');
  });

  testWidgets('二级目录：系统返回回上一级', (tester) async {
    final state = FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.allFiles,
      breadcrumbs: <FileNode>[_file('d1', '工作室'), _file('d2', '扫描件')],
    );
    final controller = await _pump(tester, state, startState: state);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.wentToBreadcrumb, 0, reason: '两级面包屑应回 index 0');
    expect(controller.wentToRoot, isFalse);
    expect(find.byKey(const Key('portal-stub')), findsNothing);
  });

  // 切到次分区时 breadcrumbs 不清空：返回若照目录回退会把用户强切回
  // 全部文件（观感是「进不去也退不出」）。
  testWidgets('次分区带残留面包屑：返回走页面层级，不动目录', (tester) async {
    final state = FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.recent,
      mobileSubpage: true,
      breadcrumbs: <FileNode>[_file('d1', '工作室'), _file('d2', '扫描件')],
    );
    final controller = await _pump(tester, state, startState: state);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.wentToBreadcrumb, isNull, reason: '不得按目录回退');
    expect(controller.wentToRoot, isFalse);
    expect(
      controller.state.asData?.value.mobileSubpage,
      isFalse,
      reason: '返回应回模块首页',
    );
    expect(find.byKey(const Key('portal-stub')), findsNothing);
  });

  // 移动端首页的内联列表不渲染工位草稿行，新建文件夹必须走可见输入框；
  // 原先点「+ → 新建文件夹」只写 draftFolderName，等于没有反应。
  testWidgets('托管目录页头新建文件夹：命名框提交后落到仓储', (tester) async {
    final state = FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.allFiles,
      mobileSubpage: true,
      parentId: 'root',
      breadcrumbs: <FileNode>[_file('root', '根')],
    );
    final repository = _RecordingFolderRepository();
    await _pump(tester, state, startState: state, repository: repository);

    expect(find.byTooltip('上传'), findsOneWidget);
    expect(find.byTooltip('新建文件夹'), findsOneWidget);
    await tester.tap(find.byTooltip('新建文件夹'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('新建文件夹'), findsWidgets, reason: '命名框应预填去重后的默认名');
    await tester.enterText(find.byType(TextField), '归档');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.byType(TextField), findsNothing, reason: '对话框应已关闭');
    expect(tester.takeException(), isNull);
    expect(repository.created, [
      (parentId: 'root', name: '归档'),
    ], reason: '建在當前目录（根）下，名字取输入值');
  });

  // 深链重复进入：`?section=` 变化在 go_router 里是原地更新（page key 只认
  // 路径），闩锁不复位就会「一次深链只生效一次」。这里覆盖「已在目标分区但
  // 停在模块首页」的再进入。
  testWidgets('深链再进入：已在目标分区也直接进子页', (tester) async {
    final state = FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.favorites,
    );
    final controller = await _pump(tester, state, startState: state);

    expect(
      controller.state.asData?.value.mobileSubpage,
      isTrue,
      reason: '落在已在分区时应进子页，而不是停在模块首页',
    );
  });

  // 多选是最内一层：一次侧滑只退出多选，不能把「清选中」和「离开子页」
  // 压在同一次手势里（此前一次侧滑吃掉两级）。
  testWidgets('子页有选中：第一次侧滑只退出多选', (tester) async {
    final state = FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.recent,
      mobileSubpage: true,
      recentFiles: <FileNode>[_file('r-1', 'quiet.mkv')],
      selectedFileIds: const <String>{'r-1'},
    );
    final controller = await _pump(tester, state, startState: state);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      controller.state.asData?.value.selectedFileIds,
      isEmpty,
      reason: '第一次只清选中',
    );
    expect(
      controller.state.asData?.value.mobileSubpage,
      isTrue,
      reason: '仍停在子页，不该一次就回首页',
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(controller.state.asData?.value.mobileSubpage, isFalse);
    expect(find.byKey(const Key('portal-stub')), findsNothing);
  });

  // 宿主正文插槽是 Expanded 下的有界高度：分区体不带 Scrollable 时，
  // 条目超过一屏会 RenderFlex 溢出且尾部内容不可达。
  testWidgets('与我共享 长列表：正文自带滚动且不溢出', (tester) async {
    await _pump(
      tester,
      FileBrowserState(
        files: const <FileNode>[],
        recycleBin: const <FileNode>[],
        section: FileManagerSection.sharedWithMe,
        sharedWithMe: <SharedFileItem>[
          for (var i = 0; i < 20; i++)
            SharedFileItem(
              shareId: 'sh-$i',
              file: _file('s$i', 'shared-$i.mov'),
              ownerUserId: 'u-$i',
              sharedAt: DateTime.utc(2026, 9, 24),
            ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    // 纵向正文列表的 Scrollable：直接取 Scrollable 会挑错目标。
    await tester.scrollUntilVisible(
      find.text('shared-19.mov'),
      260,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('shared-19.mov'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最近使用给 .feature-hero 身份块', (tester) async {
    await _expectHero(tester, FileManagerSection.recent);
  });

  testWidgets('我的收藏给 .feature-hero 身份块', (tester) async {
    await _expectHero(tester, FileManagerSection.favorites);
  });

  testWidgets('与我共享给 .feature-hero 身份块', (tester) async {
    await _expectHero(tester, FileManagerSection.sharedWithMe);
  });

  testWidgets('文件夹分区不给身份块，仍是三档分段', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.allFiles,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byType(SampleFeatureHero),
      findsNothing,
      reason: 'FolderView 档的页头是分段器，不给 .feature-hero',
    );
  });

  testWidgets('外部存储 OAuth 成功回跳：提示结果并加载外部存储分区', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.externalStorage,
      ),
      repository: _RecordingFolderRepository(),
      oauthStatus: 'success',
    );

    expect(find.text('外部存储授权完成。'), findsOneWidget);
    expect(find.byType(FileBrowserPage), findsOneWidget);
  });

  testWidgets('外部存储 OAuth 失败回跳：提示失败文案', (tester) async {
    await _pump(
      tester,
      const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
        section: FileManagerSection.externalStorage,
      ),
      repository: _RecordingFolderRepository(),
      oauthStatus: 'error',
    );

    expect(find.text('外部存储授权失败，请重试。'), findsOneWidget);
  });
}

/// 样例 featureMeta 给这四个分区各一张 FeaturePage：页头之下先落身份块。
///
/// 页头留真实计数、hero 留分区说明，两行不再同文；标题按样例在两处各现一次。
Future<void> _expectHero(
  WidgetTester tester,
  FileManagerSection section,
) async {
  await _pump(
    tester,
    FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: section,
    ),
  );

  expect(tester.takeException(), isNull, reason: section.name);
  expect(
    find.byType(SampleFeatureHero),
    findsOneWidget,
    reason: '${section.name} 是样例 featureMeta 里的 FeaturePage',
  );
  expect(
    find.descendant(
      of: find.byType(SampleFeatureHero),
      matching: find.text(section.labelOf(_l10n(tester))),
    ),
    findsOneWidget,
    reason: section.name,
  );
}

/// 从已挂载的树里取本地化实例，用于按分区名反查文案。
AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(
    tester.element(find.byType(FileBrowserPage).first),
  );
}
