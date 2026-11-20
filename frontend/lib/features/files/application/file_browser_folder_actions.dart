part of 'file_browser_controller.dart';

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
