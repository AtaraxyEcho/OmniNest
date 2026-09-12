import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/auth/auth_client.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store.dart';
import 'package:omninest/core/security/offline_data_lifecycle.dart';
import 'package:omninest/core/storage/local_database_provider.dart';

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
  final environment = AppEnvironment.fromDefines();
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

  Timer? _refreshTimer;

  @override
  Future<AuthSessionState> build() async {
    ref.onDispose(() => _refreshTimer?.cancel());
    final restored = await _refreshWithStoredToken();
    if (restored != null) {
      _scheduleRefresh(restored.expiresAt);
    }
    return restored ?? const AuthSessionState.unauthenticated();
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

  Future<bool> refreshSession() async {
    final refreshed = await _refreshWithStoredToken();
    if (refreshed == null) {
      await clearSession();
      return false;
    }
    state = AsyncData(refreshed);
    _scheduleRefresh(refreshed.expiresAt);
    return true;
  }

  Future<void> clearSession() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final userId = state.asData?.value.user?.id;
    if (userId != null) {
      try {
        await ref.read(offlineDataLifecycleProvider).clearUser(userId);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('离线数据清理失败: ${error.runtimeType}');
        }
      }
    }
    await ref.read(authSessionStoreProvider).clear();
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
      if (!ok) await clearSession();
    });
  }

  Future<AuthSessionState?> _refreshWithStoredToken() async {
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
          return _toState(session);
        }
        return null;
      }
      final session = await ref
          .read(authClientProvider)
          .refresh(refreshToken: refreshToken);
      await _saveSession(session);
      return _toState(session);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(AuthTokenResponse session) {
    return ref.read(authSessionStoreProvider).saveSession(session);
  }

  AuthSessionState _toState(AuthTokenResponse session) {
    return AuthSessionState(user: session.user, expiresAt: session.expiresAt);
  }
}
