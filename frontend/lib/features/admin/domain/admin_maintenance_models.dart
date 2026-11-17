part of 'admin_operations.dart';

/// 全站分享链接审计行。
class AdminFileShareLink {
  const AdminFileShareLink({
    required this.id,
    required this.ownerUserId,
    required this.ownerUsername,
    required this.resourceType,
    required this.resourceId,
    required this.resourceName,
    required this.status,
    required this.accessCount,
    this.maxAccessCount,
    this.expiresAt,
    this.disabledAt,
    this.createdAt,
  });

  factory AdminFileShareLink.fromJson(Map<String, dynamic> json) {
    return AdminFileShareLink(
      id: json['id']?.toString() ?? '',
      ownerUserId: json['ownerUserId']?.toString() ?? '',
      ownerUsername: json['ownerUsername']?.toString() ?? '',
      resourceType: json['resourceType']?.toString() ?? '',
      resourceId: json['resourceId']?.toString() ?? '',
      resourceName: json['resourceName']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
      maxAccessCount: (json['maxAccessCount'] as num?)?.toInt(),
      expiresAt: _adminDate(json['expiresAt']),
      disabledAt: _adminDate(json['disabledAt']),
      createdAt: _adminDate(json['createdAt']),
    );
  }

  final String id;
  final String ownerUserId;
  final String ownerUsername;
  final String resourceType;
  final String resourceId;
  final String resourceName;
  final String status;
  final int accessCount;
  final int? maxAccessCount;
  final DateTime? expiresAt;
  final DateTime? disabledAt;
  final DateTime? createdAt;
}

/// 本地媒体库中已不可用的条目。
class AdminUnavailableMedia {
  const AdminUnavailableMedia({
    required this.videoItemId,
    required this.fileNodeId,
    required this.librarySourceId,
    required this.title,
    required this.availabilityStatus,
    required this.missingConfirmations,
    this.missingSince,
  });

  factory AdminUnavailableMedia.fromJson(Map<String, dynamic> json) {
    return AdminUnavailableMedia(
      videoItemId: json['videoItemId']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      librarySourceId: json['librarySourceId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      availabilityStatus: json['availabilityStatus']?.toString() ?? '',
      missingConfirmations:
          (json['missingConfirmations'] as num?)?.toInt() ?? 0,
      missingSince: _adminDate(json['missingSince']),
    );
  }

  final String videoItemId;
  final String fileNodeId;
  final String librarySourceId;
  final String title;
  final String availabilityStatus;
  final int missingConfirmations;
  final DateTime? missingSince;
}

/// GeoNames 数据集导入任务创建结果。
class AdminGeoImportResult {
  const AdminGeoImportResult({
    required this.taskId,
    required this.datasetId,
    required this.datasetVersion,
  });

  factory AdminGeoImportResult.fromJson(Map<String, dynamic> json) {
    return AdminGeoImportResult(
      taskId: json['taskId']?.toString() ?? '',
      datasetId: json['datasetId']?.toString() ?? '',
      datasetVersion: json['datasetVersion']?.toString() ?? '',
    );
  }

  final String taskId;
  final String datasetId;
  final String datasetVersion;
}

/// 存量照片位置回填任务创建结果。
class AdminGeoBackfillResult {
  const AdminGeoBackfillResult({required this.taskId, required this.reused});

  factory AdminGeoBackfillResult.fromJson(Map<String, dynamic> json) {
    return AdminGeoBackfillResult(
      taskId: json['taskId']?.toString() ?? '',
      reused: json['reused'] == true,
    );
  }

  final String taskId;

  /// 已有活跃回填任务时复用原任务。
  final bool reused;
}

/// 共享空间角色能力矩阵行。
class AdminSharedSpacePermission {
  const AdminSharedSpacePermission({
    required this.roleId,
    required this.roleCode,
    required this.canBrowse,
    required this.canUpload,
    required this.canDownload,
    required this.canDeleteOwn,
    required this.canDeleteAny,
    required this.canMoveTo,
    required this.canMoveFrom,
    required this.canCreateFolder,
  });

  factory AdminSharedSpacePermission.fromJson(Map<String, dynamic> json) {
    bool flag(String key) => json[key] == true;
    return AdminSharedSpacePermission(
      roleId: json['roleId']?.toString() ?? '',
      roleCode: json['roleCode']?.toString() ?? '',
      canBrowse: flag('canBrowse'),
      canUpload: flag('canUpload'),
      canDownload: flag('canDownload'),
      canDeleteOwn: flag('canDeleteOwn'),
      canDeleteAny: flag('canDeleteAny'),
      canMoveTo: flag('canMoveTo'),
      canMoveFrom: flag('canMoveFrom'),
      canCreateFolder: flag('canCreateFolder'),
    );
  }

  final String roleId;
  final String roleCode;
  final bool canBrowse;
  final bool canUpload;
  final bool canDownload;
  final bool canDeleteOwn;
  final bool canDeleteAny;
  final bool canMoveTo;
  final bool canMoveFrom;
  final bool canCreateFolder;

  AdminSharedSpacePermission copyWith({
    bool? canBrowse,
    bool? canUpload,
    bool? canDownload,
    bool? canDeleteOwn,
    bool? canDeleteAny,
    bool? canMoveTo,
    bool? canMoveFrom,
    bool? canCreateFolder,
  }) {
    return AdminSharedSpacePermission(
      roleId: roleId,
      roleCode: roleCode,
      canBrowse: canBrowse ?? this.canBrowse,
      canUpload: canUpload ?? this.canUpload,
      canDownload: canDownload ?? this.canDownload,
      canDeleteOwn: canDeleteOwn ?? this.canDeleteOwn,
      canDeleteAny: canDeleteAny ?? this.canDeleteAny,
      canMoveTo: canMoveTo ?? this.canMoveTo,
      canMoveFrom: canMoveFrom ?? this.canMoveFrom,
      canCreateFolder: canCreateFolder ?? this.canCreateFolder,
    );
  }

  Set<String> get enabledCapabilities => {
    if (canBrowse) 'browse',
    if (canUpload) 'upload',
    if (canDownload) 'download',
    if (canDeleteOwn) 'deleteOwn',
    if (canDeleteAny) 'deleteAny',
    if (canMoveTo) 'moveTo',
    if (canMoveFrom) 'moveFrom',
    if (canCreateFolder) 'createFolder',
  };

  bool sameCapabilities(AdminSharedSpacePermission other) {
    return roleId == other.roleId &&
        enabledCapabilities.length == other.enabledCapabilities.length &&
        enabledCapabilities.containsAll(other.enabledCapabilities);
  }
}

DateTime? _adminDate(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text)?.toLocal();
}
