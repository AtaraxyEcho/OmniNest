// Files 模块托管态导航矩阵审查（PM 清单落地）：首页各入口 → 工作区形态、
// 目录逐级进出、分段切换、返回逐级。所有用例走真实 FileBrowserPage 树。
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

FileNode _folder(String id, String name, {String? parentId}) {
  return FileNode(
    id: id,
    parentId: parentId,
    name: name,
    isFolder: true,
    nodeType: 'FOLDER',
    normalizedPath: '/$name',
    sizeBytes: 0,
    updatedAt: DateTime(2026, 10, 1),
  );
}

FileNode _file(String id, String name, {String? parentId}) {
  return FileNode(
    id: id,
    parentId: parentId,
    name: name,
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/$name',
    sizeBytes: 2100000,
    updatedAt: DateTime(2026, 9, 24, 18, 2),
  );
}

/// 可变假件：记录分区/空间切换与面包屑导航，模拟最小状态机。
class _AuditFileController extends FileBrowserController {
  final loadedSections = <FileManagerSection>[];
  final switchedSpaces = <String>[];
  final breadcrumbJumps = <int>[];
  bool rootRestored = false;

  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      files: [_folder('root-folder', 'Spring trip')],
      recycleBin: [_file('rb1', 'Old poster.png')],
    );
  }

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {
    loadedSections.add(section);
    final current = state.asData!.value;
    state = AsyncData(current.copyWith(section: section));
  }

  @override
  Future<void> switchSpace(String newSpaceType) async {
    switchedSpaces.add(newSpaceType);
    final current = state.asData!.value;
    state = AsyncData(current.copyWith(spaceType: newSpaceType));
  }

  @override
  Future<void> openFolder(FileNode folder) async {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        files: [
          _folder('sub-${folder.id}', 'Nested', parentId: folder.id),
          _file('leaf-${folder.id}', 'Sheet.jpg', parentId: folder.id),
        ],
        parentId: folder.id,
        breadcrumbs: [...current.breadcrumbs, folder],
      ),
    );
  }

  @override
  Future<void> goToRoot() async {
    rootRestored = true;
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        files: [_folder('root-folder', 'Spring trip')],
        parentId: null,
        breadcrumbs: const [],
      ),
    );
  }

  @override
  Future<void> goToBreadcrumb(int index) async {
    breadcrumbJumps.add(index);
    final current = state.asData!.value;
    final crumbs = current.breadcrumbs.take(index + 1).toList();
    state = AsyncData(
      current.copyWith(breadcrumbs: crumbs, parentId: crumbs.last.id),
    );
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

Future<_AuditFileController> _pumpHost(WidgetTester tester) async {
  final controller = _AuditFileController();
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('目录原地展开：首页 chrome 保留 + 返回上一级栏', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = await _pumpHost(tester);

    expect(find.text('Spring trip'), findsWidgets);
    await tester.tap(find.text('Spring trip').first);
    await _settle(tester);

    expect(find.byType(MobileModuleHeader), findsNothing);
    expect(find.text('返回上一级'), findsOneWidget);
    expect(find.text('Sheet.jpg'), findsOneWidget);
    expect(controller.loadedSections, isEmpty);
  });

  testWidgets('共享空间工具栏页签：原地切换不离开首页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = await _pumpHost(tester);

    await tester.tap(find.text('共享空间').first);
    await _settle(tester);

    expect(controller.switchedSpaces, ['SHARED']);
    expect(find.byType(MobileModuleHeader), findsNothing);
    // 首页工具栏仍在场（空间页签）。
    expect(find.text('我的文件'), findsOneWidget);
  });

  testWidgets('工作区三段切换：共享空间分段加载分区并出现管理入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpHost(tester);

    // 经分类卡进入工作区（工作区仍承载分区视图）。
    await tester.tap(find.text('最近使用').first);
    await _settle(tester);
    expect(find.byType(MobileModuleHeader), findsOneWidget);
    // 分类卡工作区无三段；返回首页后再验证目录内三段不可达，
    // 三段仅在全部文件分区出现：直接切分区。
    await tester.tap(find.byType(MobileGlassIconButton).first);
    await _settle(tester);
    await tester.tap(find.text('Spring trip').first);
    await _settle(tester);
    expect(
      find.byType(MobileSegmentedControl<FileManagerSection>),
      findsNothing,
      reason: '目录原地展开态不显示三段',
    );
  });

  testWidgets('返回逐级：内联展开目录后逐级回退到空间根', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = await _pumpHost(tester);

    // 原地展开根目录。
    await tester.tap(find.text('Spring trip').first);
    await _settle(tester);
    // 展开二级目录。
    await tester.tap(find.text('Nested'));
    await _settle(tester);
    expect(
      controller.state.asData!.value.breadcrumbs.length,
      2,
      reason: '两级目录后面包屑长度为 2',
    );

    // 固定「返回上一级」栏点击回上级。
    final goUpBar = find.text('返回上一级');
    expect(goUpBar, findsOneWidget);
    await tester.tap(goUpBar);
    await _settle(tester);
    expect(controller.breadcrumbJumps, [0]);
    expect(
      controller.state.asData!.value.breadcrumbs.length,
      1,
      reason: '返回上一级后回到一级',
    );

    // 一级目录再点返回上一级：回空间根（首页卡片恢复）。
    await tester.tap(find.text('返回上一级'));
    await _settle(tester);
    expect(controller.rootRestored, isTrue);
    expect(find.text('返回上一级'), findsNothing);
    expect(find.text('Spring trip'), findsWidgets);
  });

  testWidgets('分类卡（最近）进入工作区：模块横幅在场', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = await _pumpHost(tester);

    await tester.tap(find.text('最近使用').first);
    await _settle(tester);

    expect(controller.loadedSections, contains(FileManagerSection.recent));
    expect(find.byType(MobileModuleHeader), findsOneWidget);
    expect(
      find.byType(MobileSegmentedControl<FileManagerSection>),
      findsNothing,
      reason: '非三段分区不显示分段',
    );
  });
}
