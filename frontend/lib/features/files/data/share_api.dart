import 'package:dio/dio.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/features/files/domain/public_share.dart';

/// 分享链接专用 API 客户端，不依赖认证系统。
///
/// 本地兜底文案使用稳定错误码，由 presentation 层映射 l10n；
/// 服务端 message 非空时优先透传。
class ShareApi implements PublicShareRepository {
  ShareApi(String baseUrl)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  /// 从已有 Dio 实例创建，用于测试注入。
  ShareApi.fromDio(this._dio);

  final Dio _dio;
  final Map<String, String> _sessionTokens = <String, String>{};

  void close() => _dio.close(force: true);

  /// 预览分享内容。
  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    try {
      final sessionToken = await _ensureSession(token, password);
      if (sessionToken == null) {
        return SharePreviewResult.needPassword(AppErrorCodes.needPassword);
      }
      final response = await _dio.get<Map<String, dynamic>>(
        '/s/$token/preview',
        options: Options(headers: {'X-OmniNest-Share-Session': sessionToken}),
      );
      final body = response.data;
      if (body == null || body['code'] != 200) {
        return SharePreviewResult.error(
          body?['message']?.toString() ?? AppErrorCodes.operationFailed,
        );
      }
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) {
        return SharePreviewResult.error(AppErrorCodes.emptyResponse);
      }
      return SharePreviewResult.success(
        fileName: data['fileName']?.toString() ?? AppErrorCodes.unnamedFile,
        mimeType: data['mimeType']?.toString(),
        sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
        resourceType: data['resourceType']?.toString() ?? 'FILE',
        hasPassword: data['hasPassword'] == true,
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        if (_isPasswordPrompt(body)) {
          return SharePreviewResult.needPassword(_messageOf(body));
        }
        return SharePreviewResult.error(_messageOf(body));
      }
      return SharePreviewResult.error(_networkErrorCode(e));
    } on Object catch (e) {
      return SharePreviewResult.error('${AppErrorCodes.unknown}: $e');
    }
  }

  /// 浏览分享文件夹的子项。
  @override
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    try {
      final sessionToken = await _ensureSession(token, null);
      if (sessionToken == null) {
        return ShareChildrenResult.error(AppErrorCodes.needPassword);
      }
      final response = await _dio.get<Map<String, dynamic>>(
        '/s/$token/children',
        queryParameters: {
          if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
          'page': page,
          'size': size,
        },
        options: Options(headers: {'X-OmniNest-Share-Session': sessionToken}),
      );
      final body = response.data;
      if (body == null || body['code'] != 200) {
        return ShareChildrenResult.error(
          body?['message']?.toString() ?? AppErrorCodes.operationFailed,
        );
      }
      final data = body['data'] as Map<String, dynamic>?;
      final raw = data?['items'];
      if (raw is! List) {
        return ShareChildrenResult.error(AppErrorCodes.emptyResponse);
      }
      return ShareChildrenResult.success(
        items: raw
            .whereType<Map<String, dynamic>>()
            .map(ShareChild.fromJson)
            .toList(growable: false),
        total: (data?['totalElements'] as num?)?.toInt() ?? raw.length,
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        return ShareChildrenResult.error(
          _isPasswordPrompt(body)
              ? AppErrorCodes.needPassword
              : _messageOf(body),
        );
      }
      return ShareChildrenResult.error(_networkErrorCode(e));
    } on Object catch (e) {
      return ShareChildrenResult.error('${AppErrorCodes.unknown}: $e');
    }
  }

  /// 接受分享，保存文件到当前用户。
  @override
  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  }) async {
    try {
      final sessionToken = await _ensureSession(token, password);
      final response = await _dio.post<Map<String, dynamic>>(
        '/s/$token/accept',
        options: Options(
          headers: {
            if (authToken != null) 'Authorization': 'Bearer $authToken',
            'X-OmniNest-Share-Session': sessionToken,
          },
        ),
      );
      final body = response.data;
      if (body == null || body['code'] != 200) {
        return ShareAcceptResult.error(
          body?['message']?.toString() ?? AppErrorCodes.operationFailed,
        );
      }
      return ShareAcceptResult.success();
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        final msg = _messageOf(body);
        if (_isPasswordPrompt(body)) {
          return ShareAcceptResult.error(AppErrorCodes.needPassword);
        }
        if (_isConflict(body)) {
          return ShareAcceptResult.duplicate(msg);
        }
        return ShareAcceptResult.error(msg);
      }
      return ShareAcceptResult.error(_networkErrorCode(e));
    } on Object catch (e) {
      return ShareAcceptResult.error('${AppErrorCodes.unknown}: $e');
    }
  }

  /// 匿名获取单文件的短期下载地址。
  ///
  /// 后端 `GET /s/{token}` 凭分享会话即可签发预签名地址，不需要系统账号；
  /// 文件夹分享返回空地址（子项各自带 downloadUrl）。
  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    try {
      final sessionToken = await _ensureSession(token, password);
      if (sessionToken == null) {
        return ShareAccessResult.failure(AppErrorCodes.needPassword);
      }
      final response = await _dio.get<Map<String, dynamic>>(
        '/s/$token',
        options: Options(headers: {'X-OmniNest-Share-Session': sessionToken}),
      );
      final body = response.data;
      if (body == null || body['code'] != 200) {
        return ShareAccessResult.failure(
          body?['message']?.toString() ?? AppErrorCodes.operationFailed,
        );
      }
      final data = body['data'] as Map<String, dynamic>?;
      final url = data?['downloadUrl']?.toString();
      if (url == null || url.isEmpty) {
        return ShareAccessResult.failure(AppErrorCodes.emptyResponse);
      }
      return ShareAccessResult.success(url);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        return ShareAccessResult.failure(
          _isPasswordPrompt(body)
              ? AppErrorCodes.needPassword
              : _messageOf(body),
        );
      }
      return ShareAccessResult.failure(_networkErrorCode(e));
    } on Object catch (e) {
      return ShareAccessResult.failure('${AppErrorCodes.unknown}: $e');
    }
  }

  Future<String?> _ensureSession(String token, String? password) async {
    final existing = _sessionTokens[token];
    if (existing != null && (password == null || password.isEmpty)) {
      return existing;
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/s/$token/authorize',
      data: {if (password != null && password.isNotEmpty) 'password': password},
    );
    final body = response.data;
    if (body == null || body['code'] != 200) {
      if (body != null && _isPasswordPrompt(body)) {
        return null;
      }
      throw StateError(_messageOf(body));
    }
    final data = body['data'] as Map<String, dynamic>?;
    final session = data?['sessionToken']?.toString();
    if (session == null || session.isEmpty) {
      throw StateError(AppErrorCodes.shareSessionInvalid);
    }
    _sessionTokens[token] = session;
    return session;
  }

  /// 判断业务信封是否需要用户补密码或提示密码错误。
  ///
  /// 后端的 `code` 是业务码（需要密码 9006、密码错误 9004），HTTP 状态才是 401，
  /// 因此判据以 `errorName` 为准、业务码兜底，不能拿 401 当业务码比较。
  bool _isPasswordPrompt(Map<String, dynamic> body) {
    final errorName = body['errorName']?.toString();
    if (errorName == AppErrorCodes.sharePasswordRequired ||
        errorName == AppErrorCodes.passwordInvalid) {
      return true;
    }
    final code = body['code'];
    return code == 9006 || code == 9004;
  }

  bool _isConflict(Map<String, dynamic> body) {
    final errorName = body['errorName']?.toString();
    if (errorName == 'CONFLICT' || errorName == 'FILE_LIFECYCLE_CONFLICT') {
      return true;
    }
    return body['code'] == 409;
  }

  String _messageOf(Map<String, dynamic>? body) {
    return body?['message']?.toString() ?? AppErrorCodes.operationFailed;
  }

  String _networkErrorCode(DioException exception) {
    return switch (exception.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => AppErrorCodes.networkTimeout,
      _ => AppErrorCodes.networkError,
    };
  }
}
