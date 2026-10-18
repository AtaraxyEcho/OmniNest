/// 公开分享访问仓储契约。
abstract interface class PublicShareRepository {
  Future<SharePreviewResult> preview(String token, {String? password});

  /// 逐级浏览被分享的文件夹；`parentId` 为空表示分享根目录。
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page,
    int size,
  });

  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  });
}

/// 分享文件夹的子项。
class ShareChild {
  const ShareChild({
    required this.id,
    required this.name,
    required this.nodeType,
    required this.sizeBytes,
    this.parentId,
    this.mimeType,
    this.downloadUrl,
  });

  factory ShareChild.fromJson(Map<String, dynamic> json) => ShareChild(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    nodeType: json['nodeType']?.toString() ?? 'FILE',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    parentId: json['parentId']?.toString(),
    mimeType: json['mimeType']?.toString(),
    downloadUrl: json['downloadUrl']?.toString(),
  );

  final String id;
  final String name;
  final String nodeType;
  final int sizeBytes;
  final String? parentId;
  final String? mimeType;
  final String? downloadUrl;

  bool get isFolder => nodeType == 'FOLDER';
}

/// 分享文件夹子项的分页结果。
sealed class ShareChildrenResult {
  const ShareChildrenResult();

  factory ShareChildrenResult.success({
    required List<ShareChild> items,
    required int total,
  }) = ShareChildrenSuccess;

  factory ShareChildrenResult.error(String message) = ShareChildrenFailure;
}

class ShareChildrenSuccess extends ShareChildrenResult {
  const ShareChildrenSuccess({required this.items, required this.total});

  final List<ShareChild> items;
  final int total;
}

class ShareChildrenFailure extends ShareChildrenResult {
  const ShareChildrenFailure(this.message);

  final String message;
}

/// 公开分享预览结果。
sealed class SharePreviewResult {
  const SharePreviewResult();

  factory SharePreviewResult.success({
    required String fileName,
    String? mimeType,
    required int sizeBytes,
    required String resourceType,
    required bool hasPassword,
  }) = SharePreviewSuccess;

  factory SharePreviewResult.needPassword(String message) =
      SharePreviewNeedPassword;

  factory SharePreviewResult.error(String message) = SharePreviewError;
}

class SharePreviewSuccess extends SharePreviewResult {
  const SharePreviewSuccess({
    required this.fileName,
    this.mimeType,
    required this.sizeBytes,
    required this.resourceType,
    required this.hasPassword,
  });

  final String fileName;
  final String? mimeType;
  final int sizeBytes;
  final String resourceType;
  final bool hasPassword;
}

class SharePreviewNeedPassword extends SharePreviewResult {
  const SharePreviewNeedPassword(this.message);

  final String message;
}

class SharePreviewError extends SharePreviewResult {
  const SharePreviewError(this.message);

  final String message;
}

/// 接受公开分享的结果。
sealed class ShareAcceptResult {
  const ShareAcceptResult();

  factory ShareAcceptResult.success() = ShareAcceptSuccess;

  factory ShareAcceptResult.duplicate(String message) = ShareAcceptDuplicate;

  factory ShareAcceptResult.error(String message) = ShareAcceptError;
}

class ShareAcceptSuccess extends ShareAcceptResult {
  const ShareAcceptSuccess();
}

class ShareAcceptDuplicate extends ShareAcceptResult {
  const ShareAcceptDuplicate(this.message);

  final String message;
}

class ShareAcceptError extends ShareAcceptResult {
  const ShareAcceptError(this.message);

  final String message;
}
