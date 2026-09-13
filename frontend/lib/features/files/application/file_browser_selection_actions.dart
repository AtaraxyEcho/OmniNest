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

  Future<void> createFolder(String name) async {
    await _runAction(FileOperation.createFolder, () async {
      final current = _currentState;
      if (current?.spaceType == 'SHARED') {
        await _repository.createSharedFolder(
          parentId: current?.parentId,
          name: name,
        );
      } else {
        await _repository.createFolder(parentId: current?.parentId, name: name);
      }
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> renameFile(FileNode file, String name) async {
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
    await _runAction(FileOperation.copy, () async {
      await _repository.copyFile(
        fileId: file.id,
        targetParentId: targetParentId,
      );
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> moveFile(FileNode file, String targetParentId) async {
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
    await _runAction(FileOperation.restore, () async {
      await _repository.restoreFile(file.id);
      await showRecycleBin();
    });
  }

  Future<void> purgeFile(FileNode file) async {
    await _runAction(FileOperation.purge, () async {
      await _repository.purgeFile(file.id);
      await showRecycleBin();
    });
  }

  Future<void> addFavorite(FileNode file) async {
    await _runAction(FileOperation.addFavorite, () async {
      await _repository.addFavorite(file.id);
      await _refreshFavoritesData();
    });
  }

  Future<void> removeFavorite(FileNode file) async {
    await _runAction(FileOperation.removeFavorite, () async {
      await _repository.removeFavorite(file.id);
      await _refreshFavoritesData();
    });
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
      await showRecycleBin();
    });
  }

  Future<void> batchMoveFiles(String targetParentId) async {
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
