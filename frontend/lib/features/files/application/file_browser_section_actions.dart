part of 'file_browser_controller.dart';

/// 分区内容加载、分页续载与共享/存储列表动作。
extension FileBrowserSectionActions on FileBrowserController {
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

  Future<void> showFiles() async {
    _applySectionOptimistically(FileManagerSection.allFiles);
    await refreshFiles();
  }

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
      case FileManagerSection.sharedSpace:
        await showSharedSpace();
      case FileManagerSection.externalStorage:
        await showExternalStorage();
      case FileManagerSection.importTasks:
        await showImportTasks();
    }
  }

  Future<void> showFavoriteFiles({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.favorites);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadFavorites, () async {
      final current = _currentState;
      final meta = current?.favoritesMeta ?? const FilesSubPageMeta();
      final result = await _repository.listFavoriteFilesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          favoriteFiles: result.items,
          favoritesMeta: _metaOfNodePage(result),
        ),
      );
    });
  }

  Future<void> showRecycleBin({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.recycleBin);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadRecycleBin, () async {
      final current = _currentState;
      final spaceType = current?.spaceType ?? 'PERSONAL';
      final meta = current?.recycleMeta ?? const FilesSubPageMeta();
      final result = await _repository.listRecycleBinPage(
        spaceType: spaceType,
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          recycleBin: result.items,
          recycleMeta: _metaOfNodePage(result),
        ),
      );
    });
  }

  /// 节点型次分区的滚动续载：取当前页的下一页追加到已载入集合尾部，按节点
  /// id 去重；与主列表 [loadMoreFiles] 同语义。页翻转仍由 `show*` 系列供桌面
  /// 分页条跳页，两种语义并存不互相替换。
  Future<void> _loadMoreNodePage({
    required FileOperation operation,
    required FileManagerSection section,
    required FilesSubPageMeta Function(FileBrowserState state) metaOf,
    required List<FileNode> Function(FileBrowserState state) listOf,
    required Future<FileNodePage> Function(int page, int size) fetch,
    required FileBrowserState Function(
      FileBrowserState state,
      List<FileNode> items,
      FilesSubPageMeta meta,
    )
    emit,
  }) async {
    final current = _currentState;
    if (current == null || current.isBusy || current.section != section) {
      return;
    }
    final meta = metaOf(current);
    // 续载守卫同时看已载入条数与页边界：后者能挡住 totalElements 虚高时
    // 越界请求 page = totalPages, totalPages + 1 的空拉取死循环。
    if (listOf(current).length >= meta.totalElements ||
        meta.page + 1 >= meta.totalPages) {
      return;
    }
    await _runAction(operation, () async {
      final result = await fetch(meta.page + 1, meta.size);
      final latest = _currentState;
      if (latest == null ||
          latest.section != section ||
          metaOf(latest).page != meta.page) {
        return;
      }
      final loaded = listOf(latest);
      final seen = loaded.map((node) => node.id).toSet();
      final merged = <FileNode>[
        ...loaded,
        ...result.items.where((node) => seen.add(node.id)),
      ];
      // 空页说明服务端没有更多可见条目：把总数钳到已载入数量，阻断后续空拉取。
      final effectiveMeta =
          result.items.isEmpty
              ? FilesSubPageMeta(
                page: result.page,
                size: result.size,
                totalElements: merged.length,
                totalPages: result.page + 1,
              )
              : _metaOfNodePage(result);
      _emitState(emit(latest, merged, effectiveMeta));
    });
  }

  /// 我的收藏滚动续载。
  Future<void> loadMoreFavoriteFiles() => _loadMoreNodePage(
    operation: FileOperation.loadFavorites,
    section: FileManagerSection.favorites,
    metaOf: (state) => state.favoritesMeta,
    listOf: (state) => state.favoriteFiles,
    fetch:
        (page, size) =>
            _repository.listFavoriteFilesPage(page: page, size: size),
    emit:
        (state, items, meta) =>
            state.copyWith(favoriteFiles: items, favoritesMeta: meta),
  );

  /// 回收站滚动续载：沿用当前空间类型，不跨空间续页。
  Future<void> loadMoreRecycleBin() async {
    final spaceType = _currentState?.spaceType ?? 'PERSONAL';
    await _loadMoreNodePage(
      operation: FileOperation.loadRecycleBin,
      section: FileManagerSection.recycleBin,
      metaOf: (state) => state.recycleMeta,
      listOf: (state) => state.recycleBin,
      fetch:
          (page, size) => _repository.listRecycleBinPage(
            spaceType: spaceType,
            page: page,
            size: size,
          ),
      emit:
          (state, items, meta) =>
              state.copyWith(recycleBin: items, recycleMeta: meta),
    );
  }

  Future<void> showSharedSpace() async {
    _applySectionOptimistically(FileManagerSection.sharedSpace);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadSharedSpace, () async {
      final current = _currentState;
      final usage = await _repository.getSharedSpaceUsage();
      _emitState(
        _liveOr(
          current,
        ).copyWith(sharedSpaceUsage: usage, sharedSpaceBreadcrumbs: []),
      );
    });
  }

  Future<void> openSharedSpaceFolder(FileNode folder) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.openSharedFolder, () async {
      final current = _currentState;
      final currentBreadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
      _emitState(
        _liveOr(
          current,
        ).copyWith(sharedSpaceBreadcrumbs: [...currentBreadcrumbs, folder]),
      );
    });
  }

  Future<void> goToSharedSpaceBreadcrumb(int index) async {
    _clearSelection();
    _clearInspection();
    final current = _currentState;
    final breadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
    if (index < 0 || index > breadcrumbs.length) return;
    final targetBreadcrumbs = breadcrumbs.sublist(0, index);
    await _runAction(FileOperation.navigateSharedUp, () async {
      _emitState(
        _liveOr(current).copyWith(sharedSpaceBreadcrumbs: targetBreadcrumbs),
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

  Future<void> deleteSharedFile(FileNode file) async {
    await _runAction(FileOperation.deleteSharedFile, () async {
      await _repository.deleteSharedFile(file.id);
      // 删除后必须重拉当前目录，否则已删节点会留在共享空间列表直到手动刷新。
      await refreshFileNodesForCurrentSection();
      final current = _currentState;
      final usage = await _repository.getSharedSpaceUsage();
      _emitState(_liveOr(current).copyWith(sharedSpaceUsage: usage));
    });
  }

  Future<void> showMyShares({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.myShares);
    await _runAction(FileOperation.loadMyShares, () async {
      final current = _currentState;
      final meta = current?.sharesMeta ?? const FilesSubPageMeta();
      final result = await _repository.listMySharesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          myShares: result.items,
          sharesMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          shareScopeAll: false,
        ),
      );
    });
  }

  /// 合并分享页的“全部链接”作用域：与我的分享同页共存，
  /// 只切数据域不切 section，避免页面跳转闪烁。
  Future<void> showShareLinks({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.myShares);
    await _runAction(FileOperation.loadShareLinks, () async {
      final current = _currentState;
      final meta = current?.sharesMeta ?? const FilesSubPageMeta();
      // 全部链接与我的分享同端点同 service：直接复用分页查询。
      final result = await _repository.listMySharesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          shareLinks: result.items,
          sharesMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          shareScopeAll: true,
        ),
      );
    });
  }

  Future<void> showStorageStats() async {
    _applySectionOptimistically(FileManagerSection.storageStats);
    await _runAction(FileOperation.loadStorageStats, () async {
      final current = _currentState;
      final stats = await _repository.storageStats();
      _emitState(_liveOr(current).copyWith(storageStats: stats));
    });
  }

  Future<void> showExternalStorage() async {
    _applySectionOptimistically(FileManagerSection.externalStorage);
    await _runAction(FileOperation.loadExternalStorage, () async {
      final current = _currentState;
      final externalAccounts = await _repository.listExternalStorages();
      _emitState(_liveOr(current).copyWith(externalAccounts: externalAccounts));
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
}
