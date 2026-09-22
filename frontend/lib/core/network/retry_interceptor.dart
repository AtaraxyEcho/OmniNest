import 'dart:async';

import 'package:dio/dio.dart';

/// 可重试的 HTTP 状态码集合。
const _retryableStatusCodes = {408, 429, 500, 502, 503, 504};

/// 幂等 HTTP 方法集合，这些方法默认允许基于 HTTP 状态码重试。
const _idempotentMethods = {'GET', 'HEAD', 'PUT', 'DELETE', 'OPTIONS'};

/// 请求级开关：置为 `true` 时跳过"服务端错误重试"，只保留网络层重试。
///
/// 用于用户已确认的一次性动作（如断开平台连接）：这类请求服务端若返回 5xx，
/// 重试既注定失败又会把等待时间放大为退避之和，体感是"点了很久没反应"。
const skipServerErrorRetryKey = 'omninest.skipServerErrorRetry';

/// Dio 请求重试拦截器。
///
/// 对于幂等方法（GET/HEAD/PUT/DELETE/OPTIONS），在连接异常或可重试
/// HTTP 状态码（408/429/500/502/503/504）时重试。
/// 非幂等请求只有显式携带 `Idempotency-Key` 时才允许自动重试。
///
/// 使用指数退避策略，初始延迟为 [baseDelay]。
/// 重试次数存储在 `requestOptions.extra['retryCount']` 中。
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    this.maxRetries = 2,
    this.baseDelay = const Duration(seconds: 1),
  });

  /// 持有 Dio 实例引用，重试时通过同一实例发起请求以保留拦截器链。
  Dio? _dio;

  /// 绑定 Dio 实例（在 Dio 初始化后调用）。
  void setDio(Dio dio) => _dio = dio;

  /// 最大重试次数。
  final int maxRetries;

  /// 基础延迟时间，实际延迟为 baseDelay * 2^retryCount。
  final Duration baseDelay;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final retryCount = _currentRetryCount(err.requestOptions);

    // 已达到最大重试次数，直接传递错误
    if (retryCount >= maxRetries) {
      handler.next(err);
      return;
    }

    if (!_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    // 计算指数退避延迟
    final delay = baseDelay * (1 << retryCount);

    await Future<void>.delayed(delay);

    // 递增重试计数
    err.requestOptions.extra['retryCount'] = retryCount + 1;

    try {
      final dio = _dio;
      if (dio == null) {
        handler.next(err);
        return;
      }
      final response = await dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    } on Exception catch (_) {
      handler.next(err);
    }
  }

  /// 判断是否应该重试当前请求。
  bool _shouldRetry(DioException err) {
    final request = err.requestOptions;
    if (!_isRetrySafe(request)) {
      return false;
    }

    if (_isRetryableErrorType(err)) {
      return true;
    }

    // 显式声明"服务端错误不重试"的请求只走网络层重试。
    if (request.extra[skipServerErrorRetryKey] == true) {
      return false;
    }

    // HTTP 状态码重试需要通过上面的安全重试判定。
    final statusCode = err.response?.statusCode;
    if (statusCode != null && _retryableStatusCodes.contains(statusCode)) {
      return true;
    }

    return false;
  }

  /// 判断是否为可重试的网络错误类型。
  bool _isRetryableErrorType(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;
  }

  /// 判断 HTTP 方法是否幂等。
  bool _isIdempotent(String method) {
    return _idempotentMethods.contains(method.toUpperCase());
  }

  bool _isRetrySafe(RequestOptions options) {
    if (_isIdempotent(options.method)) {
      return true;
    }
    final idempotencyKey =
        options.headers.entries
            .where((entry) => entry.key.toLowerCase() == 'idempotency-key')
            .map((entry) => entry.value?.toString().trim())
            .firstOrNull;
    return idempotencyKey?.isNotEmpty == true;
  }

  /// 获取当前已重试次数。
  int _currentRetryCount(RequestOptions options) {
    final count = options.extra['retryCount'];
    if (count is int) return count;
    return 0;
  }
}
