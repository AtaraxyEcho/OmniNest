part of 'file_browser_controller.dart';

extension FileBrowserSelectionActions on FileBrowserController {
  Future<List<FileMediaImportTask>> requestMediaImports({
    required List<String> fileNodeIds,
    required String mediaType,
  }) {
    return _repository.requestMediaImports(
      fileNodeIds: fileNodeIds,
      mediaType: mediaType,
    );
  }

  // ── 乐观更新 ──────────────────────────────────────────────────────────
  //
  // 样例的收藏 / 删除 / 重命名都是「先动界面，再等网络」：`.f-row.sel .keep`
  // 之类的手感来自本地立即生效。这里同样先改内存态，失败时用一次
  // `refreshFileNodesForCurrentSection()` 把服务端真值拉回来当回滚，
  // 比反推每个字段更可靠（节点可能已被其它端改过）。
  //
  // 写入都发生在 `await` 之前，不涉及 `_liveOr` 的回写口径。

  /// 批量翻转收藏标记，并把命中的节点并进/移出 `favoriteFiles`。
  ///
  /// 单个文件的翻转口径已在 [_flagFavorite] 定好，这里只是把同一动作跑一遍
  /// 再一次性发射状态，避免批量收藏时发 N 次状态、列表抖 N 下。
  void _flipFavoritesLocally(List<String> ids, {required bool favorited}) {
    final current = _currentState;
    if (current == null || ids.isEmpty) {
      return;
    }
    final idSet = ids.toSet();
    var files = current.files;
    var recentFiles = current.recentFiles;
    var recycleBin = current.recycleBin;
    for (final id in ids) {
      files = _flagFavorite(files, id, favorited);
      recentFiles = _flagFavorite(recentFiles, id, favorited);
      recycleBin = _flagFavorite(recycleBin, id, favorited);
    }
    final favorites =
        favorited
            ? _mergeFavorites(current, idSet)
            : current.favoriteFiles
                .where((node) => !idSet.contains(node.id))
                .toList(growable: false);
    _emitState(
      current.copyWith(
        files: files,
        recentFiles: recentFiles,
        recycleBin: recycleBin,
        favoriteFiles: favorites,
      ),
    );
  }

  /// 收藏列表的新增侧：从当前分区里取节点补进去，已存在的 id 不重复。
  List<FileNode> _mergeFavorites(FileBrowserState current, Set<String> idSet) {
    final seen = current.favoriteFiles.map((node) => node.id).toSet();
    final merged = [...current.favoriteFiles];
    for (final pool in [current.files, current.recentFiles]) {
      for (final node in pool) {
        if (idSet.contains(node.id) && seen.add(node.id)) {
          merged.add(node.copyWith(favorited: true));
        }
      }
    }
    return merged;
  }

  /// 移出回收站前的乐观剔除：当前分区、最近、收藏三处同步消失。
  void _removeNodesLocally(List<String> ids) {
    final current = _currentState;
    if (current == null || ids.isEmpty) {
      return;
    }
    final idSet = ids.toSet();
    List<FileNode> drop(List<FileNode> pool) => [
      for (final node in pool)
        if (!idSet.contains(node.id)) node,
    ];
    _emitState(
      current.copyWith(
        files: drop(current.files),
        recentFiles: drop(current.recentFiles),
        favoriteFiles: drop(current.favoriteFiles),
        selectedFileIds: const <String>{},
      ),
    );
  }

  /// 重命名的乐观改写：只换名字，其它字段原样带走。
  void _renameNodeLocally(String fileId, String name) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    List<FileNode> rename(List<FileNode> pool) => [
      for (final node in pool)
        if (node.id == fileId) node.copyWith(name: name) else node,
    ];
    _emitState(
      current.copyWith(
        files: rename(current.files),
        recentFiles: rename(current.recentFiles),
        favoriteFiles: rename(current.favoriteFiles),
      ),
    );
  }

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

  /// 分页拉取目录选择器节点；调用方自行过滤文件夹并续页。
  Future<FileNodePage> listFolderOptionsPage(
    String? parentId, {
    int page = 0,
    int size = 100,
  }) {
    return _repository.listFilesPage(
      parentId: parentId,
      page: page,
      size: size,
    );
  }

  /// 拉取外部存储可用连接器列表（展示层不直连仓储）。
  Future<List<ExternalStorageConnector>> listExternalConnectors() {
    return _repository.listExternalConnectors();
  }

  /// 在指定父目录下建夹，供文件夹选择器跨层级使用。
  Future<FileNode> createFolderInParent(String? parentId, String name) async {
    final created = await _repository.createFolder(
      parentId: parentId,
      name: name,
    );
    registerFileEcho([created.id]);
    _insertCreatedFolderLocally(created);
    await refreshFileNodesForCurrentSection();
    return created;
  }

  /// 把服务端返回的新目录先合并到当前列表，让主列表和左侧树在同一帧
  /// 看到相同的真实节点。随后仍会刷新当前页，避免只依赖树层缓存失效。
  void _insertCreatedFolderLocally(FileNode created) {
    final current = _currentState;
    if (current == null ||
        current.section != FileManagerSection.allFiles ||
        current.spaceType != created.spaceType.value ||
        current.parentId != created.parentId ||
        current.files.any((node) => node.id == created.id)) {
      return;
    }
    _emitState(
      current.copyWith(
        files: [...current.files, created],
        fileTotalElements: current.fileTotalElements + 1,
      ),
    );
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
        _insertCreatedFolderLocally(created);
      } else {
        final created = await _repository.createFolder(
          parentId: current?.parentId,
          name: name,
        );
        registerFileEcho([created.id]);
        _insertCreatedFolderLocally(created);
      }
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> renameFile(FileNode file, String name) async {
    registerFileEcho([file.id]);
    await _runAction(FileOperation.rename, () async {
      // 先改名再等网络：列表立刻显示新名字。
      _renameNodeLocally(file.id, name);
      final current = _currentState;
      try {
        if (current?.spaceType == 'SHARED') {
          await _repository.renameSharedFile(fileId: file.id, name: name);
        } else {
          await _repository.renameFile(fileId: file.id, name: name);
        }
      } on Object {
        // 回滚：重新取当前分区，把失败的名字换回服务端值。
        await refreshFileNodesForCurrentSection();
        rethrow;
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
        _applyLocalFavoriteChange(file.id, added: false);
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
        _applyLocalFavoriteChange(file.id, added: true);
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
    _emitState(
      current.copyWith(
        favoriteFiles: favorites,
        files: _flagFavorite(current.files, fileId, added),
        recentFiles: _flagFavorite(current.recentFiles, fileId, added),
        recycleBin: _flagFavorite(current.recycleBin, fileId, added),
      ),
    );
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
    final idList = ids.toList();
    await _runAction(FileOperation.batchMoveToRecycleBin, () async {
      // 行先消失、选中栏先收起，再等回收站接口。
      _removeNodesLocally(idList);
      try {
        await _repository.batchDeleteFiles(idList);
      } on Object {
        // 失败回滚：重新拉当前分区，被移掉的行会回来。
        await refreshFileNodesForCurrentSection();
        rethrow;
      }
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

  /// Undo 通道：按删除前的 id 快照还原，并留在当前视图。
  /// [restoreFile] 与 [batchRestoreFiles] 都会切到回收站，撤销列表里的
  /// 删除不能复用它们，否则用户点一次 Undo 就被带离原分区。
  Future<void> undoDelete(List<String> fileIds) async {
    if (fileIds.isEmpty) {
      return;
    }
    registerFileEcho(fileIds);
    await _runAction(FileOperation.batchRestore, () async {
      await _repository.batchRestoreFiles(fileIds);
      await refreshFileNodesForCurrentSection();
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

  /// 拖拽落点移动：显式给 id 集（被拖的行未必是当前选中集）。
  ///
  /// 目标就是当前目录时直接返回——否则行会先乐观消失，再被刷新补回来。
  /// 空串表示根目录（仓储层同样把空 parentId 折成 null）。
  Future<void> moveFilesTo(List<String> ids, String targetParentId) async {
    final current = _currentState;
    final target = targetParentId.isEmpty ? null : targetParentId;
    if (ids.isEmpty ||
        (target != null && ids.contains(target)) ||
        current?.parentId == target) {
      return;
    }
    registerFileEcho(ids);
    await _runAction(FileOperation.batchMove, () async {
      _removeNodesLocally(ids);
      try {
        await _repository.batchMoveFiles(ids, targetParentId);
      } on Object {
        await refreshFileNodesForCurrentSection();
        rethrow;
      }
      _clearSelection();
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> batchAddFavorites() async {
    final ids = _currentState?.selectedFileIds.toList() ?? const <String>[];
    if (ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchAddFavorite, () async {
      _flipFavoritesLocally(ids, favorited: true);
      _clearSelection();
      try {
        await _repository.batchAddFavorites(ids);
      } on Object {
        await _refreshFavoritesData();
        await refreshFileNodesForCurrentSection();
        rethrow;
      }
      await _refreshFavoritesData();
    });
  }

  Future<void> batchRemoveFavorites() async {
    final ids = _currentState?.selectedFileIds.toList() ?? const <String>[];
    if (ids.isEmpty) {
      return;
    }
    await _runAction(FileOperation.batchRemoveFavorite, () async {
      _flipFavoritesLocally(ids, favorited: false);
      _clearSelection();
      try {
        await _repository.batchRemoveFavorites(ids);
      } on Object {
        await _refreshFavoritesData();
        await refreshFileNodesForCurrentSection();
        rethrow;
      }
      await _refreshFavoritesData();
    });
  }

  Future<FileShareLink> createShareLink(
    FileNode file, {
    String? password,
    bool generatePassword = false,
    DateTime? expiresAt,
    int? maxAccessCount,
    bool allowDownloads = true,
    bool originalQuality = true,
    bool includeLocation = true,
    List<String> recipientUserIds = const <String>[],
  }) async {
    return _runAction(FileOperation.createShareLink, () async {
      final share = await _repository.createShareLink(
        resourceId: file.id,
        resourceType: file.isFolder ? 'FOLDER' : 'FILE',
        password: password,
        generatePassword: generatePassword,
        expiresAt: expiresAt,
        maxAccessCount: maxAccessCount,
        allowDownloads: allowDownloads,
        originalQuality: originalQuality,
        includeLocation: includeLocation,
        recipientUserIds: recipientUserIds,
      );
      final current = _currentState;
      if (current != null) {
        final myShares = await _repository.listMyShares();
        _emitState(_liveOr(current).copyWith(myShares: myShares));
      }
      return share;
    });
  }

  Future<List<FileShareRecipient>> searchShareRecipients(String query) =>
      _repository.searchShareRecipients(query);

  Future<List<FileShareLink>> listShareLinksForResource(FileNode file) async =>
      (await _repository.listMyShares())
          .where(
            (link) => link.resourceId == file.id && link.status == 'ACTIVE',
          )
          .toList(growable: false);

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

  /// 登记一次本地文件变更（供实时回声抑制查询）。
  void registerFileEcho(Iterable<String> fileIds) {
    final expiry = DateTime.now().add(FileBrowserController._fileEchoWindow);
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
}

/// 把已加载节点里的收藏标记翻到目标值，供星标乐观更新与失败回滚共用。
List<FileNode> _flagFavorite(
  List<FileNode> nodes,
  String fileId,
  bool favorited,
) {
  return [
    for (final node in nodes)
      node.id == fileId ? node.copyWith(favorited: favorited) : node,
  ];
}
