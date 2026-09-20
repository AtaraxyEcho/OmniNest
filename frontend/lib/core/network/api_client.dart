import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/auth/auth_session_store.dart';
import 'package:omninest/core/network/retry_interceptor.dart';
import 'package:omninest/core/log/dev_log.dart';

typedef AccessTokenReader = String? Function();
typedef SessionRefresher = Future<bool> Function();

class ApiClient {
  ApiClient(
    AppEnvironment environment, {
    AuthSessionStore? sessionStore,
    AccessTokenReader? readAccessToken,
    SessionRefresher? refreshSession,
    HttpClientAdapter? httpClientAdapter,
  }) : _sessionStore = sessionStore,
       _readAccessToken = readAccessToken,
       _refreshSession = refreshSession,
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
          final skipAuthorization = options.extra[skipAuthorizationKey] == true;
          if (kIsWeb && !skipAuthorization) {
            options.extra['withCredentials'] = true;
          }
          if (!skipAuthorization) {
            final token = _currentAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
              options.extra[_requestTokenKey] = token;
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (!_shouldRefresh(response)) {
            handler.next(response);
            return;
          }
          final isForbidden = response.statusCode == 403;

          try {
            final originalToken =
                response.requestOptions.extra[_requestTokenKey]?.toString();
            final currentToken = _currentAccessToken();
            var refreshed =
                currentToken != null &&
                        currentToken.isNotEmpty &&
                        originalToken != null &&
                        currentToken != originalToken
                    ? true
                    : await _refreshOnce();
            if (!refreshed) {
              // 刷新调用失败但令牌可能已被并发路径更新（如周期刷新恰好
              // 成功），复核一次签名避免把可恢复请求误判为会话失效。
              final latestToken = _currentAccessToken();
              refreshed =
                  latestToken != null &&
                  latestToken.isNotEmpty &&
                  originalToken != null &&
                  latestToken != originalToken;
            }

            if (!refreshed) {
              if (isForbidden) {
                // 刷新不可用时的 403 多为真实权限拒绝，不清除会话，
                // 原样上抛由业务层呈现无权限反馈。
                handler.reject(
                  DioException.badResponse(
                    statusCode: response.statusCode ?? 403,
                    requestOptions: response.requestOptions,
                    response: response,
                  ),
                );
                return;
              }
              // 会话清理由会话通知器按刷新结果分级处理：服务端明确拒绝
              // 才清除；瞬时网络故障保留会话，这里不再无条件登出。
              handler.reject(
                DioException.badResponse(
                  statusCode: response.statusCode ?? 401,
                  requestOptions: response.requestOptions,
                  response: response,
                ),
              );
              return;
            }

            try {
              final retryResponse = await _retry(response.requestOptions);
              handler.resolve(retryResponse);
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
          } catch (_) {
            // _refreshOnce() 或后续逻辑抛出异常时拒绝请求；
            // 403 路径不清会话，避免权限误判升级为登出。
            if (isForbidden) {
              handler.reject(
                DioException.badResponse(
                  statusCode: response.statusCode ?? 403,
                  requestOptions: response.requestOptions,
                  response: response,
                ),
              );
              return;
            }
            handler.reject(
              DioException.badResponse(
                statusCode: response.statusCode ?? 401,
                requestOptions: response.requestOptions,
                response: response,
              ),
            );
          }
        },
        onError: (error, handler) {
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
  static const skipAuthorizationKey = 'omninest.skipAuthorization';

  final Dio dio;
  final AuthSessionStore? _sessionStore;
  final AccessTokenReader? _readAccessToken;
  final SessionRefresher? _refreshSession;
  String? _manualAccessToken;
  Future<bool>? _refreshing;

  void setAccessToken(String? token) {
    _manualAccessToken = token;
    _sessionStore?.saveAccessToken(token);
  }

  String? currentAccessToken() {
    return _readAccessToken?.call() ??
        _sessionStore?.readAccessToken() ??
        _manualAccessToken;
  }

  String? _currentAccessToken() {
    return currentAccessToken();
  }

  bool _shouldRefresh(Response<dynamic> response) {
    // 401 表示令牌过期；403 可能是本地 JWT 缺少最新授权 claim（角色权限
    // 变更后服务端不重发令牌），两者都值得刷新会话后重试一次。
    final statusCode = response.statusCode;
    final isAuthChallenge = statusCode == 401 || statusCode == 403;
    if (!isAuthChallenge ||
        response.requestOptions.extra[skipAuthorizationKey] == true) {
      return false;
    }
    final path = response.requestOptions.path;
    if (path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh')) {
      return false;
    }
    return response.requestOptions.extra[_retriedKey] != true;
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
