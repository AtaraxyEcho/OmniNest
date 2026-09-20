import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/core/auth/auth_client.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store.dart';
import 'package:omninest/core/network/retry_interceptor.dart';
import 'package:omninest/core/security/offline_data_lifecycle.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/core/log/dev_log.dart';

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return createAuthSessionStore();
});

final offlineDataLifecycleProvider = Provider<OfflineDataLifecycle>((ref) {
  return createOfflineDataLifecycle(database: ref.watch(localDatabaseProvider));
});

final offlineDataInitializationProvider = FutureProvider<void>((ref) {
  return initializeOfflineDataLifecycle();
});

final authClientProvider = Provider<AuthClient>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment == null) {
    throw StateError('服务器地址未配置');
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: environment.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  // 认证请求是恢复会话的关键路径，连接层故障时按幂等键安全重试一次。
  final retryInterceptor = RetryInterceptor(
    maxRetries: 1,
    baseDelay: const Duration(milliseconds: 800),
  );
  dio.interceptors.add(retryInterceptor);
  retryInterceptor.setDio(dio);
  return AuthClient(dio);
});

final authSessionProvider =
    AsyncNotifierProvider<AuthSessionNotifier, AuthSessionState>(
      AuthSessionNotifier.new,
    );

/// 会话刷新结果分级。
enum SessionRefreshGrade {
  /// 刷新成功。
  success,

  /// 服务端明确拒绝（4xx）：会话或凭据确定失效。
  invalid,

  /// 网络等瞬时故障：会话有效性未知，不得清除本地会话与凭据。
  transient,
}

/// 单次会话刷新的结果。
class SessionRefreshResult {
  const SessionRefreshResult.ok(AuthSessionState this.session)
    : grade = SessionRefreshGrade.success;
  const SessionRefreshResult.invalid()
    : session = null,
      grade = SessionRefreshGrade.invalid;
  const SessionRefreshResult.transient()
    : session = null,
      grade = SessionRefreshGrade.transient;

  final AuthSessionState? session;
  final SessionRefreshGrade grade;
}

class AuthSessionState {
  const AuthSessionState({this.user, this.expiresAt});

  const AuthSessionState.unauthenticated() : user = null, expiresAt = null;

  final UserProfile? user;
  final DateTime? expiresAt;

  bool get isAuthenticated => user != null;
}

class AuthSessionNotifier extends AsyncNotifier<AuthSessionState> {
  static const _refreshCheckInterval = Duration(seconds: 30);
  static const _refreshAhead = Duration(minutes: 2);

  /// 冷启动会话恢复的总超时：Cookie 刷新悬挂时按未登录处理，避免
  /// 启动门控永久停留在引导页。
  static const _restoreTimeout = Duration(seconds: 12);

  Timer? _refreshTimer;

  @override
  Future<AuthSessionState> build() async {
    ref.onDispose(() => _refreshTimer?.cancel());
    var restored = await _restoreWithRetry();
    if (restored.session != null) {
      _scheduleRefresh(restored.session!.expiresAt);
      return restored.session!;
    }
    return const AuthSessionState.unauthenticated();
  }

  /// 恢复期瞬时故障单次退避重试：启动阶段网络栈常未就绪，直接按
  /// 未登录处理会把可恢复的抖动升级为登录页。
  Future<SessionRefreshResult> _restoreWithRetry() async {
    try {
      final first = await _refreshWithStoredToken().timeout(_restoreTimeout);
      if (first.grade != SessionRefreshGrade.transient) {
        return first;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return await _refreshWithStoredToken().timeout(_restoreTimeout);
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('会话恢复超时或失败: ${error.runtimeType}');
      }
      return const SessionRefreshResult.transient();
    }
  }

  /// 密码登录：正常返回并建立会话；需要两步验证时返回挑战结果，不改变当前会话状态。
  Future<AuthLoginResult> signInWithCredentials({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(authClientProvider)
          .login(username: username, password: password);
      final session = result.token;
      if (session != null) {
        await _applySession(session);
      } else {
        state = const AsyncData(AuthSessionState.unauthenticated());
      }
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// 两步验证登录第二步：验证码或备份码换取并建立会话。
  Future<void> signInWithTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    await _applyRemoteSession(() {
      return ref
          .read(authClientProvider)
          .verifyTwoFactor(challengeToken: challengeToken, code: code);
    });
  }

  /// 注册引导完成：备份码确认保存后换取并建立会话。
  Future<void> completeTwoFactorEnrollment({
    required String finalizeToken,
  }) async {
    await _applyRemoteSession(() {
      return ref
          .read(authClientProvider)
          .completeTwoFactorEnrollment(finalizeToken: finalizeToken);
    });
  }

  Future<void> _applyRemoteSession(
    Future<AuthTokenResponse> Function() fetch,
  ) async {
    state = const AsyncLoading();
    try {
      await _applySession(await fetch());
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _applySession(AuthTokenResponse session) async {
    await _saveSession(session);
    final authState = _toState(session);
    _scheduleRefresh(authState.expiresAt);
    state = AsyncData(authState);
  }

  /// 刷新当前会话并按结果分级处理：成功续期；服务端明确拒绝才清除
  /// 会话；瞬时网络故障保留本地会话与凭据，避免抖动被放大为登出。
  Future<bool> refreshSession() async {
    final result = await _refreshWithStoredToken();
    final session = result.session;
    if (session != null) {
      state = AsyncData(session);
      _scheduleRefresh(session.expiresAt);
      return true;
    }
    if (result.grade == SessionRefreshGrade.invalid) {
      await clearSession();
      return false;
    }
    if (kDebugMode) {
      devLog('会话刷新瞬时失败，保留本地会话等待下个周期');
    }
    return false;
  }

  bool _clearingSession = false;

  Future<void> clearSession() async {
    // 登出会触发路由与 provider 级联调用，单飞防止重复请求吊销接口。
    if (_clearingSession) {
      return;
    }
    _clearingSession = true;
    try {
      await _clearSessionInternal();
    } finally {
      _clearingSession = false;
    }
  }

  Future<void> _clearSessionInternal() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // 先吊销服务端会话（Web 端同时清 HttpOnly Cookie），失败不阻断本地清理；
    // 仅在确实持有会话时请求，避免登出后的级联清理反复打接口触发限流。
    final store = ref.read(authSessionStoreProvider);
    final wasAuthenticated = state.asData?.value.isAuthenticated ?? false;
    final storedRefreshToken = await store.readRefreshToken();
    if (wasAuthenticated || (storedRefreshToken ?? '').isNotEmpty) {
      try {
        await ref
            .read(authClientProvider)
            .logout(refreshToken: storedRefreshToken);
      } catch (error) {
        if (kDebugMode) {
          devLog('服务端会话吊销失败: ${error.runtimeType}');
        }
      }
    }
    final userId = state.asData?.value.user?.id;
    if (userId != null) {
      try {
        await ref.read(offlineDataLifecycleProvider).clearUser(userId);
      } catch (error) {
        if (kDebugMode) {
          devLog('离线数据清理失败: ${error.runtimeType}');
        }
      }
    }
    await store.clear();
    state = const AsyncData(AuthSessionState.unauthenticated());
  }

  void _scheduleRefresh(DateTime? expiresAt) {
    _refreshTimer?.cancel();
    if (expiresAt == null) return;

    _refreshTimer = Timer.periodic(_refreshCheckInterval, (_) async {
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining > _refreshAhead) return;

      _refreshTimer?.cancel();
      final ok = await refreshSession();
      if (ok) return;
      // 明确失效时 refreshSession 内部已清会话并取消排程；
      // 瞬时故障保留会话，按原过期时间继续排程等待下个周期。
      final stillAuthenticated = state.asData?.value.isAuthenticated ?? false;
      if (stillAuthenticated) {
        _scheduleRefresh(expiresAt);
      }
    });
  }

  Future<SessionRefreshResult> _refreshWithStoredToken() async {
    final store = ref.read(authSessionStoreProvider);
    try {
      final refreshToken = await store.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        if (kIsWeb) {
          // Web 端内存中无 token 时（如页面刷新），尝试用 HttpOnly cookie 兜底
          final session = await ref
              .read(authClientProvider)
              .refresh(refreshToken: null);
          await _saveSession(session);
          return SessionRefreshResult.ok(_toState(session));
        }
        // 无凭据且非 Web：确定无会话，不视为故障。
        return const SessionRefreshResult.invalid();
      }
      final session = await _refreshOnReadyEnvironment(
        refreshToken: refreshToken,
      );
      await _saveSession(session);
      return SessionRefreshResult.ok(_toState(session));
    } on DioException catch (error) {
      return _gradeRefreshFailure(error);
    } catch (error) {
      if (kDebugMode) {
        devLog('会话刷新失败: ${error.runtimeType}');
      }
      return const SessionRefreshResult.transient();
    }
  }

  /// 按响应分级刷新失败：4xx 为服务端明确拒绝（凭据确定失效）；
  /// 连接层故障与 5xx 视为瞬时，不清除本地会话与 Cookie。
  SessionRefreshResult _gradeRefreshFailure(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      if (kDebugMode) {
        devLog('会话刷新被服务端拒绝: HTTP $statusCode');
      }
      return const SessionRefreshResult.invalid();
    }
    if (kDebugMode) {
      devLog('会话刷新网络故障: ${error.type}（保留本地会话与凭据）');
    }
    return const SessionRefreshResult.transient();
  }

  /// 持有令牌的刷新前先等服务器配置就绪：自定义配置仍在加载时环境
  /// 为空或为预置，贸然刷新会把回访用户误判为未登录并清掉会话。
  /// 配置存储读取失败按未配置继续，刷新失败自然落到未登录态。
  Future<AuthTokenResponse> _refreshOnReadyEnvironment({
    required String refreshToken,
  }) async {
    try {
      await ref.read(serverConfigProvider.future);
    } catch (_) {
      // 与 _refreshWithStoredToken 相同的容错口径。
    }
    return ref.read(authClientProvider).refresh(refreshToken: refreshToken);
  }

  Future<void> _saveSession(AuthTokenResponse session) {
    return ref.read(authSessionStoreProvider).saveSession(session);
  }

  AuthSessionState _toState(AuthTokenResponse session) {
    return AuthSessionState(user: session.user, expiresAt: session.expiresAt);
  }
}
