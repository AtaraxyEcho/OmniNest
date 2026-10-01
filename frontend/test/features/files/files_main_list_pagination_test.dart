import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:omninest/core/widgets/hosted_touch_canvas.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/files_table_view.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

/// 主列表分页条：替代原“加载更多”按钮，跳页经 goToFilePage 重放窗口。
void main() {
  testWidgets('全部文件主列表渲染分页条并跳页回调目标页', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final visitedPages = <int>[];
    final controller = _PagedMainListController(visitedPages);
    final container = ProviderContainer.test(
      overrides: [fileBrowserControllerProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => const FileBrowserPage(
                initialSection: FileManagerSection.allFiles,
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3 页元数据：分页条在场，页码全量展示，旧“加载更多”按钮不再出现。
    expect(find.byType(WorkstationPaginationBar), findsOneWidget);
    expect(find.text('共 3000 条'), findsOneWidget);
    expect(find.text('第 1-100 条'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing, reason: '加载更多已移除');

    // 分页条自身满宽（与上方表格同宽同左），内容自左缘排布——不收缩成
    // 内容宽度后被宿主居中。
    final barRect = tester.getRect(find.byType(WorkstationPaginationBar));
    final tableRect = tester.getRect(find.byType(FileTableView));
    expect(
      (barRect.left - tableRect.left).abs(),
      lessThan(2),
      reason: '分页条左缘与表格左缘对齐',
    );
    expect(
      (barRect.width - tableRect.width).abs(),
      lessThan(2),
      reason: '分页条满宽与表格同宽',
    );
    final countLeft = tester.getTopLeft(find.text('共 3000 条')).dx;
    expect(
      (countLeft - barRect.left).abs(),
      lessThan(4),
      reason: '计数文本自分页条左缘排布',
    );

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(visitedPages, [2], reason: '跳到第 3 页回调 0 基页码 2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('语义开启下翻页过渡不产生语义树异常', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();

    final controller = _PagedMainListController(<int>[]);
    final container = ProviderContainer.test(
      overrides: [fileBrowserControllerProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => const FileBrowserPage(
                initialSection: FileManagerSection.allFiles,
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 语义树在场时连续翻页：视图切换淡入与页码窗口滑动同帧更新语义。
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('共 3000 条'), findsOneWidget);
    semanticsHandle.dispose();
    expect(tester.takeException(), isNull, reason: '语义更新不得抛框架异常');
  });

  testWidgets('单页目录也常驻渲染分页条', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _SinglePageMainListController();
    final container = ProviderContainer.test(
      overrides: [fileBrowserControllerProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => const FileBrowserPage(
                initialSection: FileManagerSection.allFiles,
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // totalPages=1 不再隐藏分页条：总数、范围与每页条数切换始终可达。
    expect(find.byType(WorkstationPaginationBar), findsOneWidget);
    expect(find.text('共 8 条'), findsOneWidget);
    expect(find.text('第 1-8 条'), findsOneWidget);
    expect(find.text('10'), findsOneWidget, reason: '每页条数触发钮显示默认值');
    // 主列表候选统一为 10/20/50/100，不含旧档位 200。
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('20'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('200'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('托管平板宽度下分页条贴屏幕左缘，不随画布居中', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer.test(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _PagedMainListController(<int>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => const FileBrowserPage(
                initialSection: FileManagerSection.allFiles,
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MobileShellScope(
        hosted: true,
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: OmniNestTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 从首页卡进入全部文件列表态。
    await tester.tap(find.text('全部文件'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationPaginationBar), findsOneWidget);

    // 宽画布封顶 720 时内容列贴屏幕左缘（与 Admin 全宽工位同语言）：
    // 画布本身不得有居中偏移，分页条计数文本左偏移只剩列表内边距。
    final canvasLeft = tester.getTopLeft(find.byType(HostedTouchCanvas)).dx;
    expect(canvasLeft, 0, reason: '托管宽画布须左对齐封顶，不居中');
    final countLeft = tester.getTopLeft(find.text('共 3000 条')).dx;
    expect(countLeft, lessThan(60), reason: '分页条随内容列贴左，无居中画布偏移');
    expect(tester.takeException(), isNull);
  });

  testWidgets('最近分区的每页条数候选包含默认 10 且不含 200', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer.test(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _RecentSectionController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => const FileBrowserPage(
                initialSection: FileManagerSection.recent,
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkstationPaginationBar), findsOneWidget);
    // 打开每页条数下拉：候选 10/20/50/100，不含主列表档位 200。
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('10'),
      ),
      findsOneWidget,
      reason: '当前默认值必须在候选内',
    );
    expect(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('200'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _PagedMainListController extends FileBrowserController {
  _PagedMainListController(this.visitedPages);

  final List<int> visitedPages;

  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      section: FileManagerSection.allFiles,
      files: [for (var i = 0; i < 100; i++) _file('f$i')],
      recycleBin: const [],
      filePage: 0,
      filePageSize: 100,
      fileTotalElements: 3000,
      fileTotalPages: 3,
    );
  }

  @override
  Future<void> goToFilePage(int page) async {
    visitedPages.add(page);
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(filePage: page));
    }
  }

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}

  @override
  Future<void> refreshForRealtime() async {}
}

class _SinglePageMainListController extends FileBrowserController {
  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      section: FileManagerSection.allFiles,
      files: [for (var i = 0; i < 8; i++) _file('f$i')],
      recycleBin: const [],
      filePage: 0,
      filePageSize: 10,
      fileTotalElements: 8,
      fileTotalPages: 1,
    );
  }

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}

  @override
  Future<void> refreshForRealtime() async {}
}

class _RecentSectionController extends FileBrowserController {
  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      section: FileManagerSection.recent,
      files: const [],
      recentFiles: [for (var i = 0; i < 7; i++) _file('r$i')],
      recycleBin: const [],
      recentMeta: FilesSubPageMeta(
        page: 0,
        size: 10,
        totalElements: 25,
        totalPages: 3,
      ),
    );
  }

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}

  @override
  Future<void> refreshForRealtime() async {}
}

FileNode _file(String id) => FileNode(
  id: id,
  parentId: null,
  name: '$id.txt',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/$id.txt',
  sizeBytes: 1024,
  updatedAt: null,
);
