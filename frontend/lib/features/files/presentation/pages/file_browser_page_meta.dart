part of 'file_browser_page.dart';

/// Inspector 常驻 dock 的自适应阈值：窗口窄于该值时隐藏 dock，
/// 检视改走贴底抽屉，为表格保留完整宽度。
abstract final class FilesInspectorAdaptive {
  static const double dockMinWidth = 1440;

  /// 仅文件列表分区提供检视：传输/分享/存储等子页没有可检视的
  /// FileNode，常驻抽屉只会挤占空间。
  static bool sectionHasFileList(FileManagerSection section) {
    return switch (section) {
      FileManagerSection.allFiles ||
      FileManagerSection.sharedSpace ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin ||
      FileManagerSection.storageStats => true,
      _ => false,
    };
  }
}

extension FileManagerSectionMeta on FileManagerSection {
  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      FileManagerSection.allFiles => l10n.filesAllFiles,
      FileManagerSection.recent => l10n.filesRecent,
      FileManagerSection.favorites => l10n.filesFavorites,
      FileManagerSection.recycleBin => l10n.filesRecycleBin,
      FileManagerSection.sharedSpace => l10n.filesSharedSpace,
      FileManagerSection.sharedWithMe => l10n.filesSharedWithMe,
      FileManagerSection.myShares => l10n.filesMyShares,
      FileManagerSection.shareManagement => l10n.filesShareManagement,
      FileManagerSection.storageStats => l10n.filesStorageStats,
      FileManagerSection.uploadQueue => l10n.filesUploadQueue,
      FileManagerSection.externalStorage => l10n.filesExternalStorage,
      FileManagerSection.importTasks => l10n.filesImportTasks,
    };
  }

  /// 样例 FeaturePage 承载的三个次级分区：页头给 `.feature-hero` 身份块，
  /// 而不是 FolderView 的三档分段。
  bool get isSampleFeaturePage {
    return switch (this) {
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.sharedWithMe => true,
      _ => false,
    };
  }

  /// `.feature-hero-icon` 舱内图标，与样例 featureMeta 各页给的那枚同源。
  /// 只在 [isSampleFeaturePage] 为真时读取。
  OmniIconsData get featureHeroIcon {
    return switch (this) {
      FileManagerSection.recent => OmniIcons.clock,
      FileManagerSection.favorites => OmniIcons.heart,
      FileManagerSection.sharedWithMe => OmniIcons.share,
      _ => OmniIcons.download,
    };
  }

  String descriptionOf(AppLocalizations l10n) {
    return switch (this) {
      FileManagerSection.allFiles => l10n.filesAllFilesDesc,
      FileManagerSection.recent => l10n.filesRecentDesc,
      FileManagerSection.favorites => l10n.filesFavoritesDesc,
      FileManagerSection.recycleBin => l10n.filesRecycleBinDesc,
      FileManagerSection.sharedSpace => l10n.filesSharedSpaceDesc,
      FileManagerSection.sharedWithMe => l10n.filesSharedWithMeDesc,
      FileManagerSection.myShares => l10n.filesMySharesDesc,
      FileManagerSection.shareManagement => l10n.filesShareManagementDesc,
      FileManagerSection.storageStats => l10n.filesStorageStatsDesc,
      FileManagerSection.uploadQueue => l10n.filesUploadQueueDesc,
      FileManagerSection.externalStorage => l10n.filesExternalStorageDesc,
      FileManagerSection.importTasks => l10n.filesImportTasksDesc,
    };
  }

  IconData get icon {
    return switch (this) {
      FileManagerSection.allFiles => Icons.folder_open_outlined,
      FileManagerSection.recent => Icons.history_rounded,
      FileManagerSection.favorites => Icons.star_border_rounded,
      FileManagerSection.recycleBin => Icons.delete_outline_rounded,
      FileManagerSection.sharedSpace => Icons.workspaces_outlined,
      FileManagerSection.sharedWithMe => Icons.group_outlined,
      FileManagerSection.myShares => Icons.ios_share_rounded,
      FileManagerSection.shareManagement => Icons.link_rounded,
      FileManagerSection.storageStats => Icons.pie_chart_outline_rounded,
      FileManagerSection.uploadQueue => Icons.cloud_upload_outlined,
      FileManagerSection.externalStorage => Icons.cloud_queue_rounded,
      FileManagerSection.importTasks => Icons.cloud_download_rounded,
    };
  }
}

extension FileBrowserFileCategoryMeta on FileBrowserFileCategory {
  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      FileBrowserFileCategory.all => l10n.filesCategoryAll,
      FileBrowserFileCategory.image => l10n.filesCategoryImage,
      FileBrowserFileCategory.video => l10n.filesCategoryVideo,
      FileBrowserFileCategory.audio => l10n.filesCategoryAudio,
      FileBrowserFileCategory.document => l10n.filesCategoryDocument,
      FileBrowserFileCategory.novel => l10n.filesCategoryNovel,
      FileBrowserFileCategory.comic => l10n.filesCategoryComic,
      FileBrowserFileCategory.archive => l10n.filesCategoryArchive,
      FileBrowserFileCategory.other => l10n.filesCategoryOther,
    };
  }

  IconData get icon {
    return switch (this) {
      FileBrowserFileCategory.all => Icons.all_inclusive_rounded,
      FileBrowserFileCategory.image => Icons.image_outlined,
      FileBrowserFileCategory.video => Icons.movie_outlined,
      FileBrowserFileCategory.audio => Icons.library_music_outlined,
      FileBrowserFileCategory.document => Icons.description_outlined,
      FileBrowserFileCategory.novel => Icons.menu_book_outlined,
      FileBrowserFileCategory.comic => Icons.auto_stories_outlined,
      FileBrowserFileCategory.archive => Icons.inventory_2_outlined,
      FileBrowserFileCategory.other => Icons.category_outlined,
    };
  }
}

enum _FileSidebarGroup {
  files,
  sharing,
  transfer,
  storage;

  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      _FileSidebarGroup.files => l10n.filesGroupFiles,
      _FileSidebarGroup.sharing => l10n.filesGroupSharing,
      _FileSidebarGroup.transfer => l10n.filesGroupTransfer,
      _FileSidebarGroup.storage => l10n.filesGroupStorage,
    };
  }
}

const Map<_FileSidebarGroup, List<FileManagerSection>> _fileSidebarGroups = {
  _FileSidebarGroup.files: [
    FileManagerSection.allFiles,
    FileManagerSection.recent,
    FileManagerSection.favorites,
    FileManagerSection.recycleBin,
  ],
  // shareManagement 已并入 myShares（页内“我的/全部”作用域切换）。
  _FileSidebarGroup.sharing: [
    FileManagerSection.sharedWithMe,
    FileManagerSection.myShares,
  ],
  _FileSidebarGroup.transfer: [FileManagerSection.uploadQueue],
  _FileSidebarGroup.storage: [
    FileManagerSection.externalStorage,
    FileManagerSection.importTasks,
  ],
};

/// 底部导航栏目标项
enum _FileNavDestination {
  files(Icons.folder_outlined, Icons.folder),
  recent(Icons.history_rounded, Icons.history_rounded),
  shared(Icons.group_outlined, Icons.group_outlined),
  recycleBin(Icons.delete_outline_rounded, Icons.delete_outline_rounded);

  const _FileNavDestination(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      _FileNavDestination.files => l10n.filesNavFiles,
      _FileNavDestination.recent => l10n.filesNavRecent,
      _FileNavDestination.shared => l10n.filesNavShared,
      _FileNavDestination.recycleBin => l10n.filesNavRecycleBin,
    };
  }
}

/// 底部导航栏目标项对应的默认 section
FileManagerSection _defaultSectionForDestination(_FileNavDestination dest) {
  return switch (dest) {
    _FileNavDestination.files => FileManagerSection.allFiles,
    _FileNavDestination.recent => FileManagerSection.recent,
    _FileNavDestination.shared => FileManagerSection.sharedWithMe,
    _FileNavDestination.recycleBin => FileManagerSection.recycleBin,
  };
}

/// 当前 section 对应的底部导航目标项
_FileNavDestination? _destinationForSection(FileManagerSection section) {
  return switch (section) {
    FileManagerSection.allFiles ||
    FileManagerSection.favorites => _FileNavDestination.files,
    FileManagerSection.recent => _FileNavDestination.recent,
    FileManagerSection.sharedWithMe ||
    FileManagerSection.myShares ||
    FileManagerSection.shareManagement => _FileNavDestination.shared,
    FileManagerSection.recycleBin => _FileNavDestination.recycleBin,
    _ => null,
  };
}
