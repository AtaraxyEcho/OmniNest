import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

/// 子表虚拟化与表头吸顶（缺陷报告 M-11）。
///
/// _SubTable 曾把表头与全部数据行塞进同一个纵向 SingleChildScrollView：
/// 行数一多就一次性构建全部行，且向下滚动时表头被推出屏幕。
/// 现在表头固定在顶部、数据行走 ListView.builder，两条都必须可被断言捕获。
void main() {
  testWidgets('共享表滚动到底部时表头仍在场、首行已被回收', (tester) async {
    tester.view.physicalSize = const Size(1440, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _PagedTableController(_stateWithRows(120)),
        ),
        realtimeCoordinatorProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => FileBrowserPage(
                initialSection: FileManagerSection.sharedWithMe,
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
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('名称'), findsOneWidget, reason: '表头列名在初始态在场');
    expect(find.text('shared-0.txt'), findsOneWidget);
    // 120 行若全部构建，树里会出现 120 个行名；虚拟化后只构建可见窗口。
    expect(
      tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text && (widget.data ?? '').startsWith('shared-'),
            ),
          )
          .length,
      lessThan(40),
      reason: '数据行必须按需构建，而不是 120 行一次性上树',
    );

    // 表头与数据行分属两个滚动容器；数据行会被回收，所以按滚动位置对象滚动。
    final tablePosition =
        Scrollable.of(tester.element(find.text('shared-0.txt'))).position;
    for (
      var attempt = 0;
      attempt < 10 && tablePosition.pixels < tablePosition.maxScrollExtent;
      attempt++
    ) {
      tablePosition.jumpTo(tablePosition.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    expect(find.text('shared-119.txt'), findsOneWidget);
    expect(find.text('shared-0.txt'), findsNothing, reason: '滚出视口的首行应当被回收');
    expect(find.text('名称'), findsOneWidget, reason: '表头必须吸顶，不随数据行滚出屏幕');
    expect(tester.takeException(), isNull);
  });

  testWidgets('上传队列表按可见窗口构建行，任务再多也不预构造全部行', (tester) async {
    tester.view.physicalSize = const Size(1440, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _PagedTableController(_stateWithUploadTasks(120)),
        ),
        realtimeCoordinatorProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => FileBrowserPage(
                initialSection: FileManagerSection.uploadQueue,
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
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('local-0.bin'), findsOneWidget);
    expect(
      tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text && (widget.data ?? '').startsWith('local-'),
            ),
          )
          .length,
      lessThan(40),
      reason: '传输行必须按需构建，而不是 120 行一次性上树',
    );

    final tablePosition =
        Scrollable.of(tester.element(find.text('local-0.bin'))).position;
    for (
      var attempt = 0;
      attempt < 10 && tablePosition.pixels < tablePosition.maxScrollExtent;
      attempt++
    ) {
      tablePosition.jumpTo(tablePosition.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    expect(find.text('local-119.bin'), findsOneWidget);
    expect(find.text('local-0.bin'), findsNothing, reason: '滚出视口的首行应当被回收');
    expect(tester.takeException(), isNull);
  });
}

FileBrowserState _stateWithUploadTasks(int count) {
  return FileBrowserState(
    section: FileManagerSection.uploadQueue,
    files: const <FileNode>[],
    recycleBin: const <FileNode>[],
    localUploadTasks: [
      for (var index = 0; index < count; index++)
        FileUploadClientTask(
          id: 'local-$index',
          fileName: 'local-$index.bin',
          sizeBytes: 1024,
          uploadedBytes: 512,
          status: 'RUNNING',
        ),
    ],
  );
}

FileBrowserState _stateWithRows(int count) {
  return FileBrowserState(
    section: FileManagerSection.sharedWithMe,
    files: const <FileNode>[],
    recycleBin: const <FileNode>[],
    sharedWithMe: [
      for (var index = 0; index < count; index++)
        SharedFileItem(
          shareId: 'share-$index',
          ownerUserId: 'owner-$index',
          sharedAt: null,
          expiresAt: null,
          file: FileNode(
            id: 'file-shared-$index',
            parentId: null,
            name: 'shared-$index.txt',
            isFolder: false,
            nodeType: 'FILE',
            normalizedPath: '/shared-$index.txt',
            sizeBytes: 1024,
            updatedAt: null,
            uploaderName: 'ataraxy',
          ),
        ),
    ],
  );
}

class _PagedTableController extends FileBrowserController {
  _PagedTableController(this.initialState);

  final FileBrowserState initialState;

  @override
  Future<FileBrowserState> build() async => initialState;

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {
    state = AsyncData(
      state.asData?.value.copyWith(section: section) ?? initialState,
    );
  }

  @override
  Future<void> refreshForRealtime() async {}
}
