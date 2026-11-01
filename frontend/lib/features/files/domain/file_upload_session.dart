class FileUploadPart {
  const FileUploadPart({
    required this.partNumber,
    required this.sizeBytes,
    required this.status,
    required this.uploadUrl,
    this.eTag,
    this.uploadUrlExpiresAt,
  });

  final int partNumber;
  final int sizeBytes;
  final String status;
  final String? eTag;
  final String? uploadUrl;
  final DateTime? uploadUrlExpiresAt;
}

class FileUploadPartsInfo {
  const FileUploadPartsInfo({
    required this.uploadId,
    required this.totalParts,
    required this.completedPartNumbers,
    required this.parts,
  });

  final String uploadId;
  final int totalParts;
  final List<int> completedPartNumbers;
  final List<FileUploadPart> parts;
}

typedef FileUploadProgressCallback = void Function(int sent, int total);

class FileUploadCancellationToken {
  final List<void Function()> _listeners = [];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// 移除监听：分片上传每次都会注册一个转发闭包，用完必须摘掉，
  /// 否则千片大文件会把上千个闭包与 CancelToken 一直挂在会话上。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}

class FileUploadSession {
  const FileUploadSession({
    required this.id,
    required this.uploadId,
    required this.parentId,
    required this.fileName,
    required this.sizeBytes,
    required this.partSizeBytes,
    required this.totalParts,
    required this.mimeType,
    required this.status,
    required this.uploadUrl,
    required this.parts,
    required this.expiresAt,
  });

  final String id;
  final String uploadId;
  final String? parentId;
  final String fileName;
  final int sizeBytes;
  final int partSizeBytes;
  final int totalParts;
  final String mimeType;
  final String status;
  final String? uploadUrl;
  final List<FileUploadPart> parts;
  final DateTime? expiresAt;

  bool get isDirectUpload => parts.isEmpty && (uploadUrl?.isNotEmpty ?? false);
}
