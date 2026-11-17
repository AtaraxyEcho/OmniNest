// 托管态存储统计：修复「点存储统计看到的是文件列表」。
// 断言统计页渲染摘要与类型分布，且不再落到文件列表工作区。
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

FileStorageStats _stats() {
  return const FileStorageStats(
    totalFiles: 1280,
    totalFolders: 42,
    usedBytes: 68000000000,
    quotaBytes: 100000000000,
    quotaStatus: 'NEAR_LIMIT',
    typeDistribution: [
      FileTypeStats(category: 'VIDEO', count: 80, sizeBytes: 50000000000),
      FileTypeStats(category: 'IMAGE', count: 1200, sizeBytes: 18000000000),
    ],
  );
}

class _StatsController extends FileBrowserController {
  _StatsController(this.stats);

  final FileStorageStats? stats;

  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      files: <FileNode>[
        FileNode(
          id: 'n1',
          parentId: null,
          name: 'should-not-show',
          isFolder: false,
          nodeType: 'FILE',
          normalizedPath: '/should-not-show',
          sizeBytes: 10,
          updatedAt: DateTime(2026, 10, 1),
        ),
      ],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.storageStats,
      storageStats: stats,
    );
  }

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}
}

Future<void> _pumpToStats(WidgetTester tester, FileStorageStats? stats) async {
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
          () => _StatsController(stats),
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
  // 存储统计不在「更多分区」列表里，入口是首页顶部的存储条。
  await tester.tap(find.text('存储用量'));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('存储统计页渲染摘要与类型分布，而不是文件列表', (tester) async {
    await _pumpToStats(tester, _stats());

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileTransferSummary), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('74%'), findsOneWidget);
    expect(
      find.text('should-not-show'),
      findsNothing,
      reason: '存储统计不再复用文件列表工作区',
    );
  });

  testWidgets('统计未就绪时给空态与重试', (tester) async {
    await _pumpToStats(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('暂时取不到存储统计'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });
}
