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

/// 桌面态全部子页工作区的页面级冒烟测试。
///
/// 回归背景：_SubTable 曾把含 Expanded 的表头行放进横向滚动视口，
/// 无界宽度约束导致每个子页进入即抛 unbounded flex 断言级联崩溃；
/// 本组用例以真实页面壳层逐分区泵入，宽/窄两档宽度都必须无异常渲染。
void main() {
  late ProviderContainer container;

  Widget host(FileManagerSection section) {
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder: (context, state) => FileBrowserPage(initialSection: section),
        ),
        GoRoute(
          path: '/portal',
          builder:
              (context, state) =>
                  const SizedBox(key: Key('portal-destination')),
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

  Future<void> pumpSection(
    WidgetTester tester,
    FileManagerSection section,
    Size surface,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _SeededController(_seededState(section)),
        ),
        // 侧栏实时状态点依赖协调器（会拉起 drift/网络），测试态置空。
        realtimeCoordinatorProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(() => container.dispose());
    await tester.pumpWidget(host(section));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  // (分区, 页头标题, 表头锚点文案, 行种子数据, 视口)。
  for (final entry in const <
    (FileManagerSection, String, String?, String, Size)
  >[
    (
      FileManagerSection.sharedWithMe,
      '共享给我',
      '名称',
      'shared-note.txt',
      Size(1440, 900),
    ),
    (FileManagerSection.myShares, '我的分享', '名称', 'AB12CD34', Size(1440, 900)),
    // shareManagement 已并入我的分享（合并页），旧入口重定向渲染。
    (
      FileManagerSection.shareManagement,
      '我的分享',
      '名称',
      'AB12CD34',
      Size(1440, 900),
    ),
    (
      FileManagerSection.uploadQueue,
      '上传队列',
      '更新时间',
      'local-upload.bin',
      Size(1440, 900),
    ),
    (
      FileManagerSection.offlineDownloads,
      '离线下载',
      '任务来源',
      'offline-movie.mkv',
      Size(1440, 900),
    ),
    (
      FileManagerSection.importTasks,
      '导入任务',
      '任务来源',
      'external-album.zip',
      Size(1440, 900),
    ),
    // 列表分区（最近/收藏/回收站）桌面态同样提供分类筛选栏。
    (
      FileManagerSection.recent,
      '最近使用',
      null,
      'recent-note.txt',
      Size(1440, 900),
    ),
    (
      FileManagerSection.favorites,
      '我的收藏',
      null,
      'fav-photo.jpg',
      Size(1440, 900),
    ),
    (
      FileManagerSection.recycleBin,
      '回收站',
      null,
      'trashed.zip',
      Size(1440, 900),
    ),
    // 窄桌面档：内容区低于自然最小宽触发 _SubTable 横向滚动分支。
    (FileManagerSection.myShares, '我的分享', '名称', 'AB12CD34', Size(1100, 900)),
    (
      FileManagerSection.importTasks,
      '导入任务',
      '任务来源',
      'external-album.zip',
      Size(1100, 900),
    ),
    (
      FileManagerSection.uploadQueue,
      '上传队列',
      '更新时间',
      'local-upload.bin',
      Size(1100, 900),
    ),
  ]) {
    final (section, title, headerAnchor, rowDatum, surface) = entry;
    testWidgets('$section @ ${surface.width}px 渲染无异常', (tester) async {
      await pumpSection(tester, section, surface);

      expect(tester.takeException(), isNull, reason: '$section 不得抛布局断言');
      // 分区标题（侧栏 + 工作区页头至少其一）+ 表头锚点 + 一行种子数据
      // 同时在场，证明工作区真实构建而非空态。
      expect(find.text(title), findsAtLeastNWidgets(1));
      if (headerAnchor != null) {
        expect(find.text(headerAnchor), findsOneWidget);
      }
      expect(find.text(rowDatum), findsAtLeastNWidgets(1));
      if (section == FileManagerSection.recent ||
          section == FileManagerSection.favorites ||
          section == FileManagerSection.recycleBin) {
        expect(
          find.textContaining('全部'),
          findsAtLeastNWidgets(1),
          reason: '列表分区同样提供分类筛选栏',
        );
      }
    });
  }

  testWidgets('共享给我表展示可读上传者与有效期而非原始用户 ID', (tester) async {
    await pumpSection(
      tester,
      FileManagerSection.sharedWithMe,
      const Size(1440, 900),
    );

    // 上传者列渲染可读名；原始 ownerUserId（UUID 形态）不再直接上表。
    expect(find.text('ataraxy'), findsOneWidget);
    expect(find.text('admin'), findsNothing);
    // 时间列表头语义对齐真实数据：sharedAt 对应"分享时间"。
    expect(find.text('分享时间'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    // sharedAt 为空显示占位，expiresAt 有值按本地格式渲染。
    expect(find.text('—'), findsAtLeastNWidgets(1));
    expect(find.text('2026-12-31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上传队列表头列齐全且富余宽度按权重分摊不超 1560 封顶', (tester) async {
    await pumpSection(
      tester,
      FileManagerSection.uploadQueue,
      const Size(1600, 900),
    );

    // 回归：表头曾只有 6 列而行有 8 列，更新/过期两列无表头且全表错位；
    // 列 spec 单一来源后表头必须列齐全。
    expect(find.text('更新时间'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 进度列转弹性后吸收富余，超过旧固定宽 220-12 的可读上界。
    final uploadBars =
        tester
            .renderObjectList<RenderBox>(find.byType(LinearProgressIndicator))
            .where((box) => box.size.height == 2)
            .toList();
    expect(uploadBars, isNotEmpty, reason: '上传行应渲染 2px 进度条');
    final bar = uploadBars.first;
    final barRight = bar.localToGlobal(Offset.zero).dx + bar.size.width;
    final statusLeft =
        tester
            .renderObject<RenderBox>(find.text('执行中'))
            .localToGlobal(Offset.zero)
            .dx;
    expect(barRight, lessThan(statusLeft), reason: '进度条与状态徽章不得相连');

    final nameLeft =
        tester
            .renderObject<RenderBox>(find.text('local-upload.bin'))
            .localToGlobal(Offset.zero)
            .dx;
    final originLeft =
        tester
            .renderObject<RenderBox>(find.text('本地'))
            .localToGlobal(Offset.zero)
            .dx;
    final nameWidth = originLeft - nameLeft;
    expect(nameWidth, greaterThan(300), reason: '名称列仍为主弹性列');
    expect(nameWidth, lessThan(700), reason: '名称列不得独吞全部富余宽度');
  });

  testWidgets('超宽视口下表格封顶 1560，主列不再被拉成大片留白', (tester) async {
    await pumpSection(
      tester,
      FileManagerSection.offlineDownloads,
      const Size(2560, 1200),
    );

    // 无封顶时 2560 视口下任务来源列会达到 1300px+；封顶 + 弹性分摊后
    // 主列被约束在远低于视口的宽度内。
    final sourceLeft =
        tester
            .renderObject<RenderBox>(find.text('offline-movie.mkv'))
            .localToGlobal(Offset.zero)
            .dx;
    final typeLeft =
        tester
            .renderObject<RenderBox>(find.text('HTTPS'))
            .localToGlobal(Offset.zero)
            .dx;
    expect(typeLeft - sourceLeft, lessThan(700), reason: '任务来源列在超宽视口下必须收束');
    expect(tester.takeException(), isNull);
  });
}

FileBrowserState _seededState(FileManagerSection section) {
  return FileBrowserState(
    section: section,
    files: const <FileNode>[],
    recycleBin: const <FileNode>[
      FileNode(
        id: 'file-trashed',
        parentId: null,
        name: 'trashed.zip',
        isFolder: false,
        nodeType: 'FILE',
        normalizedPath: '/trashed.zip',
        sizeBytes: 512,
        updatedAt: null,
      ),
    ],
    recentFiles: const <FileNode>[
      FileNode(
        id: 'file-recent',
        parentId: null,
        name: 'recent-note.txt',
        isFolder: false,
        nodeType: 'FILE',
        normalizedPath: '/docs/recent-note.txt',
        sizeBytes: 256,
        updatedAt: null,
      ),
    ],
    favoriteFiles: const <FileNode>[
      FileNode(
        id: 'file-fav',
        parentId: null,
        name: 'fav-photo.jpg',
        isFolder: false,
        nodeType: 'FILE',
        normalizedPath: '/pics/fav-photo.jpg',
        sizeBytes: 5120,
        mimeType: 'image/jpeg',
        updatedAt: null,
      ),
    ],
    sharedWithMe: [
      SharedFileItem(
        shareId: 'share-1',
        ownerUserId: 'admin',
        sharedAt: null,
        expiresAt: DateTime(2026, 12, 31, 8, 30),
        file: FileNode(
          id: 'file-shared',
          parentId: null,
          name: 'shared-note.txt',
          isFolder: false,
          nodeType: 'FILE',
          normalizedPath: '/shared-note.txt',
          sizeBytes: 2048,
          updatedAt: null,
          uploaderName: 'ataraxy',
        ),
      ),
    ],
    myShares: [_seedShare()],
    shareLinks: [_seedShare()],
    uploadQueue: const [
      FileUploadQueueItem(
        id: 'uq-1',
        uploadId: 'upload-1',
        fileName: 'queue-upload.zip',
        sizeBytes: 4096,
        partSizeBytes: 1024,
        totalParts: 4,
        uploadedParts: 2,
        status: 'UPLOADING',
      ),
    ],
    localUploadTasks: const [
      FileUploadClientTask(
        id: 'local-1',
        fileName: 'local-upload.bin',
        sizeBytes: 8192,
        uploadedBytes: 4096,
        status: 'RUNNING',
      ),
    ],
    offlineTasks: const [
      OfflineDownloadTask(
        id: 'od-1',
        sourceUri: 'https://example.com/movie.mkv',
        fileName: 'offline-movie.mkv',
        status: 'DOWNLOADING',
        totalBytes: 1000,
        completedBytes: 400,
        downloadSpeedBytes: 100,
      ),
    ],
    externalAccounts: const [
      ExternalStorageAccount(
        id: 'ext-1',
        provider: 'webdav',
        displayName: 'NAS',
        status: 'CONNECTED',
      ),
    ],
    importTasks: const [
      ImportTask(
        id: 'imp-1',
        externalAccountId: 'ext-1',
        sourcePath: '/media/external-album.zip',
        fileName: 'external-album.zip',
        status: 'RUNNING',
        totalBytes: 1000,
        transferredBytes: 500,
      ),
    ],
  );
}

FileShareLink _seedShare() {
  return const FileShareLink(
    id: 'share-seed',
    resourceType: 'FILE',
    resourceId: 'file-1',
    resourceName: 'share-target.mkv',
    shareCode: 'AB12CD34',
    status: 'ACTIVE',
    accessCount: 0,
    createdAt: null,
  );
}

class _SeededController extends FileBrowserController {
  _SeededController(this.initialState);

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
