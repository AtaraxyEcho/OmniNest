part of 'file_api.dart';

mixin FileApiBrowse on FileApiBase {
  Future<List<FileNode>> listFiles({String? parentId, String? category}) async {
    // 非分页遗留入口（全局搜索兜底等）按后端分页上限取近似全量首页。
    final page = await listFilesPage(
      parentId: parentId,
      category: category,
      size: 200,
    );
    prewarmCoverUrls(page.items);
    return page.items;
  }

  /// 封面预热：本页含媒体封面的节点一次批量签齐下载地址，回填会话级
  /// 缓存，列表首屏零逐条签名请求。失败静默（逐条 provider 兜底）。
  void prewarmCoverUrls(List<FileNode> nodes) {
    final coverIds = <String>{
      for (final node in nodes)
        if (!node.isFolder &&
            node.coverFileId != null &&
            node.coverFileId!.isNotEmpty)
          node.coverFileId!,
    };
    if (coverIds.isEmpty) {
      return;
    }
    unawaited(
      _prewarmCoverRequest(
        coverIds.toList(growable: false),
      ).catchError((Object _) {}),
    );
  }

  Future<void> _prewarmCoverRequest(List<String> fileIds) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/download-urls',
      data: {'fileIds': fileIds},
    );
    final data = parseData(response.data);
    final items = data['items'];
    if (items is! List) {
      return;
    }
    final now = DateTime.now();
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final fileId = item['fileId']?.toString();
      final url = item['downloadUrl']?.toString();
      if (fileId != null &&
          fileId.isNotEmpty &&
          url != null &&
          url.isNotEmpty) {
        prewarmDownloadUrl(fileId, url, now);
      }
    }
  }

  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 10,
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

  /// 分页获取回收站：分区页码控件消费。
  Future<FileNodePage> listRecycleBinPage({
    String spaceType = 'PERSONAL',
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/recycle-bin',
      queryParameters: {'spaceType': spaceType, 'page': page, 'size': size},
    );
    return parseFilePageResponse(response.data);
  }

  Future<List<FileNode>> listRecentFiles() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/recent',
    );
    final items = parseFilePageResponse(response.data).items;
    prewarmCoverUrls(items);
    return items;
  }

  /// 分页获取最近文件：分区页码控件消费。
  Future<FileNodePage> listRecentFilesPage({
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/recent',
      queryParameters: {'page': page, 'size': size},
    );
    final result = parseFilePageResponse(response.data);
    prewarmCoverUrls(result.items);
    return result;
  }

  Future<List<FileNode>> listFavoriteFiles() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/favorites',
    );
    final items = parseFilePageResponse(response.data).items;
    prewarmCoverUrls(items);
    return items;
  }

  /// 分页获取收藏文件：分区页码控件消费。
  Future<FileNodePage> listFavoriteFilesPage({
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/favorites',
      queryParameters: {'page': page, 'size': size},
    );
    final result = parseFilePageResponse(response.data);
    prewarmCoverUrls(result.items);
    return result;
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
    final envelope = FileApiBase._responseParser.parseEnvelope(response.data);
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
        headers: {'Range': 'bytes=0-${FileApiBase._textPreviewMaxBytes - 1}'},
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );
    final body = response.data;
    if (body == null) {
      return '';
    }
    final bytes = BytesBuilder(copy: false);
    var remaining = FileApiBase._textPreviewMaxBytes;
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
    return decodeTextFileBytes(bytes.takeBytes());
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

  /// 收藏文件（用户主动写）：无能力时抛 FORBIDDEN，禁止假成功。
  Future<FileNode> addFavorite(String fileId) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/$fileId/favorite',
    );
    return parseFileNodeResponse(response.data);
  }

  /// 取消收藏文件（用户主动写）：无能力时抛 FORBIDDEN。
  Future<void> removeFavorite(String fileId) async {
    apiClient.requirePermission(activityWritePermission);
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
      options: Options(
        responseType: ResponseType.bytes,
        // bytes 响应没有信封：非 2xx 时错误 JSON 会被当成 zip 字节返回。
        validateStatus:
            (status) => status != null && status >= 200 && status < 300,
      ),
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

  /// 批量收藏（用户主动写）：无能力时抛 FORBIDDEN，禁止假成功。
  Future<List<FileNode>> batchAddFavorites(List<String> fileIds) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/files/batch/favorite',
      data: {'fileIds': fileIds},
    );
    return parseBatchFileNodeResponse(response.data);
  }

  /// 批量取消收藏（用户主动写）：无能力时抛 FORBIDDEN。
  Future<void> batchRemoveFavorites(List<String> fileIds) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/files/batch/favorite',
      data: {'fileIds': fileIds},
    );
    parseEmptyResponse(response.data);
  }
}
