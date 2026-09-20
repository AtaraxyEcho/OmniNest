import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/server/server_config.dart';

/// 探活失败原因；由引导页映射为用户可读文案。
enum ServerProbeFailure { unreachable, timeout, notOmniNest, rejected }

/// 探活结果：成功时 [setupRequired] 非空，失败时 [failure] 非空。
class ServerProbeResult {
  const ServerProbeResult._(this.setupRequired, this.failure);

  const ServerProbeResult.success({required bool requiredSetup})
    : this._(requiredSetup, null);

  const ServerProbeResult.failure(ServerProbeFailure failure)
    : this._(null, failure);

  final bool? setupRequired;
  final ServerProbeFailure? failure;

  bool get isSuccess => failure == null;
}

/// 首启引导的服务器探活客户端。
///
/// 对候选地址 GET /setup/status：2xx 且响应可解析为标准信封中的
/// 安装状态结构视为 OmniNest 服务器；取消（页面退出）时原样抛出
/// DioException(cancel)，由调用方静默处理。
class ServerProbeClient {
  ServerProbeClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  Future<ServerProbeResult> probe(
    ServerConfig config, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<String>(
        '${config.apiBaseUrl}/setup/status',
        cancelToken: cancelToken,
      );
      return _parseResponse(response);
    } on DioException catch (error) {
      final failure = _mapDioException(error);
      if (failure == null) {
        rethrow;
      }
      return ServerProbeResult.failure(failure);
    }
  }

  ServerProbeResult _parseResponse(Response<String> response) {
    if (response.statusCode == null || response.statusCode! >= 400) {
      return const ServerProbeResult.failure(ServerProbeFailure.rejected);
    }
    try {
      final decoded = jsonDecode(response.data ?? '');
      if (decoded is! Map<String, dynamic>) {
        return const ServerProbeResult.failure(ServerProbeFailure.notOmniNest);
      }
      final code = decoded['code'];
      if (code is! int || code >= 400) {
        return const ServerProbeResult.failure(ServerProbeFailure.rejected);
      }
      final data = decoded['data'];
      if (data is! Map || data['setupRequired'] is! bool) {
        return const ServerProbeResult.failure(ServerProbeFailure.notOmniNest);
      }
      return ServerProbeResult.success(
        requiredSetup: data['setupRequired'] as bool,
      );
    } on FormatException {
      return const ServerProbeResult.failure(ServerProbeFailure.notOmniNest);
    }
  }

  ServerProbeFailure? _mapDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ServerProbeFailure.timeout;
      case DioExceptionType.connectionError:
        return ServerProbeFailure.unreachable;
      case DioExceptionType.badResponse:
        return ServerProbeFailure.rejected;
      case DioExceptionType.cancel:
        return null;
      case DioExceptionType.badCertificate:
        return ServerProbeFailure.unreachable;
      default:
        return ServerProbeFailure.unreachable;
    }
  }
}

final serverProbeClientProvider = Provider<ServerProbeClient>((ref) {
  return ServerProbeClient();
});
