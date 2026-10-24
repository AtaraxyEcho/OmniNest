part of 'file_api.dart';

mixin FileApiUpload on FileApiBase {
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

  /// 分页获取上传会话队列：子表页码控件消费。
  Future<FilesSubPage<FileUploadQueueItem>> listUploadQueuePage({
    int page = 0,
    int size = 10,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/uploads/sessions',
      queryParameters: {'page': page, 'size': size},
    );
    return FilesSubPage.fromJson(
      parseData(response.data),
      FileApiBase._responseParser.decodeUploadQueueItem,
    );
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

  /// 按需获取单个分片的预签名上传地址。
  ///
  /// 创建会话只返回前若干个分片的地址，其余分片在上传前逐个拉取，
  /// 避免一次请求在事务内生成上千个签名。
  Future<String> getUploadPartUrl({
    required String uploadId,
    required int partNumber,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/uploads/$uploadId/parts/$partNumber/url',
    );
    final data = parseData(response.data);
    final uploadUrl = data['uploadUrl']?.toString();
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const AppException(
        code: AppErrorCodes.uploadUrlMissing,
        message: AppErrorCodes.uploadUrlMissing,
      );
    }
    return uploadUrl;
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
        contentType: FileApiBase._binaryContentType,
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
}
