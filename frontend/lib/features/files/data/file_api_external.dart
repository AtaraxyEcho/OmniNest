part of 'file_api.dart';

mixin FileApiExternal on FileApiBase {
  Future<List<ExternalStorageAccount>> listExternalStorages() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages',
    );
    return parseExternalStoragePageResponse(response.data);
  }

  /// 列出可用连接器目录。
  Future<List<ExternalStorageConnector>> listExternalConnectors() async {
    // 后端返回 ApiResponse<List<...>> 对象信封，按 List 声明响应类型会让 Dio
    // 在 cast 时抛错，调用方的 catch 把它降级成空列表。
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-connectors',
    );
    final items = parseEnvelope(response.data)['data'];
    if (items is! List) {
      return const [];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (json) => ExternalStorageConnector(
            code: json['code']?.toString() ?? '',
            displayName: json['displayName']?.toString() ?? '',
            authMode: json['authMode']?.toString() ?? '',
            availability: json['availability']?.toString() ?? '',
            oauthConfigured: json['oauthConfigured'] != false,
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
      options: Options(receiveTimeout: FileApiBase._externalStorageTimeout),
    );
    final data = parseData(response.data);
    final items = data['items'];
    if (items is! List) {
      return const [];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(FileApiBase._responseParser.parseExternalFileItem)
        .toList();
  }

  /// 分页浏览外部存储目录：返回页内容与分页元数据，子表页码控件消费。
  Future<({List<ExternalFileItem> items, FilesSubPageMeta meta})>
  browseExternalStoragePage(
    String accountId,
    String path, {
    int page = 0,
    int size = 10,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages/$accountId/browse',
      queryParameters: {'path': path, 'page': page, 'size': size},
      options: Options(receiveTimeout: FileApiBase._externalStorageTimeout),
    );
    final data = parseData(response.data);
    final rawItems = data['items'];
    final items =
        rawItems is List
            ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(FileApiBase._responseParser.decodeExternalFile)
                .toList(growable: false)
            : const <ExternalFileItem>[];
    return (
      items: items,
      meta: FilesSubPageMeta(
        page: (data['page'] as num?)?.toInt() ?? page,
        size: (data['size'] as num?)?.toInt() ?? size,
        totalElements: (data['totalElements'] as num?)?.toInt() ?? items.length,
        totalPages: (data['totalPages'] as num?)?.toInt() ?? 1,
      ),
    );
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
    return FileApiBase._responseParser.parseImportTask(
      parseData(response.data),
    );
  }

  Future<List<ImportTask>> listImportTasks() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages/import-tasks',
    );
    return FileApiBase._responseParser
        .parsePageItems(response.data)
        .map(FileApiBase._responseParser.parseImportTask)
        .toList();
  }

  /// 分页获取外部存储导入任务：子表页码控件消费。
  Future<FilesSubPage<ImportTask>> listImportTasksPage({
    int page = 0,
    int size = 10,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/external-storages/import-tasks',
      queryParameters: {'page': page, 'size': size},
    );
    return FilesSubPage.fromJson(
      parseData(response.data),
      FileApiBase._responseParser.decodeImportTask,
    );
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
      options: Options(receiveTimeout: FileApiBase._externalStorageTimeout),
    );
    return ExternalSpaceUsage.fromJson(parseData(response.data));
  }

  /// 测试外部存储连通性
  Future<void> testExternalStorageConnection(String accountId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/external-storages/$accountId/test',
      options: Options(receiveTimeout: FileApiBase._externalStorageTimeout),
    );
    final data = parseData(response.data);
    if (data['success'] != true) {
      throw Exception(data['message']?.toString() ?? '连接测试失败');
    }
  }

  /// 开始 OAuth 授权，返回授权 URL。
  Future<String> startExternalOAuth({
    required String connectorCode,
    required String accountId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/external-connectors/$connectorCode/oauth/start',
      queryParameters: {'accountId': accountId},
    );
    final data = parseData(response.data);
    final url = data['authorizationUrl']?.toString() ?? '';
    if (url.isEmpty) {
      throw Exception('未返回授权地址，请检查 OAuth 应用配置');
    }
    return url;
  }

  // 共享空间相关方法
  // ============================================================

  /// 浏览共享空间目录
  Future<List<FileNode>> listSharedSpaceFiles({String? parentId}) async {
    // 非分页遗留入口按后端分页上限取近似全量首页。
    final page = await listSharedSpaceFilesPage(parentId: parentId, size: 200);
    return page.items;
  }

  Future<FileNodePage> listSharedSpaceFilesPage({
    String? parentId,
    int page = 0,
    int size = 10,
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
      usedBytes: FileApiBase._responseParser.asInt(data['usedBytes']),
      maxBytes: FileApiBase._responseParser.asInt(data['maxBytes']),
      fileCount: FileApiBase._responseParser.asInt(data['fileCount']),
    );
  }
}
