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
        final code = body['code'];
        final msg =
            body['message']?.toString() ?? AppErrorCodes.operationFailed;
        if (code == 401 || (code == 400 && msg == AppErrorCodes.needPassword)) {
          return SharePreviewResult.needPassword(
            msg == AppErrorCodes.operationFailed
                ? AppErrorCodes.needPassword
                : msg,
          );
        }
        return SharePreviewResult.error(msg);
      }
      return SharePreviewResult.error(_networkErrorCode(e));
    } on Object catch (e) {
      return SharePreviewResult.error('${AppErrorCodes.unknown}: $e');
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
        final code = body['code'];
        final msg =
            body['message']?.toString() ?? AppErrorCodes.operationFailed;
        if (code == 409) {
          return ShareAcceptResult.duplicate(msg);
        }
        return ShareAcceptResult.error(msg);
      }
      return ShareAcceptResult.error(_networkErrorCode(e));
    } on Object catch (e) {
      return ShareAcceptResult.error('${AppErrorCodes.unknown}: $e');
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
      final code = body?['code'];
      final message =
          body?['message']?.toString() ?? AppErrorCodes.operationFailed;
      if (code == 401 || message == AppErrorCodes.needPassword) {
        return null;
      }
      throw StateError(message);
    }
    final data = body['data'] as Map<String, dynamic>?;
    final session = data?['sessionToken']?.toString();
    if (session == null || session.isEmpty) {
      throw StateError(AppErrorCodes.shareSessionInvalid);
    }
    _sessionTokens[token] = session;
    return session;
  }

  String _networkErrorCode(DioException exception) {
    return switch (exception.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => AppErrorCodes.networkTimeout,
      _ => AppErrorCodes.networkError,
    };
  }
}
