import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/auth/auth_session_store.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/network/retry_interceptor.dart';
import 'package:omninest/core/log/dev_log.dart';

typedef AccessTokenReader = String? Function();
typedef SessionRefresher = Future<bool> Function();
typedef PermissionReader = Set<String> Function();

class ApiClient {
  ApiClient(
    AppEnvironment environment, {
    AuthSessionStore? sessionStore,
    AccessTokenReader? readAccessToken,
    SessionRefresher? refreshSession,
    PermissionReader? readPermissions,
    HttpClientAdapter? httpClientAdapter,
  }) : _sessionStore = sessionStore,
       _readAccessToken = readAccessToken,
       _refreshSession = refreshSession,
       _readPermissions = readPermissions,
       _apiBaseUri = Uri.tryParse(environment.apiBaseUrl),
       dio = Dio(
         BaseOptions(
           baseUrl: environment.apiBaseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 30),
           validateStatus: (status) => status != null && status < 500,
         ),
       ) {
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
    }
    final retryInterceptor = RetryInterceptor();
    dio.interceptors.add(retryInterceptor);
    retryInterceptor.setDio(dio);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 绝对 URL 指向对象存储/CDN 时，Bearer JWT 与 withCredentials 都不能外带。
          if (_isExternalOrigin(options.uri)) {
            options.extra[skipAuthorizationKey] = true;
          }
          final skipAuthorization = options.extra[skipAuthorizationKey] == true;
          // 每个后端请求生成 X-Request-Id 与日志关联；skipAuthorization 的请求
          // 目标是外部地址（对象存储预签名等），自定义头会触发不必要的跨源预检
          if (!skipAuthorization) {
            options.headers['X-Request-Id'] = const Uuid().v4();
          }
          if (kIsWeb && !skipAuthorization) {
            options.extra['withCredentials'] = true;
          }
          if (!skipAuthorization) {
            final token = _currentAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
              options.extra[_requestTokenKey] = token;
              // 带上令牌即视为会话已重建，恢复刷新尝试。
              _refreshRejected = false;
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (_isUnrecoverableSession401(response)) {
            handler.reject(
              DioException.badResponse(
                statusCode: 401,
                requestOptions: response.requestOptions,
                response: response,
              ),
            );
            return;
          }
          if (!_shouldRefresh(response)) {
            handler.next(response);
            return;
          }
          try {
            handler.resolve(
              await _refreshAndReplay(response.requestOptions, response),
            );
          } on DioException catch (error) {
            handler.reject(error);
          } catch (error) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: error,
              ),
            );
          }
        },
        onError: (error, handler) async {
          // 二进制/流式接口在请求级覆写 validateStatus 为 2xx-only，401 会直接
          // 进入 onError 而不是 onResponse；刷新逻辑必须在这里同样生效。
          final response = error.response;
          if (response != null && _shouldRefresh(response)) {
            try {
              handler.resolve(
                await _refreshAndReplay(error.requestOptions, response),
              );
              return;
            } on DioException catch (retryError) {
              handler.next(retryError);
              return;
            } catch (_) {
              handler.next(error);
              return;
            }
          }
          // 全局错误日志（避免未捕获异常导致 UI 崩溃）
          if (kDebugMode) {
            devLog(
              'DioError: ${error.type} - ${error.message} '
              '[${error.requestOptions.method} ${error.requestOptions.path}]',
            );
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _requestTokenKey = 'omninest.requestAccessToken';
  static const _retriedKey = 'omninest.authRetried';

  /// 外部签名地址使用此标记，避免向对象存储泄露 JWT。
  final Uri? _apiBaseUri;

  static const skipAuthorizationKey = 'omninest.skipAuthorization';

  final Dio dio;
  final AuthSessionStore? _sessionStore;
  final AccessTokenReader? _readAccessToken;
  final SessionRefresher? _refreshSession;
  final PermissionReader? _readPermissions;
  String? _manualAccessToken;
  Future<bool>? _refreshing;

  /// 刷新已被确定拒绝且本地无访问令牌时挂起后续刷新尝试。
  ///
  /// 否则退出登录后每个轮询请求都会再触发一次注定 401 的 `/auth/refresh`，
  /// 与业务请求成对刷屏。重新登录带上令牌后由 [dio] 的请求拦截解除。
  bool _refreshRejected = false;

  /// 当前会话是否持有指定权限码。
  ///
  /// data 层 API 用它在发请求前做能力预检（autoSkip 静默跳过 / strict 抛
  /// FORBIDDEN）。未注入读取器（如单元测试直接构造 ApiClient）时视为有
  /// 权限放行，由后端 @PreAuthorize 兜底，保持既有测试行为不变。
  bool hasPermission(String code) {
    final reader = _readPermissions;
    if (reader == null) {
      return true;
    }
    return reader().contains(code);
  }

  /// strict 写预检：无权限时抛 FORBIDDEN，由 error_code_l10n 映射用户文案。
  ///
  /// 用户主动写（收藏 / 书签 / 删历史 / 通知等）必须在发请求前调用，
  /// 禁止依赖后端 403 兜底呈现「无权限」。
  void requirePermission(String code) {
    if (!hasPermission(code)) {
      throw const AppException(
        code: AppErrorCodes.forbidden,
        message: '没有权限执行该操作',
      );
    }
  }

  void setAccessToken(String? token) {
    _manualAccessToken = token;
    final store = _sessionStore;
    if (store != null) {
      unawaited(store.saveAccessToken(token));
    }
  }

  String? currentAccessToken() {
    return _readAccessToken?.call() ??
        _sessionStore?.readAccessToken() ??
        _manualAccessToken;
  }

  String? _currentAccessToken() {
    return currentAccessToken();
  }

  /// 会话已经确认失效后，后续 401 必须与首个失败请求保持相同的异常语义。
  ///
  /// <p>业务级 401（分享密码、2FA 复核）仍交由调用方解析信封，不能在这里
  /// 统一拒绝；只处理令牌已被拒绝且不会再次刷新的会话失效。</p>
  bool _isExternalOrigin(Uri uri) {
    if (!uri.hasAuthority) {
      return false;
    }
    final base = _apiBaseUri;
    if (base == null || !base.hasAuthority) {
      return false;
    }
    int effectivePort(Uri value) {
      if (value.hasPort) {
        return value.port;
      }
      return switch (value.scheme) {
        'https' => 443,
        'http' => 80,
        _ => -1,
      };
    }

    return uri.scheme != base.scheme ||
        uri.host != base.host ||
        effectivePort(uri) != effectivePort(base);
  }

  bool _isUnrecoverableSession401(Response<dynamic> response) {
    if (response.statusCode != 401 || !_refreshRejected) {
      return false;
    }
    if (response.requestOptions.extra[skipAuthorizationKey] == true) {
      return false;
    }
    final path = response.requestOptions.path;
    if (path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh')) {
      return false;
    }
    final data = response.data;
    if (data is Map) {
      final errorName = data['errorName']?.toString();
      if (errorName == 'PASSWORD_INVALID' ||
          errorName == 'SHARE_PASSWORD_REQUIRED') {
        return false;
      }
    }
    return true;
  }

  bool _shouldRefresh(Response<dynamic> response) {
    // 会话已确定失效且尚未重新登录时不再尝试刷新，避免退出登录后
    // 轮询请求成对刷出 /auth/refresh + 业务接口的 401。
    if (_refreshRejected) {
      return false;
    }
    // 只有 401 才代表访问令牌本身需要轮换。403 是 RBAC 权限拒绝：换一枚新令牌换不来
    // 权限，而授权变更时服务端已吊销旧会话（刷新接口会返回 401 走正常重登），管理端
    // 改动自己也显式触发刷新。让每个无权限请求都多付一次 /auth/refresh 加一次原请求
    // 重放，只会把报错延迟翻倍并挤占刷新接口的限流额度。
    final statusCode = response.statusCode;
    if (statusCode != 401 ||
        response.requestOptions.extra[skipAuthorizationKey] == true) {
      return false;
    }
    final path = response.requestOptions.path;
    if (path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh')) {
      return false;
    }
    // 401 也承载业务级密码校验（分享访问密码、2FA 复核）。这类拒绝
    // 与令牌无关，刷新只会轮换令牌并用同一错误密码重放请求。
    final data = response.data;
    if (data is Map) {
      final errorName = data['errorName']?.toString();
      if (errorName == 'PASSWORD_INVALID' ||
          errorName == 'SHARE_PASSWORD_REQUIRED') {
        return false;
      }
    }
    return response.requestOptions.extra[_retriedKey] != true;
  }

  /// 401 后刷新令牌并重放原请求；刷新失败时抛出携带原响应的 401。
  Future<Response<dynamic>> _refreshAndReplay(
    RequestOptions requestOptions,
    Response<dynamic> response,
  ) async {
    final originalToken = requestOptions.extra[_requestTokenKey]?.toString();
    final currentToken = _currentAccessToken();
    var refreshed =
        currentToken != null &&
                currentToken.isNotEmpty &&
                originalToken != null &&
                currentToken != originalToken
            ? true
            : await _refreshOnce();
    if (!refreshed) {
      // 刷新调用失败但令牌可能已被并发路径更新（如周期刷新恰好成功），
      // 复核一次签名避免把可恢复请求误判为会话失效。
      final latestToken = _currentAccessToken();
      refreshed =
          latestToken != null &&
          latestToken.isNotEmpty &&
          originalToken != null &&
          latestToken != originalToken;
    }
    if (!refreshed) {
      final sessionToken = _currentAccessToken();
      if (sessionToken == null || sessionToken.isEmpty) {
        _refreshRejected = true;
      }
      // 会话清理由会话通知器按刷新结果分级处理：服务端明确拒绝才清除；
      // 瞬时网络故障保留会话，这里不再无条件登出。
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 401,
        requestOptions: requestOptions,
        response: response,
      );
    }
    if (requestOptions.data is FormData) {
      // 重放已 finalize 的 FormData 会抛 StateError；上传请求只刷新令牌，
      // 由调用方按 401 提示重试。
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 401,
        requestOptions: requestOptions,
        response: response,
      );
    }
    return _retry(requestOptions);
  }

  Future<bool> _refreshOnce() {
    final existing = _refreshing;
    if (existing != null) {
      return existing;
    }

    final refreshSession = _refreshSession;
    if (refreshSession == null) {
      return Future.value(false);
    }

    final refreshing = refreshSession().whenComplete(() {
      _refreshing = null;
    });
    _refreshing = refreshing;
    return refreshing;
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) {
    final headers = Map<String, dynamic>.from(requestOptions.headers);
    final skipAuthorization =
        requestOptions.extra[skipAuthorizationKey] == true;
    final token = skipAuthorization ? null : _currentAccessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      headers.remove('Authorization');
    }

    final extra =
        Map<String, dynamic>.from(requestOptions.extra)
          ..[_retriedKey] = true
          ..remove(_requestTokenKey);

    return dio
        .request<dynamic>(
          requestOptions.path,
          data: requestOptions.data,
          queryParameters: requestOptions.queryParameters,
          cancelToken: requestOptions.cancelToken,
          onReceiveProgress: requestOptions.onReceiveProgress,
          onSendProgress: requestOptions.onSendProgress,
          options: Options(
            method: requestOptions.method,
            sendTimeout: requestOptions.sendTimeout,
            receiveTimeout: requestOptions.receiveTimeout,
            extra: extra,
            headers: headers,
            responseType: requestOptions.responseType,
            contentType: requestOptions.contentType,
            validateStatus: requestOptions.validateStatus,
            receiveDataWhenStatusError:
                requestOptions.receiveDataWhenStatusError,
            followRedirects: requestOptions.followRedirects,
            maxRedirects: requestOptions.maxRedirects,
            persistentConnection: requestOptions.persistentConnection,
            requestEncoder: requestOptions.requestEncoder,
            responseDecoder: requestOptions.responseDecoder,
            listFormat: requestOptions.listFormat,
          ),
        )
        .then((response) {
          if (response.statusCode == 401) {
            throw DioException.badResponse(
              statusCode: 401,
              requestOptions: response.requestOptions,
              response: response,
            );
          }
          return response;
        });
  }
}
