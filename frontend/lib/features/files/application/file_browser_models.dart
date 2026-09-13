import 'package:dio/dio.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';

/// 软删除同名文件冲突信息。
class SoftDeleteConflict {
  const SoftDeleteConflict({
    required this.softDeletedFileId,
    required this.fileName,
    required this.deletedAt,
  });

  final String softDeletedFileId;
  final String fileName;
  final String deletedAt;

  /// 从 DioException 的 409 响应中解析冲突信息。
  static SoftDeleteConflict? fromDioException(DioException error) {
    if (error.response?.statusCode != 409) return null;
    final data = error.response?.data;
    if (data is! Map) return null;
    final details = data['details'];
    if (details is! Map) return null;
    final fileId = details['softDeletedFileId'] as String?;
    final name = details['fileName'] as String?;
    final deleted = details['deletedAt'] as String?;
    if (fileId == null || name == null) return null;
    return SoftDeleteConflict(
      softDeletedFileId: fileId,
      fileName: name,
      deletedAt: deleted ?? '',
    );
  }
}

/// 文件浏览器的列表展示模式。
enum FileBrowserViewMode { list, grid }

/// 文件浏览器支持的排序字段。
enum FileBrowserSortBy { name, updatedAt, size }

/// 文件浏览器支持的文件类型筛选条件。
enum FileBrowserFileCategory {
  all,
  image,
  video,
  audio,
  document,
  novel,
  comic,
  archive,
  other,
}

/// 文件管理器的功能分区。
enum FileManagerSection {
  allFiles,
  recent,
  favorites,
  recycleBin,
  sharedSpace,
  sharedWithMe,
  myShares,
  shareManagement,
  storageStats,
  uploadQueue,
  offlineDownloads,
  externalStorage,
  importTasks,
}

const _copyWithUnset = Object();

/// 当前文件集合的统计摘要。
class FileBrowserStats {
  const FileBrowserStats({
    required this.folderCount,
    required this.fileCount,
    required this.totalSizeBytes,
  });

  final int folderCount;
  final int fileCount;
  final int totalSizeBytes;
}

/// 文件操作失败后供界面展示的稳定错误信息。
class FileBrowserActionError {
  const FileBrowserActionError({
    required this.operation,
    required this.message,
    this.code,
  });

  final FileOperation operation;
  final String message;
  final String? code;

  String get displayMessage =>
      code == null || code!.isEmpty ? message : '$message（$code）';
}

/// 一批文件上传完成后的结果摘要。
class FileUploadBatchResult {
  const FileUploadBatchResult({
    required this.total,
    required this.completed,
    required this.conflicts,
    required this.failed,
    required this.paused,
  });

  final int total;
  final int completed;
  final int conflicts;
  final int failed;
  final int paused;
}

/// 文件浏览器持有的不可变界面状态。
class FileBrowserState {
  const FileBrowserState({
    required this.files,
    required this.recycleBin,
    this.breadcrumbs = const [],
    this.uploadSessions = const [],
    this.recentFiles = const [],
    this.favoriteFiles = const [],
    this.sharedSpaceFiles = const [],
    this.sharedSpaceBreadcrumbs = const [],
    this.sharedSpaceUsage,
    this.sharedWithMe = const [],
    this.myShares = const [],
    this.shareLinks = const [],
    this.uploadQueue = const [],
    this.localUploadTasks = const [],
    this.offlineTasks = const [],
    this.externalAccounts = const [],
    this.externalFiles = const [],
    this.externalBrowsePath,
    this.externalBrowseAccountId,
    this.externalSpace,
    this.isExternalBrowseLoading = false,
    this.externalBrowseError,
    this.importTasks = const [],
    this.storageStats,
    this.parentId,
    this.section = FileManagerSection.allFiles,
    this.spaceType = 'PERSONAL',
    this.searchQuery = '',
    this.viewMode = FileBrowserViewMode.list,
    this.sortBy = FileBrowserSortBy.name,
    this.fileCategory = FileBrowserFileCategory.all,
    this.selectedFileIds = const {},
    this.filePage = 0,
    this.filePageSize = 100,
    this.fileTotalElements = 0,
    this.fileTotalPages = 0,
    this.isLoadingMoreFiles = false,
    this.activeActionCount = 0,
    this.activeOperation,
    this.lastActionError,
  });

  final List<FileNode> files;
  final List<FileNode> recycleBin;
  final List<FileNode> sharedSpaceFiles;
  final List<FileNode> sharedSpaceBreadcrumbs;
  final SharedSpaceUsage? sharedSpaceUsage;
  final List<FileNode> breadcrumbs;
  final List<FileUploadSession> uploadSessions;
  final List<FileNode> recentFiles;
  final List<FileNode> favoriteFiles;
  final List<SharedFileItem> sharedWithMe;
  final List<FileShareLink> myShares;
  final List<FileShareLink> shareLinks;
  final List<FileUploadQueueItem> uploadQueue;
  final List<FileUploadClientTask> localUploadTasks;
  final List<OfflineDownloadTask> offlineTasks;
  final List<ExternalStorageAccount> externalAccounts;
  final List<ExternalFileItem> externalFiles;
  final String? externalBrowsePath;
  final String? externalBrowseAccountId;
  final ExternalSpaceUsage? externalSpace;
  final bool isExternalBrowseLoading;
  final String? externalBrowseError;
  final List<ImportTask> importTasks;
  final FileStorageStats? storageStats;
  final String? parentId;
  final FileManagerSection section;
  final String spaceType;
  final String searchQuery;
  final FileBrowserViewMode viewMode;
  final FileBrowserSortBy sortBy;
  final FileBrowserFileCategory fileCategory;
  final Set<String> selectedFileIds;
  final int filePage;
  final int filePageSize;
  final int fileTotalElements;
  final int fileTotalPages;
  final bool isLoadingMoreFiles;
  final int activeActionCount;
  final FileOperation? activeOperation;
  final FileBrowserActionError? lastActionError;

  static const Set<String> _terminalUploadStatuses = {
    'COMPLETED',
    'CANCELLED',
    'CANCELED',
    'EXPIRED',
    'FAILED',
    'CONFLICT',
  };

  /// 判断上传状态是否已经进入终态。
  static bool isTerminalUploadStatus(String status) {
    return _terminalUploadStatuses.contains(status.toUpperCase());
  }

  bool get isBusy => activeActionCount > 0;

  List<FileUploadClientTask> get inlineUploadTasks {
    return localUploadTasks
        .where((task) => !isTerminalUploadStatus(task.status))
        .toList();
  }

  int get uploadQueueBadgeCount {
    final localTasks = inlineUploadTasks;
    final localUploadIds =
        localTasks
            .map((task) => task.uploadId)
            .whereType<String>()
            .where((uploadId) => uploadId.isNotEmpty)
            .toSet();
    final serverQueueCount =
        uploadQueue
            .where((item) => !isTerminalUploadStatus(item.status))
            .where((item) => !localUploadIds.contains(item.uploadId))
            .length;
    return localTasks.length + serverQueueCount;
  }

  List<FileNode> get visibleNodes {
    final source = switch (section) {
      FileManagerSection.recent => recentFiles,
      FileManagerSection.favorites => favoriteFiles,
      FileManagerSection.recycleBin => recycleBin,
      _ => files,
    };
    final query = searchQuery.trim().toLowerCase();
    final filtered =
        query.isEmpty
            ? source
            : source
                .where(
                  (node) =>
                      node.name.toLowerCase().contains(query) ||
                      node.normalizedPath.toLowerCase().contains(query) ||
                      (node.mimeType ?? '').toLowerCase().contains(query),
                )
                .toList();
    final sorted = [...filtered]..sort(_compareNodes);
    return sorted;
  }

  FileBrowserStats get stats {
    final source = switch (section) {
      FileManagerSection.recent => recentFiles,
      FileManagerSection.favorites => favoriteFiles,
      FileManagerSection.recycleBin => recycleBin,
      _ => files,
    };
    return FileBrowserStats(
      folderCount: source.where((node) => node.isFolder).length,
      fileCount: source.where((node) => !node.isFolder).length,
      totalSizeBytes: source.fold(0, (total, node) => total + node.sizeBytes),
    );
  }

  bool get hasSelection => selectedFileIds.isNotEmpty;
  int get selectionCount => selectedFileIds.length;

  /// 判断指定文件是否处于选中状态。
  bool isSelected(String fileId) => selectedFileIds.contains(fileId);

  bool get hasMoreFiles => filePage + 1 < fileTotalPages;

  /// 基于当前状态创建仅替换指定字段的新状态。
  FileBrowserState copyWith({
    List<FileNode>? files,
    List<FileNode>? recycleBin,
    List<FileNode>? breadcrumbs,
    List<FileUploadSession>? uploadSessions,
    List<FileNode>? recentFiles,
    List<FileNode>? favoriteFiles,
    List<FileNode>? sharedSpaceFiles,
    List<FileNode>? sharedSpaceBreadcrumbs,
    SharedSpaceUsage? sharedSpaceUsage,
    bool clearSharedSpaceUsage = false,
    List<SharedFileItem>? sharedWithMe,
    List<FileShareLink>? myShares,
    List<FileShareLink>? shareLinks,
    List<FileUploadQueueItem>? uploadQueue,
    List<FileUploadClientTask>? localUploadTasks,
    List<OfflineDownloadTask>? offlineTasks,
    List<ExternalStorageAccount>? externalAccounts,
    List<ExternalFileItem>? externalFiles,
    Object? externalBrowsePath = _copyWithUnset,
    Object? externalBrowseAccountId = _copyWithUnset,
    ExternalSpaceUsage? externalSpace,
    bool clearExternalSpace = false,
    bool? isExternalBrowseLoading,
    String? externalBrowseError,
    bool clearExternalBrowseError = false,
    List<ImportTask>? importTasks,
    FileStorageStats? storageStats,
    Object? parentId = _copyWithUnset,
    FileManagerSection? section,
    String? spaceType,
    String? searchQuery,
    FileBrowserViewMode? viewMode,
    FileBrowserSortBy? sortBy,
    FileBrowserFileCategory? fileCategory,
    Set<String>? selectedFileIds,
    int? filePage,
    int? filePageSize,
    int? fileTotalElements,
    int? fileTotalPages,
    bool? isLoadingMoreFiles,
    int? activeActionCount,
    FileOperation? activeOperation,
    bool clearActiveOperationLabel = false,
    FileBrowserActionError? lastActionError,
    bool clearLastActionError = false,
  }) {
    return FileBrowserState(
      files: files ?? this.files,
      recycleBin: recycleBin ?? this.recycleBin,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      uploadSessions: uploadSessions ?? this.uploadSessions,
      recentFiles: recentFiles ?? this.recentFiles,
      favoriteFiles: favoriteFiles ?? this.favoriteFiles,
      sharedSpaceFiles: sharedSpaceFiles ?? this.sharedSpaceFiles,
      sharedSpaceBreadcrumbs:
          sharedSpaceBreadcrumbs ?? this.sharedSpaceBreadcrumbs,
      sharedSpaceUsage:
          clearSharedSpaceUsage
              ? null
              : (sharedSpaceUsage ?? this.sharedSpaceUsage),
      sharedWithMe: sharedWithMe ?? this.sharedWithMe,
      myShares: myShares ?? this.myShares,
      shareLinks: shareLinks ?? this.shareLinks,
      uploadQueue: uploadQueue ?? this.uploadQueue,
      localUploadTasks: localUploadTasks ?? this.localUploadTasks,
      offlineTasks: offlineTasks ?? this.offlineTasks,
      externalAccounts: externalAccounts ?? this.externalAccounts,
      externalFiles: externalFiles ?? this.externalFiles,
      externalBrowsePath:
          identical(externalBrowsePath, _copyWithUnset)
              ? this.externalBrowsePath
              : externalBrowsePath as String?,
      externalBrowseAccountId:
          identical(externalBrowseAccountId, _copyWithUnset)
              ? this.externalBrowseAccountId
              : externalBrowseAccountId as String?,
      externalSpace:
          clearExternalSpace ? null : (externalSpace ?? this.externalSpace),
      isExternalBrowseLoading:
          isExternalBrowseLoading ?? this.isExternalBrowseLoading,
      externalBrowseError:
          clearExternalBrowseError
              ? null
              : externalBrowseError ?? this.externalBrowseError,
      importTasks: importTasks ?? this.importTasks,
      storageStats: storageStats ?? this.storageStats,
      parentId:
          identical(parentId, _copyWithUnset)
              ? this.parentId
              : parentId as String?,
      section: section ?? this.section,
      spaceType: spaceType ?? this.spaceType,
      searchQuery: searchQuery ?? this.searchQuery,
      viewMode: viewMode ?? this.viewMode,
      sortBy: sortBy ?? this.sortBy,
      fileCategory: fileCategory ?? this.fileCategory,
      selectedFileIds: selectedFileIds ?? this.selectedFileIds,
      filePage: filePage ?? this.filePage,
      filePageSize: filePageSize ?? this.filePageSize,
      fileTotalElements: fileTotalElements ?? this.fileTotalElements,
      fileTotalPages: fileTotalPages ?? this.fileTotalPages,
      isLoadingMoreFiles: isLoadingMoreFiles ?? this.isLoadingMoreFiles,
      activeActionCount: activeActionCount ?? this.activeActionCount,
      activeOperation:
          clearActiveOperationLabel
              ? null
              : activeOperation ?? this.activeOperation,
      lastActionError:
          clearLastActionError ? null : lastActionError ?? this.lastActionError,
    );
  }

  int _compareNodes(FileNode left, FileNode right) {
    if (left.isFolder != right.isFolder) {
      return left.isFolder ? -1 : 1;
    }
    return switch (sortBy) {
      FileBrowserSortBy.name => left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      ),
      FileBrowserSortBy.updatedAt => (right.updatedAt ?? DateTime(0)).compareTo(
        left.updatedAt ?? DateTime(0),
      ),
      FileBrowserSortBy.size => right.sizeBytes.compareTo(left.sizeBytes),
    };
  }
}

/// 将文件类型筛选条件转换为后端接口参数。
extension FileBrowserFileCategoryApi on FileBrowserFileCategory {
  String? get apiValue {
    return this == FileBrowserFileCategory.all ? null : name;
  }
}
