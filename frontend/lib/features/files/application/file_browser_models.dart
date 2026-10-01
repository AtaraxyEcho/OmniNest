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
    this.sharedSpaceBreadcrumbs = const [],
    this.sharedSpaceUsage,
    this.sharedWithMe = const [],
    this.sharedWithMeMeta = const FilesSubPageMeta(),
    this.myShares = const [],
    this.shareLinks = const [],
    this.sharesMeta = const FilesSubPageMeta(),
    this.uploadQueueMeta = const FilesSubPageMeta(),
    this.offlineMeta = const FilesSubPageMeta(),
    this.importMeta = const FilesSubPageMeta(),
    this.externalMeta = const FilesSubPageMeta(),
    this.recentMeta = const FilesSubPageMeta(),
    this.favoritesMeta = const FilesSubPageMeta(),
    this.recycleMeta = const FilesSubPageMeta(),
    this.shareScopeAll = false,
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
    this.sortAscending = true,
    this.fileCategory = FileBrowserFileCategory.all,
    this.selectedFileIds = const {},
    this.inspectedFileId,
    this.inspectorOpen = true,
    this.draftFolderName,
    this.filePage = 0,
    this.filePageSize = 10,
    this.fileTotalElements = 0,
    this.fileTotalPages = 0,
    this.activeActionCount = 0,
    this.activeOperation,
    this.lastActionError,
    this.backgroundRefresh = false,
  });

  final List<FileNode> files;
  final List<FileNode> recycleBin;
  final List<FileNode> sharedSpaceBreadcrumbs;
  final SharedSpaceUsage? sharedSpaceUsage;
  final List<FileNode> breadcrumbs;
  final List<FileUploadSession> uploadSessions;
  final List<FileNode> recentFiles;
  final List<FileNode> favoriteFiles;

  /// 已收藏节点 id 集（表格/网格行内星标依据，跨分区一致）。
  Set<String> get favoriteIdSet => favoriteFiles.map((f) => f.id).toSet();

  final List<SharedFileItem> sharedWithMe;
  final FilesSubPageMeta sharedWithMeMeta;
  final List<FileShareLink> myShares;

  final List<FileShareLink> shareLinks;
  final FilesSubPageMeta sharesMeta;

  /// 合并分享页当前作用域：false=我的创建，true=全部链接（管理视角）。
  final bool shareScopeAll;
  final List<FileUploadQueueItem> uploadQueue;
  final FilesSubPageMeta uploadQueueMeta;
  final List<FileUploadClientTask> localUploadTasks;
  final List<OfflineDownloadTask> offlineTasks;
  final FilesSubPageMeta offlineMeta;
  final List<ExternalStorageAccount> externalAccounts;
  final List<ExternalFileItem> externalFiles;
  final String? externalBrowsePath;
  final String? externalBrowseAccountId;
  final ExternalSpaceUsage? externalSpace;
  final bool isExternalBrowseLoading;
  final String? externalBrowseError;
  final List<ImportTask> importTasks;
  final FilesSubPageMeta importMeta;
  final FilesSubPageMeta externalMeta;

  /// 最近/收藏/回收站分区各自的分页元数据。
  final FilesSubPageMeta recentMeta;
  final FilesSubPageMeta favoritesMeta;
  final FilesSubPageMeta recycleMeta;
  final FileStorageStats? storageStats;
  final String? parentId;
  final FileManagerSection section;
  final String spaceType;
  final String searchQuery;
  final FileBrowserViewMode viewMode;
  final FileBrowserSortBy sortBy;

  /// 排序方向：true 升序；点击已激活表头时切换。
  final bool sortAscending;
  final FileBrowserFileCategory fileCategory;
  final Set<String> selectedFileIds;

  /// Inspector 检视中的节点 id；null 表示未检视。
  final String? inspectedFileId;

  /// 详情栏开关（宽屏常驻并排 / 窄屏贴底抽屉共用）。
  final bool inspectorOpen;

  /// 就地新建文件夹草稿名；null 表示未处于新建态。
  final String? draftFolderName;

  final int filePage;
  final int filePageSize;
  final int fileTotalElements;
  final int fileTotalPages;
  final int activeActionCount;
  final FileOperation? activeOperation;
  final FileBrowserActionError? lastActionError;

  /// 后台（实时同步触发）刷新中：不切换 loading 占位符，内容原地换新。
  final bool backgroundRefresh;

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

  /// 当前检视节点：在可见集合与各分区缓存中解析，找不到返回 null。
  FileNode? get inspectedNode {
    final id = inspectedFileId;
    if (id == null) {
      return null;
    }
    final pools = [
      files,
      recycleBin,
      recentFiles,
      favoriteFiles,
      sharedSpaceBreadcrumbs,
    ];
    for (final pool in pools) {
      for (final node in pool) {
        if (node.id == id) {
          return node;
        }
      }
    }
    return null;
  }

  /// 判断指定文件是否处于选中状态。
  bool isSelected(String fileId) => selectedFileIds.contains(fileId);

  /// 基于当前状态创建仅替换指定字段的新状态。
  FileBrowserState copyWith({
    List<FileNode>? files,
    List<FileNode>? recycleBin,
    List<FileNode>? breadcrumbs,
    List<FileUploadSession>? uploadSessions,
    List<FileNode>? recentFiles,
    List<FileNode>? favoriteFiles,
    List<FileNode>? sharedSpaceBreadcrumbs,
    SharedSpaceUsage? sharedSpaceUsage,
    bool clearSharedSpaceUsage = false,
    List<SharedFileItem>? sharedWithMe,
    FilesSubPageMeta? sharedWithMeMeta,
    List<FileShareLink>? myShares,
    List<FileShareLink>? shareLinks,
    FilesSubPageMeta? sharesMeta,
    bool? shareScopeAll,
    List<FileUploadQueueItem>? uploadQueue,
    FilesSubPageMeta? uploadQueueMeta,
    List<FileUploadClientTask>? localUploadTasks,
    List<OfflineDownloadTask>? offlineTasks,
    FilesSubPageMeta? offlineMeta,
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
    FilesSubPageMeta? importMeta,
    FilesSubPageMeta? externalMeta,
    FilesSubPageMeta? recentMeta,
    FilesSubPageMeta? favoritesMeta,
    FilesSubPageMeta? recycleMeta,
    FileStorageStats? storageStats,
    Object? parentId = _copyWithUnset,
    FileManagerSection? section,
    String? spaceType,
    String? searchQuery,
    FileBrowserViewMode? viewMode,
    FileBrowserSortBy? sortBy,
    bool? sortAscending,
    FileBrowserFileCategory? fileCategory,
    Set<String>? selectedFileIds,
    Object? inspectedFileId = _copyWithUnset,
    bool? inspectorOpen,
    Object? draftFolderName = _copyWithUnset,
    int? filePage,
    int? filePageSize,
    int? fileTotalElements,
    int? fileTotalPages,
    int? activeActionCount,
    FileOperation? activeOperation,
    bool clearActiveOperationLabel = false,
    FileBrowserActionError? lastActionError,
    bool? backgroundRefresh,
    bool clearLastActionError = false,
  }) {
    return FileBrowserState(
      files: files ?? this.files,
      recycleBin: recycleBin ?? this.recycleBin,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      uploadSessions: uploadSessions ?? this.uploadSessions,
      recentFiles: recentFiles ?? this.recentFiles,
      favoriteFiles: favoriteFiles ?? this.favoriteFiles,
      sharedSpaceBreadcrumbs:
          sharedSpaceBreadcrumbs ?? this.sharedSpaceBreadcrumbs,
      sharedSpaceUsage:
          clearSharedSpaceUsage
              ? null
              : (sharedSpaceUsage ?? this.sharedSpaceUsage),
      sharedWithMe: sharedWithMe ?? this.sharedWithMe,
      sharedWithMeMeta: sharedWithMeMeta ?? this.sharedWithMeMeta,
      myShares: myShares ?? this.myShares,
      shareLinks: shareLinks ?? this.shareLinks,
      sharesMeta: sharesMeta ?? this.sharesMeta,
      shareScopeAll: shareScopeAll ?? this.shareScopeAll,
      uploadQueue: uploadQueue ?? this.uploadQueue,
      uploadQueueMeta: uploadQueueMeta ?? this.uploadQueueMeta,
      localUploadTasks: localUploadTasks ?? this.localUploadTasks,
      offlineTasks: offlineTasks ?? this.offlineTasks,
      offlineMeta: offlineMeta ?? this.offlineMeta,
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
      importMeta: importMeta ?? this.importMeta,
      externalMeta: externalMeta ?? this.externalMeta,
      recentMeta: recentMeta ?? this.recentMeta,
      favoritesMeta: favoritesMeta ?? this.favoritesMeta,
      recycleMeta: recycleMeta ?? this.recycleMeta,
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
      sortAscending: sortAscending ?? this.sortAscending,
      fileCategory: fileCategory ?? this.fileCategory,
      selectedFileIds: selectedFileIds ?? this.selectedFileIds,
      inspectedFileId:
          identical(inspectedFileId, _copyWithUnset)
              ? this.inspectedFileId
              : inspectedFileId as String?,
      inspectorOpen: inspectorOpen ?? this.inspectorOpen,
      draftFolderName:
          identical(draftFolderName, _copyWithUnset)
              ? this.draftFolderName
              : draftFolderName as String?,
      filePage: filePage ?? this.filePage,
      filePageSize: filePageSize ?? this.filePageSize,
      fileTotalElements: fileTotalElements ?? this.fileTotalElements,
      fileTotalPages: fileTotalPages ?? this.fileTotalPages,
      activeActionCount: activeActionCount ?? this.activeActionCount,
      activeOperation:
          clearActiveOperationLabel
              ? null
              : activeOperation ?? this.activeOperation,
      lastActionError:
          clearLastActionError ? null : lastActionError ?? this.lastActionError,
      backgroundRefresh: backgroundRefresh ?? this.backgroundRefresh,
    );
  }

  int _compareNodes(FileNode left, FileNode right) {
    if (left.isFolder != right.isFolder) {
      return left.isFolder ? -1 : 1;
    }
    var result = switch (sortBy) {
      FileBrowserSortBy.name => left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      ),
      FileBrowserSortBy.updatedAt => (left.updatedAt ?? DateTime(0)).compareTo(
        right.updatedAt ?? DateTime(0),
      ),
      FileBrowserSortBy.size => left.sizeBytes.compareTo(right.sizeBytes),
    };
    // 升序方向下时间与大小按业务习惯倒序查看（最新/最大在前）。
    final effectiveAscending = switch (sortBy) {
      FileBrowserSortBy.updatedAt || FileBrowserSortBy.size => !sortAscending,
      _ => sortAscending,
    };
    if (!effectiveAscending) {
      result = -result;
    }
    return result;
  }
}

/// 将文件类型筛选条件转换为后端接口参数。
extension FileBrowserFileCategoryApi on FileBrowserFileCategory {
  String? get apiValue {
    return this == FileBrowserFileCategory.all ? null : name;
  }
}
