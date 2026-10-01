import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

/// 根治回归：自操作（建夹等）登记的回声在窗口内命中抑制；
/// 他端变更（无本地登记）不命中，仍走全量刷新。
class _MockRepo extends Mock implements FileRepository {}

void main() {
  late ProviderContainer container;
  late _MockRepo repository;

  Widget host() {
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder: (context, state) => const FileBrowserPage(),
        ),
        GoRoute(
          path: '/portal',
          builder: (context, state) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    );
  }

  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository = _MockRepo();
    when(
      () => repository.listFilesPage(
        parentId: any(named: 'parentId'),
        category: any(named: 'category'),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer(
      (_) async => const FileNodePage(
        items: <FileNode>[],
        page: 0,
        size: 50,
        totalElements: 0,
        totalPages: 1,
      ),
    );
    when(() => repository.storageStats()).thenAnswer(
      (_) async => const FileStorageStats(
        totalFiles: 0,
        totalFolders: 0,
        usedBytes: 0,
        quotaBytes: -1,
        quotaStatus: 'UNLIMITED',
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
      () => repository.createFolder(
        parentId: any(named: 'parentId'),
        name: any(named: 'name'),
      ),
    ).thenAnswer(
      (_) async => const FileNode(
        id: 'new-folder',
        parentId: null,
        name: '测试夹',
        isFolder: true,
        nodeType: 'FOLDER',
        normalizedPath: '/测试夹',
        sizeBytes: 0,
        updatedAt: null,
      ),
    );
    container = ProviderContainer(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        realtimeCoordinatorProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(() => container.dispose());
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('创建文件夹登记回声：窗口内命中抑制判定', (tester) async {
    await pumpDesktop(tester);
    final notifier = container.read(fileBrowserControllerProvider.notifier);

    await notifier.createFolder('测试夹');
    await tester.pumpAndSettle();

    expect(
      notifier.matchesRecentFileEchoes(const {'new-folder'}),
      isTrue,
      reason: '新建文件夹的自回声应命中抑制窗口（FileSyncHandler 据此跳过重载）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('他端变更不命中回声窗口（仍走全量刷新）', (tester) async {
    await pumpDesktop(tester);
    final notifier = container.read(fileBrowserControllerProvider.notifier);

    expect(
      notifier.matchesRecentFileEchoes(const {'other-device-file'}),
      isFalse,
      reason: '无本地登记的他端文件不得抑制刷新',
    );
  });

  testWidgets('后台刷新不切换 loading 占位符', (tester) async {
    await pumpDesktop(tester);
    final notifier = container.read(fileBrowserControllerProvider.notifier);

    // 后台模式刷新期间：backgroundRefresh 应为 true（占位符被门控）。
    var observedBackground = false;
    final sub = container.listen(
      fileBrowserControllerProvider.select(
        (async) => async.asData?.value.backgroundRefresh,
      ),
      (_, next) {
        if (next == true) {
          observedBackground = true;
        }
      },
    );
    addTearDown(sub.close);

    await notifier.refreshForRealtime();
    await tester.pumpAndSettle();

    expect(observedBackground, isTrue, reason: '实时刷新应标记为后台模式');
    expect(
      container
          .read(fileBrowserControllerProvider)
          .asData
          ?.value
          .backgroundRefresh,
      isFalse,
      reason: '刷新完成后应复位',
    );
    expect(tester.takeException(), isNull);
  });
}
