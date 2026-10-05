// 托管态上传队列：原型传输页形态（计数眉标 + 三格摘要 + 进度行），
// 不出现工位指标条、四列表格与分页条。走真实「更多分区 → 上传队列」入口。
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

FileUploadQueueItem _item(
  String id,
  String name,
  int uploadedParts,
  String status,
) {
  return FileUploadQueueItem(
    id: id,
    uploadId: 'upload-$id',
    fileName: name,
    sizeBytes: 1200000,
    partSizeBytes: 12000,
    totalParts: 100,
    uploadedParts: uploadedParts,
    status: status,
  );
}

class _QueueController extends FileBrowserController {
  _QueueController(this.items);

  final List<FileUploadQueueItem> items;
  int? requestedPage;

  @override
  Future<FileBrowserState> build() async {
    return FileBrowserState(
      files: const <FileNode>[],
      recycleBin: const <FileNode>[],
      section: FileManagerSection.uploadQueue,
      uploadQueue: items,
      uploadQueueMeta: const FilesSubPageMeta(
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

  @override
  Future<void> showUploadQueue({int? page, int? size}) async {
    requestedPage = page;
  }
}

Future<_QueueController> _pumpToQueue(
  WidgetTester tester,
  List<FileUploadQueueItem> items,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = _QueueController(items);
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

  await tester.tap(find.byTooltip('更多分区'));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  await tester.tap(find.text('上传队列').last);
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  return controller;
}

void main() {
  testWidgets('队列页渲染摘要与进度行，不出现工位分页条', (tester) async {
    await _pumpToQueue(tester, [
      _item('u1', 'spring-raw.mov', 68, 'UPLOADING'),
      _item('u2', 'golden-hour.zip', 100, 'COMPLETED'),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileTransferSummary), findsOneWidget);
    expect(find.byType(MobileTransferRow), findsNWidgets(2));
    expect(find.text('spring-raw.mov'), findsOneWidget);
    expect(
      find.byType(WorkstationPaginationBar),
      findsNothing,
      reason: '托管态翻页改由眉标行动作承接',
    );
  });

  testWidgets('队列页翻页动作请求下一页', (tester) async {
    final controller = await _pumpToQueue(tester, [
      _item('u1', 'spring-raw.mov', 68, 'UPLOADING'),
    ]);

    await tester.tap(find.textContaining('加载更多'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.requestedPage, 1);
  });

  testWidgets('队列为空时给出空态而不是空表格', (tester) async {
    await _pumpToQueue(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileTransferRow), findsNothing);
    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('没有正在上传的文件'), findsOneWidget);
  });
}
