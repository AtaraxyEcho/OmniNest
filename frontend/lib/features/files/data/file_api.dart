import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/files/data/file_api_response_parser.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

class FileApi {
  FileApi(this.apiClient, {Dio? uploadDio}) : _uploadDio = uploadDio ?? Dio();

  static const String _binaryContentType = 'application/octet-stream';
  static const int _textPreviewMaxBytes = 1024 * 1024;
  static const Duration _externalStorageTimeout = Duration(seconds: 15);
  static const FileApiResponseParser _responseParser = FileApiResponseParser();

  final ApiClient apiClient;
  final Dio _uploadDio;
  final Map<String, String> _shareSessionTokens = <String, String>{};

  void close() => _uploadDio.close(force: true);

  Future<List<FileNode>> listFiles({String? parentId, String? category}) async {
    final page = await listFilesPage(parentId: parentId, category: category);
    return page.items;
  }

  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 100,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files',
      queryParameters: {
        if (parentId != null) 'parentId': parentId,
        if (category != null && category.isNotEmpty && category != 'all')
          'category': category,
        'page': page,
        'size': size,
      },
    );
    return parseFilePageResponse(response.data);
  }

  Future<List<FileNode>> listRecycleBin({String spaceType = 'PERSONAL'}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/recycle-bin',
      queryParameters: {'spaceType': spaceType},
    );
    return parseFilePageResponse(response.data).items;
  }

  Future<List<FileNode>> listRecentFiles() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/recent',
    );
    return parseFilePageResponse(response.data).items;
  }

  Future<List<FileNode>> listFavoriteFiles() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/favorites',
    );
    return parseFilePageResponse(response.data).items;
  }

  Future<FileNode> createFolder({
    String? parentId,
    required String name,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/folders',
      data: {'parentId': parentId, 'name': name},
    );
    return parseFileNodeResponse(response.data);
  }

  Future<FileNode> renameFile({
    required String fileId,
    required String name,
  }) async {
    final response = await apiClient.dio.patch<Map<String, dynamic>>(
      '/files/$fileId/rename',
      data: {'name': name},
    );
    return parseFileNodeResponse(response.data);
  }

  Future<FileNode> moveFile({
    required String fileId,
    required String parentId,
  }) async {
    final response = await apiClient.dio.patch<Map<String, dynamic>>(
      '/files/$fileId/move',
      data: {'parentId': parentId.isEmpty ? null : parentId},
    );
    return parseFileNodeResponse(response.data);
  }

  /// 复制文件节点到目标目录（null 表示根目录）。
  Future<FileNode> copyFile({
    required String fileId,
    String? targetParentId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/copy',
      data: {'targetParentId': targetParentId},
    );
    return parseFileNodeResponse(response.data);
  }

  /// 查询文件版本历史。
  Future<List<FileVersion>> listFileVersions(String fileId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/$fileId/versions',
    );
    final envelope = _responseParser.parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(FileVersion.fromJson)
        .toList();
  }

  /// 将当前内容保存为历史版本，并切换到已上传对象。
  Future<FileNode> saveFileVersion({
    required String fileId,
    required String objectId,
    required int sizeBytes,
    String? remark,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/versions',
      data: {
        'objectId': objectId,
        'sizeBytes': sizeBytes,
        if (remark != null && remark.isNotEmpty) 'remark': remark,
      },
    );
    return parseFileNodeResponse(response.data);
  }

  /// 恢复指定历史版本为当前内容。
  Future<FileNode> restoreFileVersion({
    required String fileId,
    required String versionId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/versions/$versionId/restore',
    );
    return parseFileNodeResponse(response.data);
  }

  Future<String> downloadUrl(String fileId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/$fileId/download-url',
    );
    final data = parseData(response.data);
    return data['downloadUrl'] as String;
  }

  /// 通过签名地址读取有界文本预览。
  Future<String> loadTextPreview(String fileId) async {
    final url = await downloadUrl(fileId);
    final response = await _uploadDio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-${_textPreviewMaxBytes - 1}'},
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );
    final body = response.data;
    if (body == null) {
      return '';
    }
    final bytes = BytesBuilder(copy: false);
    var remaining = _textPreviewMaxBytes;
    await for (final chunk in body.stream) {
      if (remaining <= 0) {
        break;
      }
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        remaining -= chunk.length;
      } else {
        bytes.add(chunk.sublist(0, remaining));
        remaining = 0;
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Future<void> deleteFile(String fileId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/$fileId',
    );
    parseEmptyResponse(response.data);
  }

  Future<FileNode> restoreFile(String fileId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/restore',
    );
    return parseFileNodeResponse(response.data);
  }

  Future<FileNode> reprocessFile(String fileId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/reprocess',
    );
    return parseFileNodeResponse(response.data);
  }

  Future<TaskSubmission> purgeFile(
    String fileId, {
    bool cascade = false,
    int? expectedVersion,
  }) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/$fileId/purge',
      queryParameters: {
        'cascade': cascade,
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
      },
    );
    return TaskSubmission.fromJson(parseData(response.data));
  }

  Future<FileNode> addFavorite(String fileId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/favorite',
    );
    return parseFileNodeResponse(response.data);
  }

  Future<void> removeFavorite(String fileId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/$fileId/favorite',
    );
    parseEmptyResponse(response.data);
  }

  Future<List<FileNode>> batchDeleteFiles(List<String> fileIds) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/batch/delete',
      data: {'fileIds': fileIds},
    );
    return parseBatchFileNodeResponse(response.data);
  }

  Future<List<FileNode>> batchRestoreFiles(List<String> fileIds) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/batch/restore',
      data: {'fileIds': fileIds},
    );
    return parseBatchFileNodeResponse(response.data);
  }

  Future<TaskSubmission> batchPurgeFiles(
    List<String> fileIds, {
    bool cascade = false,
  }) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/batch/purge',
      data: {'fileIds': fileIds},
      queryParameters: {'cascade': cascade},
    );
    return TaskSubmission.fromJson(parseData(response.data));
  }

  /// 批量下载文件为 ZIP。
  Future<Response<List<int>>> batchDownload(List<String> fileIds) async {
    return apiClient.dio.post<List<int>>(
      '/files/batch/download',
      data: {'fileIds': fileIds},
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<List<FileNode>> batchMoveFiles(
    List<String> fileIds,
    String parentId,
  ) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/batch/move',
      data: {
        'fileIds': fileIds,
        'parentId': parentId.isEmpty ? null : parentId,
      },
    );
    return parseBatchFileNodeResponse(response.data);
  }

  Future<List<FileNode>> batchAddFavorites(List<String> fileIds) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/batch/favorite',
      data: {'fileIds': fileIds},
    );
    return parseBatchFileNodeResponse(response.data);
  }

  Future<void> batchRemoveFavorites(List<String> fileIds) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/batch/favorite',
      data: {'fileIds': fileIds},
    );
    parseEmptyResponse(response.data);
  }

  Future<List<SharedFileItem>> listSharedWithMe() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shared-with-me',
    );
    return parseSharedItemPageResponse(response.data);
  }

  Future<List<FileShareLink>> listMyShares() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shares',
    );
    return parseShareLinkPageResponse(response.data);
  }

  Future<List<FileShareLink>> listShareLinks() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shares',
    );
    return parseShareLinkPageResponse(response.data);
  }

  Future<FileShareLink> createShareLink({
    required String resourceId,
    String resourceType = 'FILE',
    String? password,
    bool generatePassword = false,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/shares',
      data: {
        'resourceId': resourceId,
        'resourceType': resourceType,
        if (password != null && password.isNotEmpty) 'password': password,
        'generatePassword': generatePassword,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (maxAccessCount != null) 'maxAccessCount': maxAccessCount,
      },
    );
    return parseShareLinkResponse(response.data);
  }

  Future<void> revokeShare(String shareId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/shares/$shareId',
    );
    parseEmptyResponse(response.data);
  }

  Future<FileSharePreview> previewShare(
    String token, {
    String? password,
    String? sessionToken,
  }) async {
    final issued = sessionToken ?? await _ensureShareSession(token, password);
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/s/$token/preview',
      options: Options(headers: {'X-OmniNest-Share-Session': issued}),
    );
    final data = parseData(response.data);
    return FileSharePreview(
      shareId: data['shareId']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? AppErrorCodes.unnamedFile,
      mimeType: data['mimeType']?.toString(),
      sizeBytes: _responseParser.asInt(data['sizeBytes']),
      resourceType: data['resourceType']?.toString() ?? 'FILE',
      hasPassword: data['hasPassword'] == true,
    );
  }

  Future<void> acceptShare(
    String token, {
    String? password,
    String? targetParentId,
    String? sessionToken,
  }) async {
    final issued =
        sessionToken ??
        _shareSessionTokens[token] ??
        await _ensureShareSession(token, password);
    await apiClient.dio.post<Map<String, dynamic>>(
      '/s/$token/accept',
      data: {
        if (targetParentId != null && targetParentId.isNotEmpty)
          'targetParentId': targetParentId,
      },
      options: Options(headers: {'X-OmniNest-Share-Session': issued}),
    );
  }

  Future<String> _ensureShareSession(String token, String? password) async {
    final existing = _shareSessionTokens[token];
    if (existing != null && (password == null || password.isEmpty)) {
      return existing;
    }
    final authorization = await apiClient.dio.post<Map<String, dynamic>>(
      '/s/$token/authorize',
      data: {if (password != null && password.isNotEmpty) 'password': password},
    );
    final issued = parseData(authorization.data)['sessionToken']?.toString();
    if (issued == null || issued.isEmpty) {
      throw StateError(AppErrorCodes.shareSessionInvalid);
    }
    _shareSessionTokens[token] = issued;
    return issued;
  }

  Future<FileStorageStats> storageStats() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/storage-stats',
    );
    return parseStorageStatsResponse(response.data);
  }

  Future<FileUploadPolicy> uploadPolicy() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/uploads/policy',
    );
    return parseUploadPolicyResponse(response.data);
  }

  Future<List<FileUploadQueueItem>> listUploadQueue() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/uploads/sessions',
    );
    return parseUploadQueuePageResponse(response.data);
  }

  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/sessions',
      data: {
        'parentId': parentId,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        if (mimeType != null && mimeType.isNotEmpty) 'mimeType': mimeType,
        if (sha256 != null && sha256.isNotEmpty) 'sha256': sha256,
        if (partSizeBytes != null) 'partSizeBytes': partSizeBytes,
        if (spaceType != null) 'spaceType': spaceType,
        if (asVersionOfFileId != null && asVersionOfFileId.isNotEmpty)
          'asVersionOfFileId': asVersionOfFileId,
      },
    );
    return parseUploadSessionResponse(response.data);
  }

  Future<void> completeUploadPart({
    required String uploadId,
    required int partNumber,
    required String eTag,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/$uploadId/parts/$partNumber/complete',
      data: {'partNumber': partNumber, 'eTag': eTag},
    );
    parseEnvelope(response.data);
  }

  Future<FileUploadPartsInfo> listUploadParts(String uploadId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/uploads/$uploadId/parts',
    );
    return parseUploadPartsResponse(response.data);
  }

  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  }) async {
    final dioCancelToken = CancelToken();
    cancellationToken?.addListener(
      () => dioCancelToken.cancel('file-upload-cancelled'),
    );
    final response = await _uploadDio.put<dynamic>(
      uploadUrl,
      data: data,
      cancelToken: dioCancelToken,
      onSendProgress: onProgress,
      options: Options(
        contentType: _binaryContentType,
        headers: {Headers.contentLengthHeader: contentLength},
        responseType: ResponseType.plain,
        validateStatus:
            (status) => status != null && status >= 200 && status < 300,
      ),
    );
    return (response.headers.value('etag') ??
            response.headers.value('ETag') ??
            '')
        .replaceAll('"', '');
  }

  Future<FileUploadCompleteResult> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/$sessionId/complete',
      data: {
        if (sha256 != null && sha256.isNotEmpty) 'sha256': sha256,
        if (asVersionOfFileId != null && asVersionOfFileId.isNotEmpty)
          'asVersionOfFileId': asVersionOfFileId,
      },
    );
    return FileUploadCompleteResult.fromJson(parseData(response.data));
  }

  Future<void> cancelUploadSession(String uploadId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/uploads/$uploadId',
    );
    parseEmptyResponse(response.data);
  }

  Future<List<OfflineDownloadTask>> listOfflineDownloads() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/offline-downloads',
    );
    return parseOfflineTaskPageResponse(response.data);
  }

  Future<OfflineDownloadTask> createOfflineDownload({
    required String sourceUri,
    String? targetParentId,
    String? spaceType,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/offline-downloads',
      data: {
        'sourceUri': sourceUri,
        'targetParentId': targetParentId,
        if (spaceType != null) 'spaceType': spaceType,
      },
    );
    return parseOfflineTaskResponse(response.data);
  }

  Future<void> cancelOfflineDownload(String taskId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/offline-downloads/$taskId',
    );
    parseEmptyResponse(response.data);
  }

  Future<List<ExternalStorageAccount>> listExternalStorages() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages',
    );
    return parseExternalStoragePageResponse(response.data);
  }

  /// 列出可用连接器目录。
  Future<List<ExternalStorageConnector>> listExternalConnectors() async {
    final response = await apiClient.dio.get<List<dynamic>>(
      '/external-connectors',
    );
    final items = response.data ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (json) => ExternalStorageConnector(
            code: json['code']?.toString() ?? '',
            displayName: json['displayName']?.toString() ?? '',
            authMode: json['authMode']?.toString() ?? '',
            availability: json['availability']?.toString() ?? '',
          ),
        )
        .where((item) => item.code.isNotEmpty)
        .toList();
  }

  Future<ExternalStorageAccount> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/external-storages',
      data: {
        'provider': provider,
        'displayName': displayName,
        'encryptedCredentials': encryptedCredentials,
      },
    );
    return parseExternalStorageResponse(response.data);
  }

  Future<ExternalStorageAccount> updateExternalStorage({
    required String accountId,
    required String displayName,
    required String encryptedCredentials,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/external-storages/$accountId',
      data: {
        'displayName': displayName,
        'encryptedCredentials': encryptedCredentials,
      },
    );
    return parseExternalStorageResponse(response.data);
  }

  Future<void> disableExternalStorage(String accountId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/external-storages/$accountId',
    );
    parseEmptyResponse(response.data);
  }

  Future<void> deleteExternalStorage(String accountId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/external-storages/$accountId/permanent',
    );
    parseEmptyResponse(response.data);
  }

  Future<List<ExternalFileItem>> browseExternalStorage(
    String accountId,
    String path,
  ) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages/$accountId/browse',
      queryParameters: {'path': path},
      options: Options(receiveTimeout: _externalStorageTimeout),
    );
    final data = parseData(response.data);
    final items = data['items'];
    if (items is! List) {
      return const [];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(_responseParser.parseExternalFileItem)
        .toList();
  }

  Future<ImportTask> createImportTask(
    String accountId, {
    required String sourcePath,
    required String sourceKind,
    String? targetParentId,
    String? spaceType,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/external-storages/$accountId/import',
      data: {
        'sourcePath': sourcePath,
        'sourceKind': sourceKind,
        if (targetParentId != null) 'targetParentId': targetParentId,
        if (spaceType != null) 'spaceType': spaceType,
      },
    );
    return _responseParser.parseImportTask(parseData(response.data));
  }

  Future<List<ImportTask>> listImportTasks() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages/import-tasks',
    );
    return _responseParser
        .parsePageItems(response.data)
        .map(_responseParser.parseImportTask)
        .toList();
  }

  Future<void> cancelImportTask(String taskId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/external-storages/import-tasks/$taskId',
    );
    parseEmptyResponse(response.data);
  }

  /// 获取外部存储空间用量
  Future<ExternalSpaceUsage> getExternalStorageSpace(String accountId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages/$accountId/space',
      options: Options(receiveTimeout: _externalStorageTimeout),
    );
    return ExternalSpaceUsage.fromJson(parseData(response.data));
  }

  /// 测试外部存储连通性
  Future<void> testExternalStorageConnection(String accountId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/external-storages/$accountId/test',
      options: Options(receiveTimeout: _externalStorageTimeout),
    );
    final data = parseData(response.data);
    if (data['success'] != true) {
      throw Exception(data['message']?.toString() ?? '连接测试失败');
    }
  }

  FileNodePage parseFilePageResponse(Map<String, dynamic>? body) {
    return _responseParser.parseFilePageResponse(body);
  }

  FileNode parseFileNodeResponse(Map<String, dynamic>? body) {
    return _responseParser.parseFileNodeResponse(body);
  }

  List<FileNode> parseBatchFileNodeResponse(Map<String, dynamic>? body) {
    return _responseParser.parseBatchFileNodeResponse(body);
  }

  FileUploadSession parseUploadSessionResponse(Map<String, dynamic>? body) {
    return _responseParser.parseUploadSessionResponse(body);
  }

  FileUploadPartsInfo parseUploadPartsResponse(Map<String, dynamic>? body) {
    return _responseParser.parseUploadPartsResponse(body);
  }

  FileStorageStats parseStorageStatsResponse(Map<String, dynamic>? body) {
    return _responseParser.parseStorageStatsResponse(body);
  }

  FileUploadPolicy parseUploadPolicyResponse(Map<String, dynamic>? body) {
    return _responseParser.parseUploadPolicyResponse(body);
  }

  List<FileShareLink> parseShareLinkPageResponse(Map<String, dynamic>? body) {
    return _responseParser.parseShareLinkPageResponse(body);
  }

  FileShareLink parseShareLinkResponse(Map<String, dynamic>? body) {
    return _responseParser.parseShareLinkResponse(body);
  }

  List<SharedFileItem> parseSharedItemPageResponse(Map<String, dynamic>? body) {
    return _responseParser.parseSharedItemPageResponse(body);
  }

  List<FileUploadQueueItem> parseUploadQueuePageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseUploadQueuePageResponse(body);
  }

  List<OfflineDownloadTask> parseOfflineTaskPageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseOfflineTaskPageResponse(body);
  }

  OfflineDownloadTask parseOfflineTaskResponse(Map<String, dynamic>? body) {
    return _responseParser.parseOfflineTaskResponse(body);
  }

  List<ExternalStorageAccount> parseExternalStoragePageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseExternalStoragePageResponse(body);
  }

  ExternalStorageAccount parseExternalStorageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseExternalStorageResponse(body);
  }

  void parseEmptyResponse(Map<String, dynamic>? body) {
    _responseParser.parseEmptyResponse(body);
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    return _responseParser.parseData(body);
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    return _responseParser.parseEnvelope(body);
  }

  // ============================================================
  // 共享空间相关方法
  // ============================================================

  /// 浏览共享空间目录
  Future<List<FileNode>> listSharedSpaceFiles({String? parentId}) async {
    final page = await listSharedSpaceFilesPage(parentId: parentId);
    return page.items;
  }

  Future<FileNodePage> listSharedSpaceFilesPage({
    String? parentId,
    int page = 0,
    int size = 100,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/shared-space/files',
      queryParameters: {
        if (parentId != null) 'parentId': parentId,
        'page': page,
        'size': size,
      },
    );
    return parseFilePageResponse(response.data);
  }

  /// 在共享空间创建文件夹
  Future<FileNode> createSharedFolder({
    String? parentId,
    required String name,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/shared-space/folders',
      data: {'parentId': parentId, 'name': name},
    );
    return parseFileNodeResponse(response.data);
  }

  /// 重命名共享空间文件或文件夹
  Future<FileNode> renameSharedFile({
    required String fileId,
    required String name,
  }) async {
    final response = await apiClient.dio.patch<Map<String, dynamic>>(
      '/shared-space/files/$fileId/rename',
      data: {'name': name},
    );
    return parseFileNodeResponse(response.data);
  }

  /// 移动文件到共享空间
  Future<void> moveToSharedSpace(String fileId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/shared-space/move-to-shared',
      data: {'fileNodeId': fileId},
    );
    parseEmptyResponse(response.data);
  }

  /// 从共享空间移回个人空间
  Future<void> moveToPersonalSpace(String fileId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/shared-space/move-to-personal',
      data: {'fileNodeId': fileId},
    );
    parseEmptyResponse(response.data);
  }

  /// 删除共享空间文件
  Future<void> deleteSharedFile(String fileId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/shared-space/files/$fileId',
    );
    parseEmptyResponse(response.data);
  }

  /// 获取共享空间使用情况
  Future<SharedSpaceUsage> getSharedSpaceUsage() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/shared-space/usage',
    );
    final data = parseData(response.data);
    return SharedSpaceUsage(
      usedBytes: _responseParser.asInt(data['usedBytes']),
      maxBytes: _responseParser.asInt(data['maxBytes']),
      fileCount: _responseParser.asInt(data['fileCount']),
    );
  }
}
