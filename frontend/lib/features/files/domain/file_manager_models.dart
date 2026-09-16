import 'package:omninest/features/files/domain/file_node.dart';

class FileTypeStats {
  const FileTypeStats({
    required this.category,
    required this.count,
    required this.sizeBytes,
  });

  final String category;
  final int count;
  final int sizeBytes;
}

class FileStorageStats {
  const FileStorageStats({
    required this.totalFiles,
    required this.totalFolders,
    required this.usedBytes,
    required this.quotaBytes,
    required this.quotaStatus,
    required this.typeDistribution,
  });

  final int totalFiles;
  final int totalFolders;
  final int usedBytes;
  final int quotaBytes;
  final String quotaStatus;
  final List<FileTypeStats> typeDistribution;

  bool get isQuotaUnlimited => quotaBytes < 0;

  double get usageRatio {
    if (isQuotaUnlimited) {
      return 0;
    }
    if (quotaBytes <= 0) {
      return 0;
    }
    return (usedBytes / quotaBytes).clamp(0, 1);
  }
}

class FileUploadPolicy {
  const FileUploadPolicy({
    required this.directUploadMaxBytes,
    required this.defaultPartSizeBytes,
    required this.maxPartSizeBytes,
    required this.maxTotalParts,
    required this.maxConcurrentParts,
  });

  final int directUploadMaxBytes;
  final int defaultPartSizeBytes;
  final int maxPartSizeBytes;
  final int maxTotalParts;
  final int maxConcurrentParts;
}

abstract final class FileUploadTaskMessageCode {
  static const waiting = 'waiting';
  static const directUploading = 'directUploading';
  static const multipartUploading = 'multipartUploading';
  static const pausePending = 'pausePending';
  static const paused = 'paused';
  static const resuming = 'resuming';
  static const completed = 'completed';
  static const scanPending = 'scanPending';
  static const conflict = 'conflict';
  static const partCompleted = 'partCompleted';
  static const retrying = 'retrying';
  static const failed = 'failed';
}

class FileUploadClientTask {
  const FileUploadClientTask({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.uploadedBytes,
    required this.status,
    this.message,
    this.messageCode,
    this.messageArgument,
    this.messageCurrent,
    this.messageTotal,
    this.uploadId,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final int uploadedBytes;
  final String status;
  final String? message;
  final String? messageCode;
  final String? messageArgument;
  final int? messageCurrent;
  final int? messageTotal;
  final String? uploadId;

  double get progress {
    if (sizeBytes <= 0) {
      return 0;
    }
    return (uploadedBytes / sizeBytes).clamp(0, 1);
  }

  FileUploadClientTask copyWith({
    int? uploadedBytes,
    String? status,
    String? message,
    String? messageCode,
    String? messageArgument,
    int? messageCurrent,
    int? messageTotal,
    String? uploadId,
  }) {
    return FileUploadClientTask(
      id: id,
      fileName: fileName,
      sizeBytes: sizeBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      status: status ?? this.status,
      message: message ?? this.message,
      messageCode: messageCode ?? this.messageCode,
      messageArgument: messageArgument ?? this.messageArgument,
      messageCurrent: messageCurrent ?? this.messageCurrent,
      messageTotal: messageTotal ?? this.messageTotal,
      uploadId: uploadId ?? this.uploadId,
    );
  }
}

class FileShareLink {
  const FileShareLink({
    required this.id,
    required this.resourceType,
    required this.resourceId,
    required this.resourceName,
    required this.shareCode,
    required this.status,
    required this.accessCount,
    required this.createdAt,
    this.maxAccessCount,
    this.expiresAt,
    this.disabledAt,
    this.generatedPassword,
  });

  final String id;
  final String resourceType;
  final String resourceId;
  final String resourceName;
  final String shareCode;
  final String status;
  final int? maxAccessCount;
  final int accessCount;
  final DateTime? expiresAt;
  final DateTime? disabledAt;
  final DateTime? createdAt;
  final String? generatedPassword;
}

class FileSharePreview {
  const FileSharePreview({
    required this.shareId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.resourceType,
    required this.hasPassword,
  });

  final String shareId;
  final String fileName;
  final String? mimeType;
  final int sizeBytes;
  final String resourceType;
  final bool hasPassword;
}

class SharedFileItem {
  const SharedFileItem({
    required this.shareId,
    required this.file,
    required this.ownerUserId,
    required this.sharedAt,
    this.expiresAt,
  });

  final String shareId;
  final FileNode file;
  final String ownerUserId;
  final DateTime? sharedAt;
  final DateTime? expiresAt;
}

class FileUploadQueueItem {
  const FileUploadQueueItem({
    required this.id,
    required this.uploadId,
    required this.fileName,
    required this.sizeBytes,
    required this.partSizeBytes,
    required this.totalParts,
    required this.uploadedParts,
    required this.status,
    this.parentId,
    this.expiresAt,
    this.updatedAt,
  });

  final String id;
  final String uploadId;
  final String? parentId;
  final String fileName;
  final int sizeBytes;
  final int partSizeBytes;
  final int totalParts;
  final int uploadedParts;
  final String status;
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  double get progress {
    if (totalParts <= 0) {
      return 0;
    }
    return (uploadedParts / totalParts).clamp(0, 1);
  }
}

class OfflineDownloadTask {
  const OfflineDownloadTask({
    required this.id,
    required this.sourceUri,
    required this.status,
    this.aria2Gid,
    this.fileName,
    this.totalBytes = 0,
    this.completedBytes = 0,
    this.downloadSpeedBytes = 0,
    this.errorSummary,
    this.completedFileId,
    this.completedAt,
    this.targetParentId,
    this.taskId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String sourceUri;
  final String? targetParentId;
  final String? taskId;
  final String status;
  final String? aria2Gid;
  final String? fileName;
  final int totalBytes;
  final int completedBytes;
  final int downloadSpeedBytes;
  final String? errorSummary;
  final String? completedFileId;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return (completedBytes / totalBytes).clamp(0, 1);
  }

  bool get canCancel {
    return !{
      'CANCELLED',
      'COMPLETED',
      'FAILED',
      'CANCELLING',
    }.contains(status.toUpperCase());
  }

  OfflineDownloadTask copyWith({String? status, DateTime? updatedAt}) {
    return OfflineDownloadTask(
      id: id,
      sourceUri: sourceUri,
      status: status ?? this.status,
      aria2Gid: aria2Gid,
      fileName: fileName,
      totalBytes: totalBytes,
      completedBytes: completedBytes,
      downloadSpeedBytes: downloadSpeedBytes,
      errorSummary: errorSummary,
      completedFileId: completedFileId,
      completedAt: completedAt,
      targetParentId: targetParentId,
      taskId: taskId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ExternalStorageAccount {
  const ExternalStorageAccount({
    required this.id,
    required this.provider,
    required this.displayName,
    this.connectionMetadata = const {},
    this.credentialsConfigured = false,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String provider;
  final String displayName;
  final Map<String, String> connectionMetadata;
  final bool credentialsConfigured;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class ExternalFileItem {
  const ExternalFileItem({
    required this.name,
    required this.path,
    required this.isDir,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.mimeType,
    this.hash,
  });

  final String name;
  final String path;
  final bool isDir;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final String? mimeType;
  final String? hash;
}

class ExternalSpaceUsage {
  const ExternalSpaceUsage({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.trashedBytes,
  });

  factory ExternalSpaceUsage.fromJson(Map<String, dynamic> json) {
    return ExternalSpaceUsage(
      totalBytes: _asInt(json['totalBytes']),
      usedBytes: _asInt(json['usedBytes']),
      freeBytes: _asInt(json['freeBytes']),
      trashedBytes: _asInt(json['trashedBytes']),
    );
  }

  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int trashedBytes;

  /// 已用空间百分比（0~1）
  double get usagePercent => totalBytes > 0 ? usedBytes / totalBytes : 0;
}

class ImportTask {
  const ImportTask({
    required this.id,
    this.taskId,
    required this.externalAccountId,
    required this.sourcePath,
    this.sourceKind = 'FILE',
    required this.status,
    this.fileName,
    this.totalBytes = 0,
    this.transferredBytes = 0,
    this.speedBytes = 0,
    this.totalFiles = 0,
    this.completedFiles = 0,
    this.currentFileName,
    this.errorSummary,
    this.completedFileId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? taskId;
  final String externalAccountId;
  final String sourcePath;
  final String sourceKind;
  final String? fileName;
  final int totalBytes;
  final int transferredBytes;
  final int speedBytes;
  final int totalFiles;
  final int completedFiles;
  final String? currentFileName;
  final String status;
  final String? errorSummary;
  final String? completedFileId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get progress =>
      totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  bool get canCancel =>
      !{'CANCELLED', 'COMPLETED', 'FAILED'}.contains(status.toUpperCase());

  bool get isDirectory => sourceKind.toUpperCase() == 'DIRECTORY';

  bool get isActive => canCancel;

  ImportTask copyWith({
    String? status,
    int? transferredBytes,
    int? speedBytes,
  }) {
    return ImportTask(
      id: id,
      taskId: taskId,
      externalAccountId: externalAccountId,
      sourcePath: sourcePath,
      sourceKind: sourceKind,
      status: status ?? this.status,
      fileName: fileName,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      speedBytes: speedBytes ?? this.speedBytes,
      totalFiles: totalFiles,
      completedFiles: completedFiles,
      currentFileName: currentFileName,
      errorSummary: errorSummary,
      completedFileId: completedFileId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// 共享空间使用情况
class SharedSpaceUsage {
  const SharedSpaceUsage({
    required this.usedBytes,
    required this.maxBytes,
    required this.fileCount,
  });

  final int usedBytes;
  final int maxBytes;
  final int fileCount;

  bool get isUnlimited => maxBytes < 0;

  double get usageRatio {
    if (isUnlimited) return 0;
    if (maxBytes <= 0) return 0;
    return (usedBytes / maxBytes).clamp(0, 1);
  }
}

/// 文件历史版本条目。
class FileVersion {
  const FileVersion({
    required this.id,
    required this.versionNo,
    required this.objectId,
    required this.changeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.isCurrent,
    this.createdBy,
    this.remark,
  });

  factory FileVersion.fromJson(Map<String, dynamic> json) {
    return FileVersion(
      id: json['id']?.toString() ?? '',
      versionNo:
          json['versionNo'] is num ? (json['versionNo'] as num).toInt() : 0,
      objectId: json['objectId']?.toString() ?? '',
      changeType: json['changeType']?.toString() ?? '',
      sizeBytes:
          json['sizeBytes'] is num ? (json['sizeBytes'] as num).toInt() : 0,
      createdBy: json['createdBy']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      isCurrent: json['isCurrent'] == true,
      remark: json['remark']?.toString(),
    );
  }

  final String id;
  final int versionNo;
  final String objectId;
  final String changeType;
  final int sizeBytes;
  final String? createdBy;
  final DateTime? createdAt;
  final bool isCurrent;
  final String? remark;
}

int _asInt(Object? value) {
  return switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text) ?? 0,
    _ => 0,
  };
}
