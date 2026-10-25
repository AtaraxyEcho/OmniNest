part of 'file_api.dart';

mixin FileApiShares on FileApiBase {
  Future<List<SharedFileItem>> listSharedWithMe() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shared-with-me',
    );
    return parseSharedItemPageResponse(response.data);
  }

  /// 分页获取共享给我列表：子表页码控件消费。
  Future<FilesSubPage<SharedFileItem>> listSharedWithMePage({
    int page = 0,
    int size = 10,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shared-with-me',
      queryParameters: {'page': page, 'size': size},
    );
    return FilesSubPage.fromJson(
      parseData(response.data),
      FileApiBase._responseParser.decodeSharedItem,
    );
  }

  /// 分页浏览定向分享给当前用户的文件夹子树。
  ///
  /// 接收人拿不到分享明文 token，只能按分享标识走鉴权链；服务端以"接收人 ↔ 分享链接"
  /// 关系授权，并把可见范围钉在分享根目录子树内。
  Future<FilesSubPage<ShareChild>> listSharedFolderChildren({
    required String shareId,
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shared-with-me/$shareId/children',
      queryParameters: {
        if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
        'page': page,
        'size': size,
      },
    );
    return FilesSubPage.fromJson(parseData(response.data), ShareChild.fromJson);
  }

  Future<List<FileShareLink>> listMyShares() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shares',
    );
    return parseShareLinkPageResponse(response.data);
  }

  /// 分页获取我的分享链接：子表页码控件消费。
  Future<FilesSubPage<FileShareLink>> listMySharesPage({
    int page = 0,
    int size = 10,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/shares',
      queryParameters: {'page': page, 'size': size},
    );
    return FilesSubPage.fromJson(
      parseData(response.data),
      FileApiBase._responseParser.decodeShareLink,
    );
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

  /// 修改分享链接设置：令牌与资源不变，已发出的地址继续可用。
  ///
  /// 与创建不同，这里的空值有语义：[password] 传空串表示清除密码，[expiresAt]
  /// 传空串表示改为长期有效，[maxAccessCount] 传 0 表示不限次数；传 null 表示保持原值。
  Future<FileShareLink> updateShareLink({
    required String shareId,
    String? password,
    String? expiresAt,
    int? maxAccessCount,
  }) async {
    final response = await apiClient.dio.patch<Map<String, dynamic>>(
      '/files/shares/$shareId',
      data: {
        if (password != null) 'password': password,
        if (expiresAt != null) 'expiresAt': expiresAt,
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

  /// 探测文件媒体元数据（视频时长/分辨率，图片尺寸）。
  Future<FileMediaInfo> mediaInfo(String fileId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/files/$fileId/media-info',
    );
    final data = parseData(response.data);
    int? asIntOrNull(Object? value) =>
        value == null ? null : FileApiBase._responseParser.asInt(value);
    return FileMediaInfo(
      durationSeconds: FileApiBase._responseParser.asDouble(
        data['durationSeconds'],
      ),
      width: asIntOrNull(data['width']),
      height: asIntOrNull(data['height']),
    );
  }

  Future<FileSharePreview> previewShare(
    String token, {
    String? password,
    String? sessionToken,
  }) async {
    final explicitSession = sessionToken;
    var issued =
        explicitSession ??
        _cachedShareSession(token) ??
        await _ensureShareSession(token, password);
    try {
      return _parseSharePreview(await _loadSharePreview(token, issued));
    } on Object catch (error) {
      if (explicitSession != null || !_isShareSessionInvalid(error)) {
        rethrow;
      }
      _shareSessionTokens.remove(token);
      issued = await _ensureShareSession(token, password);
      return _parseSharePreview(await _loadSharePreview(token, issued));
    }
  }

  Future<Map<String, dynamic>> _loadSharePreview(
    String token,
    String session,
  ) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/s/$token/preview',
      options: Options(headers: {'X-OmniNest-Share-Session': session}),
    );
    return parseData(response.data);
  }

  FileSharePreview _parseSharePreview(Map<String, dynamic> data) {
    return FileSharePreview(
      shareId: data['shareId']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? AppErrorCodes.unnamedFile,
      mimeType: data['mimeType']?.toString(),
      sizeBytes: FileApiBase._responseParser.asInt(data['sizeBytes']),
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
    final explicitSession = sessionToken;
    var issued =
        explicitSession ??
        _cachedShareSession(token) ??
        await _ensureShareSession(token, password);
    try {
      await _acceptShareOnce(token, issued, targetParentId);
    } on Object catch (error) {
      if (explicitSession != null || !_isShareSessionInvalid(error)) {
        rethrow;
      }
      _shareSessionTokens.remove(token);
      issued = await _ensureShareSession(token, password);
      await _acceptShareOnce(token, issued, targetParentId);
    }
  }

  Future<void> _acceptShareOnce(
    String token,
    String session,
    String? targetParentId,
  ) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/s/$token/accept',
      data: {
        if (targetParentId != null && targetParentId.isNotEmpty)
          'targetParentId': targetParentId,
      },
      options: Options(headers: {'X-OmniNest-Share-Session': session}),
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '保存分享文件失败');
  }

  String? _cachedShareSession(String token) {
    final cached = _shareSessionTokens[token];
    if (cached == null) {
      return null;
    }
    if (!cached.isUsable) {
      _shareSessionTokens.remove(token);
      return null;
    }
    return cached.token;
  }

  bool _isShareSessionInvalid(Object error) {
    String? code;
    if (error is AppException) {
      code = error.details['errorName']?.toString() ?? error.code;
    } else if (error is DioException) {
      final body = error.response?.data;
      if (body is Map) {
        code = body['errorName']?.toString() ?? body['code']?.toString();
      }
      code ??= error.response?.statusCode?.toString();
    }
    return code == AppErrorCodes.shareSessionInvalid ||
        code == 'UNAUTHORIZED' ||
        code == '401';
  }

  Future<String> _ensureShareSession(String token, String? password) async {
    // 已有会话在有效期内直接复用，避免带密码重复 authorize 造成访问次数重复扣减。
    final existing = _cachedShareSession(token);
    if (existing != null) {
      return existing;
    }
    final authorization = await apiClient.dio.post<Map<String, dynamic>>(
      '/s/$token/authorize',
      data: {if (password != null && password.isNotEmpty) 'password': password},
    );
    final data = parseData(authorization.data);
    final issued = data['sessionToken']?.toString();
    if (issued == null || issued.isEmpty) {
      throw StateError(AppErrorCodes.shareSessionInvalid);
    }
    _shareSessionTokens[token] = _CachedShareSession(
      issued,
      DateTime.tryParse(data['expiresAt']?.toString() ?? '')?.toLocal(),
    );
    return issued;
  }
}
