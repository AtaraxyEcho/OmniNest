import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/core/auth/auth_client.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store.dart';
import 'package:omninest/core/errors/app_exception.dart';
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

/// 用户资料实时事件的目标标识（后端头像/资料变更按 PREFERENCES 作用域
/// 发出，resourceId 固定为该值）。
const userProfileSyncTarget = 'USER_PROFILE';

class AuthSessionNotifier extends AsyncNotifier<AuthSessionState> {
  static const _refreshCheckInterval = Duration(seconds: 30);
  static const _refreshAhead = Duration(minutes: 2);

  /// 冷启动会话恢复的总超时：Cookie 刷新悬挂时按未登录处理，避免
  /// 启动门控永久停留在引导页。
  static const _restoreTimeout = Duration(seconds: 12);

  /// 登出清理单步超时。存储读写、离线数据清理或吊销接口悬挂时不得
  /// 拖死退出流程，也不得让单飞标记永久占住后续登出。
  @visibleForTesting
  static Duration cleanupStepTimeout = const Duration(seconds: 5);

  Timer? _refreshTimer;

  /// 登出意图标记：置位后禁止在途刷新、资料重拉和存储写入把状态写回
  /// 已登录。clearSession 先落地未认证再清理，窗口变长，必须挡住竞态。
  bool _rejectSessionWrites = false;

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

  /// 恢复期瞬时故障立即单次重试：启动阶段网络栈常未就绪，直接按
  /// 未登录处理会把可恢复的抖动升级为登录页。不引入退避延迟，
  /// 避免在测试的 fake async 环境留下未触发的 Timer。
  Future<SessionRefreshResult> _restoreWithRetry() async {
    try {
      final first = await _refreshWithStoredToken();
      if (first.grade != SessionRefreshGrade.transient) {
        return first;
      }
      return await _refreshWithStoredToken();
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('会话恢复超时或失败: ${error.runtimeType}');
      }
      return const SessionRefreshResult.transient();
    }
  }

  /// 其他设备变更资料（头像/显示名）后经 PREFERENCES 实时事件重拉并
  /// 就地更新会话资料；令牌与过期时间保持不变，瞬时失败静默保留旧值。
  Future<void> reloadProfile() async {
    // 读 value 而不是 asData：重载过渡期状态是带旧值的 AsyncLoading，asData 会变 null，
    // 就地刷新会静默跳过，会话资料停在旧值上。
    final current = state.value;
    if (current == null || current.user == null) {
      return;
    }
    try {
      // authClientProvider 是刻意不带拦截器的裸客户端（登录/刷新不能被会话
      // 拦截器改写），因此这里必须显式附带当前访问令牌。
      final token = ref.read(authSessionStoreProvider).readAccessToken();
      final profile = await ref
          .read(authClientProvider)
          .currentUser(accessToken: token);
      if (!ref.mounted || _rejectSessionWrites) {
        return;
      }
      state = AsyncData(
        AuthSessionState(user: profile, expiresAt: current.expiresAt),
      );
    } on Exception {
      return;
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
    // 登录建立新会话：放行后续写入，并撤销可能仍在途的登出拒绝。
    _rejectSessionWrites = false;
    await _saveSession(session);
    final authState = _toState(session);
    _scheduleRefresh(authState.expiresAt);
    state = AsyncData(authState);
  }

  /// 刷新当前会话并按结果分级处理：成功续期；服务端明确拒绝才清除
  /// 会话；瞬时网络故障保留本地会话与凭据，避免抖动被放大为登出。
  Future<bool> refreshSession() async {
    final result = await _refreshWithStoredToken();
    if (_rejectSessionWrites) {
      return false;
    }
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
    // 先拒绝在途写入并落地未认证：后续吊销与本地清理不得阻塞退出登录的
    // 界面切换，也不得被并发刷新写回已登录。
    _rejectSessionWrites = true;
    // 读 .value 而不是 asData：重载过渡期状态是带前值的 AsyncLoading，asData 为 null
    // 会让 userId 取不到，离线库与密钥的清理被整段跳过——登出看似成功但数据还在设备上。
    final wasAuthenticated = state.value?.isAuthenticated ?? false;
    final userId = state.value?.user?.id;
    final store = ref.read(authSessionStoreProvider);
    final accessToken = store.readAccessToken();
    state = const AsyncData(AuthSessionState.unauthenticated());

    String? storedRefreshToken;
    try {
      storedRefreshToken = await store.readRefreshToken().timeout(
        cleanupStepTimeout,
      );
    } catch (error) {
      if (kDebugMode) {
        devLog('读取刷新令牌失败: ${error.runtimeType}');
      }
    }
    // 吊销服务端会话（Web 端同时清 HttpOnly Cookie），失败不阻断本地清理；
    // 仅在确实持有会话时请求，避免登出后的级联清理反复打接口触发限流。
    if (wasAuthenticated || (storedRefreshToken ?? '').isNotEmpty) {
      try {
        await ref
            .read(authClientProvider)
            .logout(refreshToken: storedRefreshToken, accessToken: accessToken)
            .timeout(cleanupStepTimeout);
      } catch (error) {
        if (kDebugMode) {
          devLog('服务端会话吊销失败: ${error.runtimeType}');
        }
      }
    }
    if (userId != null) {
      try {
        await ref
            .read(offlineDataLifecycleProvider)
            .clearUser(userId)
            .timeout(cleanupStepTimeout);
      } catch (error) {
        if (kDebugMode) {
          devLog('离线数据清理失败: ${error.runtimeType}');
        }
      }
    }
    try {
      await store.clear().timeout(cleanupStepTimeout);
    } catch (error) {
      if (kDebugMode) {
        devLog('认证存储清理失败: ${error.runtimeType}');
      }
    }
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
      final stillAuthenticated = state.value?.isAuthenticated ?? false;
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
          // Web 端内存中无 token 时（如页面刷新），尝试用 HttpOnly cookie
          // 兜底。超时只包网络调用本身：存储读取在测试的 fake async 环境
          // 可能永不返回，包整体会留下悬挂 Timer。
          final session = await ref
              .read(authClientProvider)
              .refresh(refreshToken: null)
              .timeout(_restoreTimeout);
          await _saveSession(session);
          return SessionRefreshResult.ok(_toState(session));
        }
        // 无凭据且非 Web：确定无会话，不视为故障。
        return const SessionRefreshResult.invalid();
      }
      final session = await _refreshOnReadyEnvironment(
        refreshToken: refreshToken,
      ).timeout(_restoreTimeout);
      await _saveSession(session);
      return SessionRefreshResult.ok(_toState(session));
    } on AppException catch (error) {
      return _gradeApiRefreshFailure(error);
    } on DioException catch (error) {
      return _gradeRefreshFailure(error);
    } catch (error) {
      if (kDebugMode) {
        devLog('会话刷新失败: ${error.runtimeType}');
      }
      return const SessionRefreshResult.transient();
    }
  }

  /// 按服务端业务码分级刷新失败。
  ///
  /// 只有 401/403 表示凭据确实不可用。刷新接口另有每分钟限流（429）与超时（408），
  /// 把这些一并当作凭据失效会直接清会话并清空离线数据库与加密缓存——用户只是网络抖动
  /// 或多组件并发刷新撞到限流，却被踢出登录并丢掉本地内容。
  SessionRefreshResult _gradeApiRefreshFailure(AppException error) {
    final errorCode = int.tryParse(error.code);
    final errorName = error.details['errorName']?.toString();
    final credentialRejected =
        errorCode == 401 ||
        errorCode == 403 ||
        errorName == 'UNAUTHORIZED' ||
        errorName == 'FORBIDDEN';
    if (credentialRejected) {
      if (kDebugMode) {
        devLog('会话刷新被服务端拒绝: ${error.code}');
      }
      return const SessionRefreshResult.invalid();
    }
    if (kDebugMode) {
      devLog('会话刷新失败但不影响凭据: ${error.code}（保留本地会话）');
    }
    return const SessionRefreshResult.transient();
  }

  /// 按响应分级刷新失败：仅 401/403 为服务端明确拒绝（凭据确定失效）；
  /// 连接层故障、408/429 与 5xx 视为瞬时，不清除本地会话与 Cookie。
  SessionRefreshResult _gradeRefreshFailure(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
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
    if (_rejectSessionWrites) {
      return Future<void>.value();
    }
    return ref.read(authSessionStoreProvider).saveSession(session);
  }

  AuthSessionState _toState(AuthTokenResponse session) {
    return AuthSessionState(user: session.user, expiresAt: session.expiresAt);
  }
}
