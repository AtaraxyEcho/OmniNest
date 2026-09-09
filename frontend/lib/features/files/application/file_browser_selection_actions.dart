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
    await _runAction('新建文件夹', () async {
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
    await _runAction('重命名文件', () async {
      final current = _currentState;
      if (current?.spaceType == 'SHARED') {
        await _repository.renameSharedFile(fileId: file.id, name: name);
      } else {
        await _repository.renameFile(fileId: file.id, name: name);
      }
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> moveFile(FileNode file, String targetParentId) async {
    await _runAction('移动文件', () async {
      await _repository.moveFile(fileId: file.id, parentId: targetParentId);
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<String> downloadUrl(FileNode file) async {
    return _repository.downloadUrl(file.id);
  }

  Future<void> deleteFile(FileNode file) async {
    await _runAction('移入回收站', () async {
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
    await _runAction('恢复文件', () async {
      await _repository.restoreFile(file.id);
      await showRecycleBin();
    });
  }

  Future<void> purgeFile(FileNode file) async {
    await _runAction('彻底删除', () async {
      await _repository.purgeFile(file.id);
      await showRecycleBin();
    });
  }

  Future<void> addFavorite(FileNode file) async {
    await _runAction('添加收藏', () async {
      await _repository.addFavorite(file.id);
      await _refreshFavoritesData();
    });
  }

  Future<void> removeFavorite(FileNode file) async {
    await _runAction('取消收藏', () async {
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
    await _runAction('批量移入回收站', () async {
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
    await _runAction('批量恢复', () async {
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
    await _runAction('批量彻底删除', () async {
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
    await _runAction('批量移动', () async {
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
    await _runAction('批量添加收藏', () async {
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
    await _runAction('批量取消收藏', () async {
      await _repository.batchRemoveFavorites(ids.toList());
      _clearSelection();
      await _refreshFavoritesData();
    });
  }

  Future<FileShareLink> createShareLink(FileNode file) async {
    return _runAction('创建分享链接', () async {
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
    await _runAction('撤销分享', () async {
      await _repository.revokeShare(share.id);
      if (_currentState?.section == FileManagerSection.shareManagement) {
        await showShareLinks();
      } else {
        await showMyShares();
      }
    });
  }
}
