import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/features/files/data/dtos/file_node_dto.dart';
import 'package:omninest/features/files/data/dtos/file_upload_session_dto.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';

/// 负责将文件模块 API 响应转换为领域对象。
class FileApiResponseParser {
  const FileApiResponseParser();

  FileNodePage parseFilePageResponse(Map<String, dynamic>? body) {
    final data = parseData(body);
    final items = data['items'];
    if (items is! List) {
      throw const AppException(
        code: AppErrorCodes.invalidResponse,
        message: AppErrorCodes.invalidResponse,
      );
    }
    return FileNodePage(
      items:
          items
              .whereType<Map<String, dynamic>>()
              .map(FileNodeDto.fromJson)
              .map((dto) => dto.toDomain())
              .toList(),
      page: asInt(data['page']),
      size: asInt(data['size']),
      totalElements: asInt(data['totalElements']),
      totalPages: asInt(data['totalPages']),
    );
  }

  FileNode parseFileNodeResponse(Map<String, dynamic>? body) {
    return FileNodeDto.fromJson(parseData(body)).toDomain();
  }

  List<FileNode> parseBatchFileNodeResponse(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(FileNodeDto.fromJson)
        .map((dto) => dto.toDomain())
        .toList();
  }

  FileUploadSession parseUploadSessionResponse(Map<String, dynamic>? body) {
    return FileUploadSessionDto.fromJson(parseData(body)).toDomain();
  }

  FileUploadPartsInfo parseUploadPartsResponse(Map<String, dynamic>? body) {
    final data = parseData(body);
    final rawParts = data['parts'];
    final rawCompleted = data['completedPartNumbers'];
    return FileUploadPartsInfo(
      uploadId: data['uploadId']?.toString() ?? '',
      totalParts: asInt(data['totalParts']),
      completedPartNumbers:
          rawCompleted is List
              ? rawCompleted.whereType<int>().toList()
              : const [],
      parts:
          rawParts is List
              ? rawParts
                  .whereType<Map<String, dynamic>>()
                  .map(FileUploadPartDto.fromJson)
                  .map((dto) => dto.toDomain())
                  .toList()
              : const [],
    );
  }

  FileStorageStats parseStorageStatsResponse(Map<String, dynamic>? body) {
    return _parseStorageStats(parseData(body));
  }

  FileUploadPolicy parseUploadPolicyResponse(Map<String, dynamic>? body) {
    final data = parseData(body);
    return FileUploadPolicy(
      directUploadMaxBytes: asInt(data['directUploadMaxBytes']),
      defaultPartSizeBytes: asInt(data['defaultPartSizeBytes']),
      maxPartSizeBytes: asInt(data['maxPartSizeBytes']),
      maxTotalParts: asInt(data['maxTotalParts']),
      maxConcurrentParts: asInt(data['maxConcurrentParts']),
    );
  }

  List<FileShareLink> parseShareLinkPageResponse(Map<String, dynamic>? body) {
    return parsePageItems(body).map(_parseShareLink).toList();
  }

  FileShareLink parseShareLinkResponse(Map<String, dynamic>? body) {
    return _parseShareLink(parseData(body));
  }

  List<SharedFileItem> parseSharedItemPageResponse(Map<String, dynamic>? body) {
    return parsePageItems(body).map(_parseSharedItem).toList();
  }

  List<FileUploadQueueItem> parseUploadQueuePageResponse(
    Map<String, dynamic>? body,
  ) {
    return parsePageItems(body).map(_parseUploadQueueItem).toList();
  }

  List<OfflineDownloadTask> parseOfflineTaskPageResponse(
    Map<String, dynamic>? body,
  ) {
    return parsePageItems(body).map(_parseOfflineTask).toList();
  }

  OfflineDownloadTask parseOfflineTaskResponse(Map<String, dynamic>? body) {
    return _parseOfflineTask(parseData(body));
  }

  List<ExternalStorageAccount> parseExternalStoragePageResponse(
    Map<String, dynamic>? body,
  ) {
    return parsePageItems(body).map(_parseExternalStorage).toList();
  }

  ExternalStorageAccount parseExternalStorageResponse(
    Map<String, dynamic>? body,
  ) {
    return _parseExternalStorage(parseData(body));
  }

  void parseEmptyResponse(Map<String, dynamic>? body) {
    parseEnvelope(body);
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(
        code: AppErrorCodes.invalidResponse,
        message: AppErrorCodes.invalidResponse,
      );
    }
    return data;
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(
        code: AppErrorCodes.emptyResponse,
        message: AppErrorCodes.emptyResponse,
      );
    }
    final code = body['code'];
    if (code != 200) {
      throw AppException(
        code: code?.toString() ?? 'FILE_ERROR',
        message: body['message']?.toString() ?? AppErrorCodes.operationFailed,
        details: _parseErrorDetails(body['details']),
      );
    }
    return body;
  }

  Map<String, Object?> _parseErrorDetails(Object? rawDetails) {
    if (rawDetails is! Map) {
      return const <String, Object?>{};
    }
    return rawDetails.map((key, value) => MapEntry(key.toString(), value));
  }

  List<Map<String, dynamic>> parsePageItems(Map<String, dynamic>? body) {
    final data = parseData(body);
    final items = data['items'];
    if (items is! List) {
      throw const AppException(
        code: AppErrorCodes.invalidResponse,
        message: AppErrorCodes.invalidResponse,
      );
    }
    return items.whereType<Map<String, dynamic>>().toList();
  }

  ExternalFileItem parseExternalFileItem(Map<String, dynamic> json) {
    return ExternalFileItem(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      isDir: json['isDir'] == true,
      sizeBytes: asInt(json['sizeBytes']),
      modifiedAt:
          DateTime.tryParse(json['modifiedAt']?.toString() ?? '')?.toLocal(),
      mimeType: json['mimeType']?.toString(),
      hash: json['hash']?.toString(),
    );
  }

  ImportTask parseImportTask(Map<String, dynamic> json) {
    return ImportTask(
      id: json['id'].toString(),
      taskId: json['taskId']?.toString(),
      externalAccountId: json['externalAccountId']?.toString() ?? '',
      sourcePath: json['sourcePath']?.toString() ?? '',
      sourceKind: json['sourceKind']?.toString() ?? 'FILE',
      fileName: json['fileName']?.toString(),
      totalBytes: asInt(json['totalBytes']),
      transferredBytes: asInt(json['transferredBytes']),
      speedBytes: asInt(json['speedBytes']),
      totalFiles: asInt(json['totalFiles']),
      completedFiles: asInt(json['completedFiles']),
      currentFileName: json['currentFileName']?.toString(),
      status: json['status']?.toString() ?? 'QUEUED',
      errorSummary: json['errorSummary']?.toString(),
      completedFileId: json['completedFileId']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }

  int asInt(Object? value) {
    return switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
  }

  FileStorageStats _parseStorageStats(Map<String, dynamic> json) {
    final rawTypes = json['typeDistribution'];
    return FileStorageStats(
      totalFiles: asInt(json['totalFiles']),
      totalFolders: asInt(json['totalFolders']),
      usedBytes: asInt(json['usedBytes']),
      quotaBytes: asInt(json['quotaBytes']),
      quotaStatus: json['quotaStatus']?.toString() ?? 'NORMAL',
      typeDistribution:
          rawTypes is List
              ? rawTypes
                  .whereType<Map<String, dynamic>>()
                  .map(
                    (item) => FileTypeStats(
                      category:
                          item['category']?.toString() ?? AppErrorCodes.other,
                      count: asInt(item['count']),
                      sizeBytes: asInt(item['sizeBytes']),
                    ),
                  )
                  .toList()
              : const [],
    );
  }

  FileShareLink _parseShareLink(Map<String, dynamic> json) {
    return FileShareLink(
      id: json['id'].toString(),
      resourceType: json['resourceType']?.toString() ?? 'FILE',
      resourceId: json['resourceId']?.toString() ?? '',
      resourceName:
          json['resourceName']?.toString() ?? AppErrorCodes.unnamedResource,
      shareCode: json['shareCode']?.toString() ?? '',
      status: json['status']?.toString() ?? 'ACTIVE',
      maxAccessCount:
          json['maxAccessCount'] == null ? null : asInt(json['maxAccessCount']),
      accessCount: asInt(json['accessCount']),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
      disabledAt:
          DateTime.tryParse(json['disabledAt']?.toString() ?? '')?.toLocal(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      generatedPassword: json['generatedPassword']?.toString(),
    );
  }

  SharedFileItem _parseSharedItem(Map<String, dynamic> json) {
    final file = json['file'];
    if (file is! Map<String, dynamic>) {
      throw const AppException(
        code: AppErrorCodes.invalidResponse,
        message: AppErrorCodes.invalidResponse,
      );
    }
    return SharedFileItem(
      shareId: json['shareId'].toString(),
      file: FileNodeDto.fromJson(file).toDomain(),
      ownerUserId: json['ownerUserId']?.toString() ?? '',
      sharedAt:
          DateTime.tryParse(json['sharedAt']?.toString() ?? '')?.toLocal(),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
    );
  }

  FileUploadQueueItem _parseUploadQueueItem(Map<String, dynamic> json) {
    return FileUploadQueueItem(
      id: json['id'].toString(),
      uploadId: json['uploadId']?.toString() ?? '',
      parentId: json['parentId']?.toString(),
      fileName: json['fileName']?.toString() ?? '',
      sizeBytes: asInt(json['sizeBytes']),
      partSizeBytes: asInt(json['partSizeBytes']),
      totalParts: asInt(json['totalParts']),
      uploadedParts: asInt(json['uploadedParts']),
      status: json['status']?.toString() ?? 'CREATED',
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }

  OfflineDownloadTask _parseOfflineTask(Map<String, dynamic> json) {
    return OfflineDownloadTask(
      id: json['id'].toString(),
      sourceUri: json['sourceUri']?.toString() ?? '',
      targetParentId: json['targetParentId']?.toString(),
      taskId: json['taskId']?.toString(),
      status: json['status']?.toString() ?? 'QUEUED',
      aria2Gid: json['aria2Gid']?.toString(),
      fileName: json['fileName']?.toString(),
      totalBytes: asInt(json['totalBytes']),
      completedBytes: asInt(json['completedBytes']),
      downloadSpeedBytes: asInt(json['downloadSpeedBytes']),
      errorSummary: json['errorSummary']?.toString(),
      completedFileId: json['completedFileId']?.toString(),
      completedAt:
          DateTime.tryParse(json['completedAt']?.toString() ?? '')?.toLocal(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }

  ExternalStorageAccount _parseExternalStorage(Map<String, dynamic> json) {
    final rawMetadata = json['connectionMetadata'];
    final connectionMetadata =
        rawMetadata is Map
            ? rawMetadata.map(
              (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
            )
            : const <String, String>{};
    return ExternalStorageAccount(
      id: json['id'].toString(),
      provider: json['provider']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      connectionMetadata: connectionMetadata,
      credentialsConfigured: json['credentialsConfigured'] == true,
      status: json['status']?.toString() ?? 'ACTIVE',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }
}
