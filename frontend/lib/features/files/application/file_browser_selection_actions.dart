part of 'file_browser_controller.dart';

extension FileBrowserSelectionActions on FileBrowserController {
  void setSearchQuery(String query) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(current.copyWith(searchQuery: query));
  }

  void setViewMode(FileBrowserViewMode viewMode) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(current.copyWith(viewMode: viewMode));
  }

  void setSortBy(FileBrowserSortBy sortBy) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(current.copyWith(sortBy: sortBy));
  }

  /// 切换排序方向（表头点击已激活字段时触发）。
  void toggleSortAscending() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(current.copyWith(sortAscending: !current.sortAscending));
  }

  void toggleSelection(String fileId) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final ids = Set<String>.of(current.selectedFileIds);
    if (ids.contains(fileId)) {
      ids.remove(fileId);
    } else {
      ids.add(fileId);
    }
    _emitState(current.copyWith(selectedFileIds: ids));
  }

  void selectAll() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final allIds = current.visibleNodes.map((node) => node.id).toSet();
    _emitState(current.copyWith(selectedFileIds: allIds));
  }

  void clearSelection() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    if (current.selectedFileIds.isEmpty) {
      return;
    }
    _emitState(current.copyWith(selectedFileIds: const {}));
  }

  void _clearSelection() {
    final current = _currentState;
    if (current == null || current.selectedFileIds.isEmpty) {
      return;
    }
    _emitState(current.copyWith(selectedFileIds: const {}));
  }

  /// 检视节点：再次检视当前节点时 Toggle 取消并收起详情栏。
  void inspectNode(String? fileId) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    if (fileId == null || fileId == current.inspectedFileId) {
      _emitState(current.copyWith(inspectedFileId: null));
      return;
    }
    _emitState(current.copyWith(inspectedFileId: fileId, inspectorOpen: true));
  }

  /// 详情栏显隐开关（不改变检视中的节点）。
  void toggleInspector() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(current.copyWith(inspectorOpen: !current.inspectorOpen));
  }

  /// 设置详情栏开关（宽屏常驻栏自动展开使用）。
  void setInspectorOpen(bool open) {
    final current = _currentState;
    if (current == null || current.inspectorOpen == open) {
      return;
    }
    _emitState(current.copyWith(inspectorOpen: open));
  }

  void clearInspection() {
    final current = _currentState;
    if (current == null || current.inspectedFileId == null) {
      return;
    }
    _emitState(current.copyWith(inspectedFileId: null));
  }

  /// 分区/空间/目录切换时同步清空检视态。
  void _clearInspection() {
    final current = _currentState;
    if (current == null || current.inspectedFileId == null) {
      return;
    }
    _emitState(current.copyWith(inspectedFileId: null));
  }

  /// 拉取节点版本历史（Inspector 版本页共用，展示层不直连仓储）。
  Future<List<FileVersion>> listFileVersions(String fileId) {
    return _repository.listFileVersions(fileId);
  }

  /// 拉取目录选择器可进入的文件夹列表（展示层不直连仓储）。
  Future<List<FileNode>> listFolderOptions(String? parentId) {
    return _repository.listFiles(parentId: parentId);
  }

  /// 拉取外部存储可用连接器列表（展示层不直连仓储）。
  Future<List<ExternalStorageConnector>> listExternalConnectors() {
    return _repository.listExternalConnectors();
  }

  Future<void> createFolder(String name) async {
    // 回声登记放行内（新节点 ID 在响应后才知道，用父目录宽登记：
    // 建夹事件的 resourceId 是新 ID，须在 repository 响应里拿到再补记）。
    await _runAction(FileOperation.createFolder, () async {
      final current = _currentState;
      if (current?.spaceType == 'SHARED') {
        final created = await _repository.createSharedFolder(
          parentId: current?.parentId,
          name: name,
        );
        registerFileEcho([created.id]);
      } else {
        final created = await _repository.createFolder(
          parentId: current?.parentId,
          name: name,
        );
        registerFileEcho([created.id]);
      }
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> renameFile(FileNode file, String name) async {
    registerFileEcho([file.id]);
    await _runAction(FileOperation.rename, () async {
      final current = _currentState;
      if (current?.spaceType == 'SHARED') {
        await _repository.renameSharedFile(fileId: file.id, name: name);
      } else {
        await _repository.renameFile(fileId: file.id, name: name);
      }
      await refreshFileNodesForCurrentSection();
    });
  }

  /// 复制文件到目标目录（null 表示根目录）。
  Future<void> copyFile(FileNode file, String? targetParentId) async {
    registerFileEcho([file.id]);
    await _runAction(FileOperation.copy, () async {
      await _repository.copyFile(
        fileId: file.id,
        targetParentId: targetParentId,
      );
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  /// 恢复历史版本为当前内容。
  Future<void> restoreFileVersion(FileNode file, String versionId) async {
    await _runAction(FileOperation.restoreVersion, () async {
      await _repository.restoreFileVersion(
        fileId: file.id,
        versionId: versionId,
      );
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> moveFile(FileNode file, String targetParentId) async {
    registerFileEcho([file.id]);
    await _runAction(FileOperation.move, () async {
      await _repository.moveFile(fileId: file.id, parentId: targetParentId);
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<String> downloadUrl(FileNode file) async {
    return _repository.downloadUrl(file.id);
  }

  Future<void> deleteFile(FileNode file) async {
    registerFileEcho([file.id]);
    await _runAction(FileOperation.moveToRecycleBin, () async {
      final current = _currentState;
      if (current?.spaceType == 'SHARED') {
        await _repository.deleteSharedFile(file.id);
      } else {
        await _repository.deleteFile(file.id);
      }
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> restoreFile(FileNode file) async {
    registerFileEcho([file.id]);
    await _runAction(FileOperation.restore, () async {
      await _repository.restoreFile(file.id);
      await showRecycleBin();
    });
  }

  /// purge 任务提交成功后从回收站列表乐观移除对应条目。
  ///
  /// 永久删除由后端异步任务执行，整页重拉会在任务处理前把条目重新带回
  /// 列表；失败场景由任务中心呈现，不在此处轮询。
  void _removeFromRecycleBin(Set<String> fileIds) {
    final current = _currentState;
    if (current == null || fileIds.isEmpty) {
      return;
    }
    _emitState(
      current.copyWith(
        recycleBin:
            current.recycleBin
                .where((node) => !fileIds.contains(node.id))
                .toList(),
      ),
    );
  }

  Future<void> purgeFile(FileNode file) async {
    await _runAction(FileOperation.purge, () async {
      await _repository.purgeFile(file.id);
      _removeFromRecycleBin({file.id});
      notifyTaskSubmitted();
    });
  }

  Future<void> addFavorite(FileNode file) async {
    // 乐观更新：星标/列表即时翻转，不等两次网络往返（此前 ~1s 延迟
    // 正是 addFavorite + listFavoriteFiles 串行造成的）。
    registerFileEcho([file.id]);
    await _runQuietAction(FileOperation.addFavorite, () async {
      _applyLocalFavoriteChange(file.id, added: true);
      try {
        await _repository.addFavorite(file.id);
      } on Object {
        await _refreshFavoritesData();
        rethrow;
      }
    });
  }

  Future<void> removeFavorite(FileNode file) async {
    registerFileEcho([file.id]);
    await _runQuietAction(FileOperation.removeFavorite, () async {
      _applyLocalFavoriteChange(file.id, added: false);
      try {
        await _repository.removeFavorite(file.id);
      } on Object {
        await _refreshFavoritesData();
        rethrow;
      }
    });
  }

  /// 本地收藏集乐观变更：立即发射一次仅 favoriteFiles 变化的状态。
  /// 添加时若无法在已加载列表中找到节点（如未加载的分页），跳过本地
  /// 更新等待服务端刷新；移除直接剔除。失败路径由调用方回滚重拉。
  void _applyLocalFavoriteChange(String fileId, {required bool added}) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final favorites = current.favoriteFiles.toList();
    if (added) {
      if (favorites.any((f) => f.id == fileId)) {
        return;
      }
      FileNode? node;
      for (final candidate in current.visibleNodes) {
        if (candidate.id == fileId) {
          node = candidate;
          break;
        }
      }
      if (node == null) {
        return;
      }
      favorites.add(node);
    } else {
      favorites.removeWhere((f) => f.id == fileId);
    }
    _emitState(current.copyWith(favoriteFiles: favorites));
  }

  Future<void> _refreshFavoritesData() async {
    final favoriteFiles = await _repository.listFavoriteFiles();
    final current = _currentState;
    if (current == null) {
      return;
    }
    if (current.section == FileManagerSection.favorites) {
      _emitState(current.copyWith(favoriteFiles: favoriteFiles));
      return;
    }
    // 非收藏分区只静默更新收藏缓存，避免强制跳转视图。
    _emitState(current.copyWith(favoriteFiles: favoriteFiles));
  }

  Future<void> batchDeleteFiles() async {
    final echoIds = _currentState?.selectedFileIds.toList() ?? const <String>[];
    registerFileEcho(echoIds);
    final ids = _currentState?.selectedFileIds;
    if (ids == null || ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchMoveToRecycleBin, () async {
      await _repository.batchDeleteFiles(ids.toList());
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> batchRestoreFiles() async {
    final echoIds = _currentState?.selectedFileIds.toList() ?? const <String>[];
    registerFileEcho(echoIds);
    final ids = _currentState?.selectedFileIds;
    if (ids == null || ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchRestore, () async {
      await _repository.batchRestoreFiles(ids.toList());
      _clearSelection();
      await showRecycleBin();
    });
  }

  Future<void> batchPurgeFiles() async {
    final ids = _currentState?.selectedFileIds;
    if (ids == null || ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchPurge, () async {
      await _repository.batchPurgeFiles(ids.toList());
      _clearSelection();
      _removeFromRecycleBin(ids);
      notifyTaskSubmitted();
    });
  }

  Future<void> batchMoveFiles(String targetParentId) async {
    final echoIds = _currentState?.selectedFileIds.toList() ?? const <String>[];
    registerFileEcho(echoIds);
    final ids = _currentState?.selectedFileIds;
    if (ids == null || ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchMove, () async {
      await _repository.batchMoveFiles(ids.toList(), targetParentId);
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> batchAddFavorites() async {
    final ids = _currentState?.selectedFileIds;
    if (ids == null || ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchAddFavorite, () async {
      await _repository.batchAddFavorites(ids.toList());
      _clearSelection();
      await _refreshFavoritesData();
    });
  }

  Future<void> batchRemoveFavorites() async {
    final ids = _currentState?.selectedFileIds;
    if (ids == null || ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchRemoveFavorite, () async {
      await _repository.batchRemoveFavorites(ids.toList());
      _clearSelection();
      await _refreshFavoritesData();
    });
  }

  Future<FileShareLink> createShareLink(FileNode file) async {
    return _runAction(FileOperation.createShareLink, () async {
      final share = await _repository.createShareLink(
        resourceId: file.id,
        resourceType: file.isFolder ? 'FOLDER' : 'FILE',
      );
      final current = _currentState;
      if (current != null) {
        final myShares = await _repository.listMyShares();
        _emitState(current.copyWith(myShares: myShares));
      }
      return share;
    });
  }

  Future<void> revokeShare(FileShareLink share) async {
    await _runAction(FileOperation.revokeShare, () async {
      await _repository.revokeShare(share.id);
      if (_currentState?.section == FileManagerSection.shareManagement) {
        await showShareLinks();
      } else {
        await showMyShares();
      }
    });
  }
}

/// 同级目录内去重命名：重名时以数字递增补充（新建文件夹 / 新建文件夹 2 ...）。
String dedupeFolderName(String base, Iterable<FileNode> siblings) {
  final names = siblings.where((n) => n.isFolder).map((n) => n.name).toSet();
  if (!names.contains(base)) {
    return base;
  }
  var index = 2;
  while (names.contains('$base $index')) {
    index++;
  }
  return '$base $index';
}

/// 就地新建文件夹草稿态。
extension FileBrowserFolderDraftActions on FileBrowserController {
  /// 进入新建态：[baseName] 为本地化默认名（调用侧先经 dedupeFolderName 去重）。
  void beginFolderCreation(String baseName) {
    final current = _currentState;
    if (current == null || current.draftFolderName != null) {
      return;
    }
    _emitState(current.copyWith(draftFolderName: baseName));
  }

  void cancelFolderCreation() {
    final current = _currentState;
    if (current == null || current.draftFolderName == null) {
      return;
    }
    _emitState(current.copyWith(draftFolderName: null));
  }

  /// 提交新建：空名回落默认名，提交前按当前同级再次去重。
  Future<void> commitFolderCreation(String name) async {
    final current = _currentState;
    if (current == null || current.draftFolderName == null) {
      return;
    }
    final base = current.draftFolderName!;
    final trimmed = name.trim();
    final finalName = dedupeFolderName(
      trimmed.isEmpty ? base : trimmed,
      current.files,
    );
    _emitState(current.copyWith(draftFolderName: null));
    await createFolder(finalName);
  }
}
