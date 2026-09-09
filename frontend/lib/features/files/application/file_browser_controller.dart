import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/files/domain/upload_part_size.dart';

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
  return ref.watch(fileApiProvider).storageStats();
});

enum _UploadFileResult { completed, conflict, failed, paused, cancelled }

class FileBrowserController extends AsyncNotifier<FileBrowserState> {
  FileRepository get _repository => ref.read(fileRepositoryProvider);
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
  int _externalBrowseRequestGeneration = 0;

  @override
  Future<FileBrowserState> build() async {
    ref.onDispose(() {
      _uploadQueuePollTimer?.cancel();
      _uploadQueuePollTimer = null;
      _importTaskPollTimer?.cancel();
      _importTaskPollTimer = null;
    });
    final filesPage = await _repository.listFilesPage();
    final stats = await _repository.storageStats();
    List<FileUploadQueueItem> uploadQueue = const [];
    try {
      uploadQueue = await _repository.listUploadQueue();
    } on Exception {
      // 上传队列获取失败不影响主初始化
    }
    return FileBrowserState(
      files: filesPage.items,
      recycleBin: const [],
      storageStats: stats,
      uploadQueue: uploadQueue,
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

  Future<T> _runAction<T>(
    String operationLabel,
    Future<T> Function() action,
  ) async {
    _setBusy(operationLabel);
    try {
      final result = await action();
      _clearBusy();
      return result;
    } catch (error) {
      _recordActionError(operationLabel, error);
      _clearBusy();
      rethrow;
    }
  }

  void _setBusy(String operationLabel) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        activeActionCount: current.activeActionCount + 1,
        activeOperationLabel: operationLabel,
        clearLastActionError: true,
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
      ),
    );
  }

  void _recordActionError(String operationLabel, Object error) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final described = describeUserFacingError(error);
    state = AsyncData(
      current.copyWith(
        lastActionError: FileBrowserActionError(
          operationLabel: operationLabel,
          message: described.message,
          code: described.code,
        ),
      ),
    );
  }

  /// 刷新文件列表数据，保留当前分区、目录与筛选条件。
  Future<void> refreshFiles() async {
    await _runAction('刷新文件列表', () async {
      final current = state.asData?.value;
      final parentId = current?.parentId;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final isShared = current?.spaceType == 'SHARED';

      final filesPage = await _listFilePageForSpace(
        spaceType: isShared ? 'SHARED' : 'PERSONAL',
        parentId: parentId,
        category: category,
      );

      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          files: filesPage.items,
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  /// 按当前分区刷新文件节点列表，不改变导航分区。
  Future<void> refreshFileNodesForCurrentSection() async {
    final section = _currentState?.section;
    switch (section) {
      case FileManagerSection.recent:
        final recentFiles = await _repository.listRecentFiles();
        final current = _currentState;
        if (current != null) {
          _emitState(current.copyWith(recentFiles: recentFiles));
        }
      case FileManagerSection.favorites:
        final favoriteFiles = await _repository.listFavoriteFiles();
        final current = _currentState;
        if (current != null) {
          _emitState(current.copyWith(favoriteFiles: favoriteFiles));
        }
      case FileManagerSection.recycleBin:
        final spaceType = _currentState?.spaceType ?? 'PERSONAL';
        final recycleBin = await _repository.listRecycleBin(
          spaceType: spaceType,
        );
        final current = _currentState;
        if (current != null) {
          _emitState(current.copyWith(recycleBin: recycleBin));
        }
      default:
        await refreshFiles();
    }
  }

  /// 按当前分区刷新远端数据，不改变目录、视图模式和筛选条件。
  Future<void> refreshForRealtime() async {
    final current = state.asData?.value;
    if (current == null) return;
    await loadSection(current.section);
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
    await _runAction('切换空间', () async {
      final current = state.asData?.value;
      if (current == null) return;

      final FileNodePage filesPage;
      SharedSpaceUsage? usage;
      if (newSpaceType == 'SHARED') {
        filesPage = await _repository.listSharedSpaceFilesPage();
        usage = await _repository.getSharedSpaceUsage();
      } else {
        filesPage = await _repository.listFilesPage();
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

  Future<void> loadSection(FileManagerSection section) async {
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

  Future<void> showRecentFiles() async {
    _clearSelection();
    await _runAction('加载最近文件', () async {
      final current = state.asData?.value;
      final recentFiles = await _repository.listRecentFiles();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          recentFiles: recentFiles,
          section: FileManagerSection.recent,
          searchQuery: '',
        ),
      );
    });
  }

  Future<void> showFavoriteFiles() async {
    _clearSelection();
    await _runAction('加载收藏文件', () async {
      final current = state.asData?.value;
      final favoriteFiles = await _repository.listFavoriteFiles();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          favoriteFiles: favoriteFiles,
          section: FileManagerSection.favorites,
          searchQuery: '',
        ),
      );
    });
  }

  Future<void> showRecycleBin() async {
    _clearSelection();
    await _runAction('加载回收站', () async {
      final current = state.asData?.value;
      final spaceType = current?.spaceType ?? 'PERSONAL';
      final recycleBin = await _repository.listRecycleBin(spaceType: spaceType);
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          recycleBin: recycleBin,
          section: FileManagerSection.recycleBin,
          searchQuery: '',
        ),
      );
    });
  }

  Future<void> showSharedWithMe() async {
    await _runAction('加载共享文件', () async {
      final current = state.asData?.value;
      final sharedWithMe = await _repository.listSharedWithMe();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedWithMe: sharedWithMe,
          section: FileManagerSection.sharedWithMe,
        ),
      );
    });
  }

  Future<void> showSharedSpace() async {
    _clearSelection();
    await _runAction('加载共享空间', () async {
      final current = state.asData?.value;
      final files = await _repository.listSharedSpaceFiles();
      final usage = await _repository.getSharedSpaceUsage();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceFiles: files,
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
    await _runAction('打开共享空间文件夹', () async {
      final current = state.asData?.value;
      final files = await _repository.listSharedSpaceFiles(parentId: folder.id);
      final currentBreadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceFiles: files,
          sharedSpaceBreadcrumbs: [...currentBreadcrumbs, folder],
        ),
      );
    });
  }

  Future<void> goToSharedSpaceBreadcrumb(int index) async {
    _clearSelection();
    final current = state.asData?.value;
    final breadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
    if (index < 0 || index > breadcrumbs.length) return;
    final targetBreadcrumbs = breadcrumbs.sublist(0, index);
    final parentId =
        targetBreadcrumbs.isEmpty ? null : targetBreadcrumbs.last.id;
    await _runAction('返回共享空间上级', () async {
      final files = await _repository.listSharedSpaceFiles(parentId: parentId);
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceFiles: files,
          sharedSpaceBreadcrumbs: targetBreadcrumbs,
        ),
      );
    });
  }

  Future<void> moveToSharedSpace(FileNode file) async {
    await _runAction('移到共享空间', () async {
      await _repository.moveToSharedSpace(file.id);
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> moveToPersonalSpace(FileNode file) async {
    await _runAction('移到个人空间', () async {
      await _repository.moveToPersonalSpace(file.id);
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> createSharedFolder(String name) async {
    await _runAction('创建共享空间文件夹', () async {
      final current = state.asData?.value;
      final parentId =
          current?.sharedSpaceBreadcrumbs.isEmpty ?? true
              ? null
              : current!.sharedSpaceBreadcrumbs.last.id;
      await _repository.createSharedFolder(parentId: parentId, name: name);
      final files = await _repository.listSharedSpaceFiles(parentId: parentId);
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceFiles: files,
        ),
      );
    });
  }

  Future<void> deleteSharedFile(FileNode file) async {
    await _runAction('删除共享空间文件', () async {
      await _repository.deleteSharedFile(file.id);
      final current = state.asData?.value;
      final parentId =
          current?.sharedSpaceBreadcrumbs.isEmpty ?? true
              ? null
              : current!.sharedSpaceBreadcrumbs.last.id;
      final files = await _repository.listSharedSpaceFiles(parentId: parentId);
      final usage = await _repository.getSharedSpaceUsage();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          sharedSpaceFiles: files,
          sharedSpaceUsage: usage,
        ),
      );
    });
  }

  Future<void> showMyShares() async {
    await _runAction('加载我的分享', () async {
      final current = state.asData?.value;
      final myShares = await _repository.listMyShares();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          myShares: myShares,
          section: FileManagerSection.myShares,
        ),
      );
    });
  }

  Future<void> showShareLinks() async {
    await _runAction('加载分享链接', () async {
      final current = state.asData?.value;
      final shareLinks = await _repository.listShareLinks();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          shareLinks: shareLinks,
          section: FileManagerSection.shareManagement,
        ),
      );
    });
  }

  Future<void> showStorageStats() async {
    await _runAction('加载存储统计', () async {
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

  Future<void> showUploadQueue() async {
    await _runAction('加载上传队列', () async {
      final current = state.asData?.value;
      final uploadQueue = await _repository.listUploadQueue();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          uploadQueue: uploadQueue,
          section: FileManagerSection.uploadQueue,
        ),
      );
    });
  }

  Future<void> showOfflineDownloads() async {
    await _runAction('加载离线下载', () async {
      final current = state.asData?.value;
      final offlineTasks = await _repository.listOfflineDownloads();
      state = AsyncData(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          offlineTasks: offlineTasks,
          section: FileManagerSection.offlineDownloads,
        ),
      );
    });
  }

  Future<void> showExternalStorage() async {
    await _runAction('加载外部存储', () async {
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
    await _runAction('打开文件夹', () async {
      final current = state.asData?.value;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        parentId: folder.id,
        category: category,
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
    await _runAction('返回根目录', () async {
      final current = state.asData?.value;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        category: category,
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
    await _runAction('切换目录', () async {
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
    await _runAction('筛选文件类型', () async {
      final current = state.asData?.value;
      final categoryForRequest = category;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        parentId: current?.parentId,
        category: categoryForRequest,
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
    int size = 100,
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

  Future<void> loadMoreFiles() async {
    final current = state.asData?.value;
    if (current == null ||
        current.isLoadingMoreFiles ||
        !current.hasMoreFiles ||
        current.section != FileManagerSection.allFiles) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMoreFiles: true));
    try {
      final page = await _listFilePageForSpace(
        spaceType: current.spaceType,
        parentId: current.parentId,
        category: current.fileCategory,
        page: current.filePage + 1,
        size: current.filePageSize,
      );
      final latest = state.asData?.value;
      if (latest == null ||
          latest.parentId != current.parentId ||
          latest.spaceType != current.spaceType ||
          latest.fileCategory != current.fileCategory) {
        return;
      }
      final existingIds = latest.files.map((file) => file.id).toSet();
      state = AsyncData(
        latest.copyWith(
          files: [
            ...latest.files,
            ...page.items.where((file) => existingIds.add(file.id)),
          ],
          filePage: page.page,
          filePageSize: page.size,
          fileTotalElements: page.totalElements,
          fileTotalPages: page.totalPages,
          isLoadingMoreFiles: false,
        ),
      );
    } catch (error) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(isLoadingMoreFiles: false));
      }
      _recordActionError('加载更多文件', error);
      rethrow;
    }
  }
}

class _UploadRuntime {
  _UploadRuntime({required this.file, required this.session});

  final XFile file;
  final FileUploadSession session;
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
