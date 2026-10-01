import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/files/domain/upload_part_size.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';

export 'package:omninest/features/files/data/file_providers.dart';
export 'package:omninest/features/files/application/file_browser_models.dart';

part 'file_browser_selection_actions.dart';
part 'file_browser_upload_actions.dart';
part 'file_browser_integration_actions.dart';

final fileBrowserControllerProvider =
    AsyncNotifierProvider<FileBrowserController, FileBrowserState>(
      FileBrowserController.new,
    );

/// 提供文件模块的存储摘要只读视图。
final fileStorageStatsProvider = FutureProvider<FileStorageStats>((ref) {
  ref.watch(sessionEpochProvider);
  return ref.watch(fileApiProvider).storageStats();
});

enum _UploadFileResult { completed, conflict, failed, paused, cancelled }

class FileBrowserController extends AsyncNotifier<FileBrowserState> {
  FileRepository get _repository => ref.read(fileRepositoryProvider);

  /// 文件仓储（展示层版本历史对话框直接读取）。
  FileBrowserState? get _currentState => state.asData?.value;

  void _emitState(FileBrowserState nextState) {
    state = AsyncData(nextState);
  }

  final Map<String, _UploadRuntime> _uploadRuntimes = {};
  final Map<
    String,
    ({
      SoftDeleteConflict conflict,
      XFile file,
      String fileName,
      int sizeBytes,
      String mimeType,
    })
  >
  _pendingConflicts = {};
  Timer? _uploadQueuePollTimer;
  Timer? _importTaskPollTimer;
  Timer? _offlineTaskPollTimer;
  int _externalBrowseRequestGeneration = 0;

  @override
  Future<FileBrowserState> build() async {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧值。
    ref.watch(sessionEpochProvider);
    ref.onDispose(() {
      _uploadQueuePollTimer?.cancel();
      _uploadQueuePollTimer = null;
      _importTaskPollTimer?.cancel();
      _importTaskPollTimer = null;
      _offlineTaskPollTimer?.cancel();
      _offlineTaskPollTimer = null;
    });
    final filesPage = await _repository.listFilesPage();
    final stats = await _repository.storageStats();
    List<FileUploadQueueItem> uploadQueue = const [];
    try {
      uploadQueue = await _repository.listUploadQueue();
    } on Exception {
      // 上传队列获取失败不影响主初始化
    }
    List<FileNode> favoriteFiles = const [];
    try {
      // 预载收藏列表：任意分区的行内星标都需要已收藏状态。
      favoriteFiles = await _repository.listFavoriteFiles();
    } on Object {
      // 收藏列表获取失败（含测试假体 UnimplementedError 属 Error 非
      // Exception）不影响主初始化。
    }
    return FileBrowserState(
      files: filesPage.items,
      recycleBin: const [],
      storageStats: stats,
      uploadQueue: uploadQueue,
      favoriteFiles: favoriteFiles,
      filePage: filesPage.page,
      filePageSize: filesPage.size,
      fileTotalElements: filesPage.totalElements,
      fileTotalPages: filesPage.totalPages,
    );
  }

  void clearActionError() {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearLastActionError: true));
  }

  /// 异步任务提交成功后刷新全局任务摘要徽标。
  void notifyTaskSubmitted() {
    ref.invalidate(activeTaskSummaryProvider);
  }

  Future<T> _runAction<T>(
    FileOperation operation,
    Future<T> Function() action,
  ) async {
    _setBusy(operation, background: _backgroundLoad);
    try {
      final result = await action();
      _clearBusy();
      return result;
    } catch (error) {
      _recordActionError(operation, error);
      _clearBusy();
      rethrow;
    }
  }

  /// 最近本地文件变更的自回声记录：fileId -> 过期时刻。
  /// 后端为每次节点变更（建夹/重命名/删除/恢复/移动/复制/收藏…）记录
  /// FILES 作用域同步事件，事件经实时通道回到本机会触发 FileSyncHandler
  /// 全量刷新；本地动作自身已完成状态收敛，这份“自回落”只会造成列表
  /// 闪烁刷新，须按窗口抑制。其他设备的变更没有本地记录，仍走全量刷新。
  final Map<String, DateTime> _recentFileEchoes = {};

  static const Duration _fileEchoWindow = Duration(seconds: 15);

  /// 登记一次本地文件变更（供实时回声抑制查询）。
  void registerFileEcho(Iterable<String> fileIds) {
    final expiry = DateTime.now().add(_fileEchoWindow);
    for (final fileId in fileIds) {
      _recentFileEchoes[fileId] = expiry;
    }
  }

  /// 判断一批资源是否全部命中本地回声窗口；
  /// 顺带清理过期条目。空集返回 false（保守走刷新）。
  bool matchesRecentFileEchoes(Set<String> fileIds) {
    final now = DateTime.now();
    _recentFileEchoes.removeWhere((_, expiry) => expiry.isBefore(now));
    if (fileIds.isEmpty) {
      return false;
    }
    return fileIds.every(_recentFileEchoes.containsKey);
  }

  /// 静默快操作：不进入 busy 门控（避免 0→1→0 双次全量状态发射造成
  /// 工具栏禁用态闪烁与全列表重建），仅记录失败；成功后的状态更新由
  /// 动作体自身发出（如收藏缓存刷新）。适用于毫秒级本地感知操作。
  Future<void> _runQuietAction(
    FileOperation operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      _recordActionError(operation, error);
    }
  }

  void _setBusy(FileOperation operation, {bool background = false}) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        activeActionCount: current.activeActionCount + 1,
        activeOperation: operation,
        clearLastActionError: true,
        backgroundRefresh: background,
      ),
    );
  }

  void _clearBusy() {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final nextCount =
        current.activeActionCount > 0 ? current.activeActionCount - 1 : 0;
    state = AsyncData(
      current.copyWith(
        activeActionCount: nextCount,
        clearActiveOperationLabel: nextCount == 0,
        backgroundRefresh: nextCount > 0 && current.backgroundRefresh,
      ),
    );
  }

  void _recordActionError(FileOperation operation, Object error) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final described = describeUserFacingError(error);
    state = AsyncData(
      current.copyWith(
        lastActionError: FileBrowserActionError(
          operation: operation,
          message: described.message,
          code: described.code,
        ),
      ),
    );
  }

  /// 刷新文件列表数据，保留当前分区、目录、筛选条件与当前页窗；只拉
  /// 目标页（跳页不再 0..N 串行重放，列表与分页条范围一一对应），
  /// 目标页越界（他端删尽末页）时回退到新的末页。
  Future<void> refreshFiles() async {
    await _runAction(FileOperation.refresh, () async {
      final current = state.asData?.value;
      final parentId = current?.parentId;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final isShared = current?.spaceType == 'SHARED';
      final spaceType = isShared ? 'SHARED' : 'PERSONAL';
      final pageSize = current?.filePageSize ?? 10;
      final targetPage = current?.filePage ?? 0;

      final result = await _fetchSectionPage(
        (page, size) => _listFilePageForSpace(
          spaceType: spaceType,
          parentId: parentId,
          category: category,
          page: page,
          size: size,
        ),
        page: targetPage,
        size: pageSize,
      );

      final latest = state.asData?.value;
      if (latest != null &&
          (latest.parentId != parentId ||
              latest.spaceType != current?.spaceType ||
              latest.fileCategory != category)) {
        return;
      }

      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          files: result.items,
          fileCategory: category,
          filePage: result.page,
          filePageSize: result.size,
          fileTotalElements: result.totalElements,
          fileTotalPages: result.totalPages,
        ),
      );
    });
  }

  /// 按当前分区刷新文件节点列表，不改变导航分区。最近/收藏/回收站
  /// 与主列表一样走分页接口并同步 meta，避免列表与分页条元数据发散。
  Future<void> refreshFileNodesForCurrentSection() async {
    final section = _currentState?.section;
    switch (section) {
      case FileManagerSection.recent:
        final meta = _currentState?.recentMeta ?? const FilesSubPageMeta();
        final result = await _fetchSectionPage(
          (page, size) =>
              _repository.listRecentFilesPage(page: page, size: size),
          page: meta.page,
          size: meta.size,
        );
        final current = _currentState;
        if (current != null) {
          _emitState(
            current.copyWith(
              recentFiles: result.items,
              recentMeta: _metaOfNodePage(result),
            ),
          );
        }
      case FileManagerSection.favorites:
        final meta = _currentState?.favoritesMeta ?? const FilesSubPageMeta();
        final result = await _fetchSectionPage(
          (page, size) =>
              _repository.listFavoriteFilesPage(page: page, size: size),
          page: meta.page,
          size: meta.size,
        );
        final current = _currentState;
        if (current != null) {
          _emitState(
            current.copyWith(
              favoriteFiles: result.items,
              favoritesMeta: _metaOfNodePage(result),
            ),
          );
        }
      case FileManagerSection.recycleBin:
        final meta = _currentState?.recycleMeta ?? const FilesSubPageMeta();
        final spaceType = _currentState?.spaceType ?? 'PERSONAL';
        final result = await _fetchSectionPage(
          (page, size) => _repository.listRecycleBinPage(
            spaceType: spaceType,
            page: page,
            size: size,
          ),
          page: meta.page,
          size: meta.size,
        );
        final current = _currentState;
        if (current != null) {
          _emitState(
            current.copyWith(
              recycleBin: result.items,
              recycleMeta: _metaOfNodePage(result),
            ),
          );
        }
      default:
        await refreshFiles();
    }
  }

  /// 按页窗拉取分区分页数据；末页条目被删尽导致请求页越界时，回退到
  /// 新的末页重拉，避免分页条停留并展示空页。
  Future<FileNodePage> _fetchSectionPage(
    Future<FileNodePage> Function(int page, int size) fetch, {
    required int page,
    required int size,
  }) async {
    var result = await fetch(page, size);
    if (result.items.isEmpty &&
        result.page > 0 &&
        result.page >= result.totalPages) {
      final lastPage = result.totalPages > 0 ? result.totalPages - 1 : 0;
      result = await fetch(lastPage, size);
    }
    return result;
  }

  /// 按当前分区刷新远端数据，不改变目录、视图模式和筛选条件。
  Future<void> refreshForRealtime() async {
    final current = state.asData?.value;
    if (current == null) return;
    await loadSection(current.section, background: true);
  }

  Future<void> showFiles() async {
    final current = _currentState;
    if (current != null) {
      _emitState(current.copyWith(section: FileManagerSection.allFiles));
    }
    await refreshFiles();
  }

  /// 切换个人空间/共享空间。
  Future<void> switchSpace(String newSpaceType) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.switchSpace, () async {
      final current = state.asData?.value;
      if (current == null) return;

      final FileNodePage filesPage;
      SharedSpaceUsage? usage;
      // 空间切换回第 0 页，但保留用户已选的每页条数。
      if (newSpaceType == 'SHARED') {
        filesPage = await _repository.listSharedSpaceFilesPage(
          size: current.filePageSize,
        );
        usage = await _repository.getSharedSpaceUsage();
      } else {
        filesPage = await _repository.listFilesPage(size: current.filePageSize);
      }

      state = AsyncData(
        current.copyWith(
          files: filesPage.items,
          parentId: null,
          breadcrumbs: [],
          spaceType: newSpaceType,
          section: FileManagerSection.allFiles,
          sharedSpaceUsage: usage,
          fileCategory: FileBrowserFileCategory.all,
          searchQuery: '',
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {
    _backgroundLoad = background;
    try {
      await _loadSectionInner(section);
    } finally {
      _backgroundLoad = false;
    }
  }

  /// 当前分区加载是否处于后台（实时触发）模式，供各 show* 动作读取。
  bool _backgroundLoad = false;

  Future<void> _loadSectionInner(FileManagerSection section) async {
    switch (section) {
      case FileManagerSection.allFiles:
        await showFiles();
      case FileManagerSection.recent:
        await showRecentFiles();
      case FileManagerSection.favorites:
        await showFavoriteFiles();
      case FileManagerSection.recycleBin:
        await showRecycleBin();
      case FileManagerSection.sharedWithMe:
        await showSharedWithMe();
      case FileManagerSection.myShares:
        await showMyShares();
      case FileManagerSection.shareManagement:
        await showShareLinks();
      case FileManagerSection.storageStats:
        await showStorageStats();
      case FileManagerSection.uploadQueue:
        await showUploadQueue();
      case FileManagerSection.offlineDownloads:
        await showOfflineDownloads();
      case FileManagerSection.sharedSpace:
        await showSharedSpace();
      case FileManagerSection.externalStorage:
        await showExternalStorage();
      case FileManagerSection.importTasks:
        await showImportTasks();
    }
  }

  Future<void> showRecentFiles({int? page, int? size}) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadRecent, () async {
      final current = state.asData?.value;
      final meta = current?.recentMeta ?? const FilesSubPageMeta();
      final result = await _repository.listRecentFilesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          recentFiles: result.items,
          recentMeta: _metaOfNodePage(result),
          section: FileManagerSection.recent,
          searchQuery: '',
        ),
      );
    });
  }

  Future<void> showFavoriteFiles({int? page, int? size}) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadFavorites, () async {
      final current = state.asData?.value;
      final meta = current?.favoritesMeta ?? const FilesSubPageMeta();
      final result = await _repository.listFavoriteFilesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          favoriteFiles: result.items,
          favoritesMeta: _metaOfNodePage(result),
          section: FileManagerSection.favorites,
          searchQuery: '',
        ),
      );
    });
  }

  Future<void> showRecycleBin({int? page, int? size}) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadRecycleBin, () async {
      final current = state.asData?.value;
      final spaceType = current?.spaceType ?? 'PERSONAL';
      final meta = current?.recycleMeta ?? const FilesSubPageMeta();
      final result = await _repository.listRecycleBinPage(
        spaceType: spaceType,
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          recycleBin: result.items,
          recycleMeta: _metaOfNodePage(result),
          section: FileManagerSection.recycleBin,
          searchQuery: '',
        ),
      );
    });
  }

  FilesSubPageMeta _metaOfNodePage(FileNodePage page) {
    return FilesSubPageMeta(
      page: page.page,
      size: page.size,
      totalElements: page.totalElements,
      totalPages: page.totalPages,
    );
  }

  Future<void> showSharedWithMe({int? page, int? size}) async {
    await _runAction(FileOperation.loadShared, () async {
      final current = state.asData?.value;
      final meta = current?.sharedWithMeMeta ?? const FilesSubPageMeta();
      final result = await _repository.listSharedWithMePage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedWithMe: result.items,
          sharedWithMeMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          section: FileManagerSection.sharedWithMe,
        ),
      );
    });
  }

  Future<void> showSharedSpace() async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadSharedSpace, () async {
      final current = state.asData?.value;
      final usage = await _repository.getSharedSpaceUsage();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceUsage: usage,
          sharedSpaceBreadcrumbs: [],
          section: FileManagerSection.sharedSpace,
          searchQuery: '',
        ),
      );
    });
  }

  Future<void> openSharedSpaceFolder(FileNode folder) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.openSharedFolder, () async {
      final current = state.asData?.value;
      final currentBreadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceBreadcrumbs: [...currentBreadcrumbs, folder],
        ),
      );
    });
  }

  Future<void> goToSharedSpaceBreadcrumb(int index) async {
    _clearSelection();
    _clearInspection();
    final current = state.asData?.value;
    final breadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
    if (index < 0 || index > breadcrumbs.length) return;
    final targetBreadcrumbs = breadcrumbs.sublist(0, index);
    await _runAction(FileOperation.navigateSharedUp, () async {
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceBreadcrumbs: targetBreadcrumbs,
        ),
      );
    });
  }

  Future<void> moveToSharedSpace(FileNode file) async {
    await _runAction(FileOperation.moveToSharedSpace, () async {
      await _repository.moveToSharedSpace(file.id);
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> moveToPersonalSpace(FileNode file) async {
    await _runAction(FileOperation.moveToPersonalSpace, () async {
      await _repository.moveToPersonalSpace(file.id);
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> createSharedFolder(String name) async {
    await _runAction(FileOperation.createSharedFolder, () async {
      final current = state.asData?.value;
      final parentId =
          current?.sharedSpaceBreadcrumbs.isEmpty ?? true
              ? null
              : current!.sharedSpaceBreadcrumbs.last.id;
      await _repository.createSharedFolder(parentId: parentId, name: name);
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: []))
            .copyWith(),
      );
    });
  }

  Future<void> deleteSharedFile(FileNode file) async {
    await _runAction(FileOperation.deleteSharedFile, () async {
      await _repository.deleteSharedFile(file.id);
      final current = state.asData?.value;
      final usage = await _repository.getSharedSpaceUsage();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceUsage: usage,
        ),
      );
    });
  }

  Future<void> showMyShares({int? page, int? size}) async {
    await _runAction(FileOperation.loadMyShares, () async {
      final current = state.asData?.value;
      final meta = current?.sharesMeta ?? const FilesSubPageMeta();
      final result = await _repository.listMySharesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          myShares: result.items,
          sharesMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          section: FileManagerSection.myShares,
          shareScopeAll: false,
        ),
      );
    });
  }

  /// 合并分享页的“全部链接”作用域：与我的分享同页共存，
  /// 只切数据域不切 section，避免页面跳转闪烁。
  Future<void> showShareLinks({int? page, int? size}) async {
    await _runAction(FileOperation.loadShareLinks, () async {
      final current = state.asData?.value;
      final meta = current?.sharesMeta ?? const FilesSubPageMeta();
      // 全部链接与我的分享同端点同 service：直接复用分页查询。
      final result = await _repository.listMySharesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          shareLinks: result.items,
          sharesMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          section: FileManagerSection.myShares,
          shareScopeAll: true,
        ),
      );
    });
  }

  Future<void> showStorageStats() async {
    await _runAction(FileOperation.loadStorageStats, () async {
      final current = state.asData?.value;
      final stats = await _repository.storageStats();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          storageStats: stats,
          section: FileManagerSection.storageStats,
        ),
      );
    });
  }

  Future<void> showUploadQueue({int? page, int? size}) async {
    await _runAction(FileOperation.loadUploadQueue, () async {
      final current = state.asData?.value;
      final meta = current?.uploadQueueMeta ?? const FilesSubPageMeta();
      final result = await _repository.listUploadQueuePage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          uploadQueue: result.items,
          uploadQueueMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          section: FileManagerSection.uploadQueue,
        ),
      );
    });
  }

  Future<void> showOfflineDownloads({int? page, int? size}) async {
    await _runAction(FileOperation.loadOfflineDownloads, () async {
      final current = state.asData?.value;
      final meta = current?.offlineMeta ?? const FilesSubPageMeta();
      final result = await _repository.listOfflineDownloadsPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          offlineTasks: result.items,
          offlineMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          section: FileManagerSection.offlineDownloads,
        ),
      );
    });
    _startOfflineTaskPolling();
  }

  Future<void> showExternalStorage() async {
    await _runAction(FileOperation.loadExternalStorage, () async {
      final current = state.asData?.value;
      final externalAccounts = await _repository.listExternalStorages();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          externalAccounts: externalAccounts,
          section: FileManagerSection.externalStorage,
        ),
      );
    });
  }

  Future<void> openFolder(FileNode folder) async {
    if (!folder.isFolder) {
      return;
    }
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.openFolder, () async {
      final current = state.asData?.value;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        parentId: folder.id,
        category: category,
        size: current?.filePageSize ?? 10,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          files: filesPage.items,
          parentId: folder.id,
          breadcrumbs: [...?current?.breadcrumbs, folder],
          section: FileManagerSection.allFiles,
          searchQuery: '',
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> goToRoot() async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.navigateToRoot, () async {
      final current = state.asData?.value;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        category: category,
        size: current?.filePageSize ?? 10,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          files: filesPage.items,
          parentId: null,
          breadcrumbs: const [],
          section: FileManagerSection.allFiles,
          searchQuery: '',
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> goToParent() async {
    final breadcrumbs = state.asData?.value.breadcrumbs;
    if (breadcrumbs == null || breadcrumbs.isEmpty) {
      return;
    }
    if (breadcrumbs.length == 1) {
      await goToRoot();
      return;
    }
    await goToBreadcrumb(breadcrumbs.length - 2);
  }

  Future<void> goToBreadcrumb(int index) async {
    final current = state.asData?.value;
    if (current == null || index < 0 || index >= current.breadcrumbs.length) {
      return;
    }
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.changeDirectory, () async {
      final currentState = state.asData?.value;
      if (currentState == null ||
          index < 0 ||
          index >= currentState.breadcrumbs.length) {
        return;
      }
      final target = currentState.breadcrumbs[index];
      final filesPage = await _listFilePageForSpace(
        spaceType: currentState.spaceType,
        parentId: target.id,
        category: currentState.fileCategory,
        size: currentState.filePageSize,
      );
      state = AsyncData(
        currentState.copyWith(
          files: filesPage.items,
          parentId: target.id,
          breadcrumbs: currentState.breadcrumbs.take(index + 1).toList(),
          section: FileManagerSection.allFiles,
          searchQuery: '',
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> setFileCategory(FileBrowserFileCategory category) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.filterFileType, () async {
      final current = state.asData?.value;
      final categoryForRequest = category;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        parentId: current?.parentId,
        category: categoryForRequest,
        size: current?.filePageSize ?? 10,
      );
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          files: filesPage.items,
          section: FileManagerSection.allFiles,
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<FileNodePage> _listFilePageForSpace({
    required String spaceType,
    required FileBrowserFileCategory category,
    String? parentId,
    int page = 0,
    int size = 10,
  }) {
    if (spaceType == 'SHARED') {
      return _repository.listSharedSpaceFilesPage(
        parentId: parentId,
        page: page,
        size: size,
      );
    }
    return _repository.listFilesPage(
      parentId: parentId,
      category: category.apiValue,
      page: page,
      size: size,
    );
  }

  /// 跳转到主列表指定页：refreshFiles 按目标页重放窗口（向前收缩、
  /// 向后扩页），页式导航语义；正在加载或分区不符时忽略。
  Future<void> goToFilePage(int page) async {
    final current = state.asData?.value;
    if (current == null ||
        current.isBusy ||
        page < 0 ||
        page >= current.fileTotalPages ||
        page == current.filePage) {
      return;
    }
    state = AsyncData(current.copyWith(filePage: page));
    await refreshFiles();
  }

  /// 调整主列表每页条数：回到第 0 页重放。
  Future<void> setFilePageSize(int size) async {
    final current = state.asData?.value;
    if (current == null || current.isBusy || size == current.filePageSize) {
      return;
    }
    state = AsyncData(current.copyWith(filePageSize: size, filePage: 0));
    await refreshFiles();
  }
}

class _UploadRuntime {
  _UploadRuntime({
    required this.file,
    required this.session,
    this.asVersionOfFileId,
  });

  final XFile file;
  final FileUploadSession session;

  /// 非空时完成上传后保存为目标文件的新版本，不新建文件节点。
  final String? asVersionOfFileId;
  final Set<int> completedPartNumbers = <int>{};
  bool pauseRequested = false;
  bool removed = false;
  bool running = false;
  bool completed = false;
  FileUploadCancellationToken? activeCancellation;
  DateTime lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
  int lastReportedBytes = 0;

  int get uploadedBytes {
    if (session.isDirectUpload && completed) {
      return session.sizeBytes;
    }
    return session.parts
        .where((part) => completedPartNumbers.contains(part.partNumber))
        .fold<int>(0, (total, part) => total + part.sizeBytes)
        .clamp(0, session.sizeBytes);
  }
}
