/// 空间类型枚举
enum SpaceType {
  personal('PERSONAL'),
  shared('SHARED');

  final String value;
  const SpaceType(this.value);

  static SpaceType fromValue(String value) {
    return SpaceType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SpaceType.personal,
    );
  }
}

class FileNode {
  const FileNode({
    required this.id,
    required this.parentId,
    required this.name,
    required this.isFolder,
    required this.nodeType,
    required this.normalizedPath,
    required this.sizeBytes,
    required this.updatedAt,
    this.mimeType,
    this.spaceType = SpaceType.personal,
    this.uploadedBy,
    this.uploaderName,
    this.coverFileId,
    this.mediaAutoImportTaskId,
  });

  final String id;
  final String? parentId;
  final String name;
  final bool isFolder;
  final String nodeType;
  final String normalizedPath;
  final String? mimeType;
  final int sizeBytes;
  final DateTime? updatedAt;
  final SpaceType spaceType;
  final String? uploadedBy;

  /// 上传者显示名（后端解析；个人空间即所有者，共享空间为实际上传者）。
  final String? uploaderName;

  /// 媒体封面文件节点 ID（音乐/影视/阅读库反查；无封面为空）。
  final String? coverFileId;
  final String? mediaAutoImportTaskId;
}

class FileNodePage {
  const FileNodePage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<FileNode> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  bool get hasNextPage => page + 1 < totalPages;
}
