import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_client.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/security/offline_data_lifecycle_base.dart';
import 'package:omninest/core/security/offline_memory_cache.dart';

void main() {
  test('退出登录会清理当前用户离线数据和认证存储', () async {
    final sessionStore = _RecordingSessionStore();
    final lifecycle = _RecordingOfflineDataLifecycle();
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(lifecycle),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    OfflineMemoryCache.write(
      userId: 'user-1',
      cacheType: 'reader-book',
      businessId: 'item-1',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );

    await container.read(authSessionProvider.notifier).clearSession();

    expect(lifecycle.clearedUserId, 'user-1');
    expect(sessionStore.cleared, isTrue);
    expect(
      OfflineMemoryCache.read(
        userId: 'user-1',
        cacheType: 'reader-book',
        businessId: 'item-1',
      ),
      isNull,
    );
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('退出登录先吊销服务端会话再清理本地状态', () async {
    final authClient = _RecordingAuthClient();
    final sessionStore = _RecordingSessionStore(refreshToken: 'refresh-1');
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(),
        ),
        authClientProvider.overrideWithValue(authClient),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);

    await container.read(authSessionProvider.notifier).clearSession();

    expect(authClient.logoutCalls, 1);
    expect(authClient.lastRefreshToken, 'refresh-1');
    expect(sessionStore.cleared, isTrue);
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('服务端登出失败时仍会完成本地会话清理', () async {
    final authClient = _RecordingAuthClient(shouldFail: true);
    final sessionStore = _RecordingSessionStore();
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(),
        ),
        authClientProvider.overrideWithValue(authClient),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);

    await container.read(authSessionProvider.notifier).clearSession();

    expect(authClient.logoutCalls, 1);
    expect(sessionStore.cleared, isTrue);
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('级联并发退出登录只发起一次服务端吊销', () async {
    final authClient = _RecordingAuthClient(
      delay: const Duration(milliseconds: 50),
    );
    final sessionStore = _RecordingSessionStore(refreshToken: 'refresh-1');
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(),
        ),
        authClientProvider.overrideWithValue(authClient),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final notifier = container.read(authSessionProvider.notifier);

    await Future.wait(<Future<void>>[
      notifier.clearSession(),
      notifier.clearSession(),
      notifier.clearSession(),
    ]);

    expect(authClient.logoutCalls, 1);
    expect(sessionStore.cleared, isTrue);
  });

  test('离线数据清理失败时仍会清除认证会话', () async {
    final sessionStore = _RecordingSessionStore();
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(shouldFail: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);

    await container.read(authSessionProvider.notifier).clearSession();

    expect(sessionStore.cleared, isTrue);
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('清理步骤挂起时仍会完成登出并释放单飞标记', () async {
    AuthSessionNotifier.cleanupStepTimeout = const Duration(milliseconds: 40);
    addTearDown(() {
      AuthSessionNotifier.cleanupStepTimeout = const Duration(seconds: 5);
    });
    final sessionStore = _HangingSessionStore();
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _HangingOfflineDataLifecycle(),
        ),
        authClientProvider.overrideWithValue(_HangingAuthClient()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final notifier = container.read(authSessionProvider.notifier);

    await notifier.clearSession().timeout(const Duration(seconds: 2));

    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );

    // 单飞标记不得被悬挂清理永久占住，后续登出必须能再次执行。
    await notifier.clearSession().timeout(const Duration(seconds: 2));
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('会话状态先于清理落地，存储清理失败不影响未认证结果', () async {
    final sessionStore = _RecordingSessionStore(shouldFailClear: true);
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final notifier = container.read(authSessionProvider.notifier);
    final stateChanges = <bool>[];
    final sub = container.listen(authSessionProvider, (previous, next) {
      final value = next.asData?.value;
      if (value != null) {
        stateChanges.add(value.isAuthenticated);
      }
    });

    await notifier.clearSession();
    sub.close();

    expect(stateChanges, contains(false));
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('登出后在途会话刷新不得写回已登录', () async {
    final sessionStore = _RecordingSessionStore(refreshToken: 'refresh-1');
    final authClient = _SlowRefreshAuthClient(
      delay: const Duration(milliseconds: 80),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(),
        ),
        authClientProvider.overrideWithValue(authClient),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final notifier = container.read(authSessionProvider.notifier);

    final inFlightRefresh = notifier.refreshSession();
    await notifier.clearSession();
    final refreshed = await inFlightRefresh;

    expect(refreshed, isFalse);
    expect(authClient.refreshCalls, 1);
    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });

  test('清理期间资料重拉不得写回已登录', () async {
    final sessionStore = _RecordingSessionStore();
    final authClient = _SlowProfileAuthClient(
      delay: const Duration(milliseconds: 80),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
        authSessionStoreProvider.overrideWithValue(sessionStore),
        offlineDataLifecycleProvider.overrideWithValue(
          _RecordingOfflineDataLifecycle(),
        ),
        authClientProvider.overrideWithValue(authClient),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final notifier = container.read(authSessionProvider.notifier);

    final inFlightReload = notifier.reloadProfile();
    await notifier.clearSession();
    await inFlightReload;

    expect(
      container.read(authSessionProvider).requireValue.isAuthenticated,
      isFalse,
    );
  });
}

class _AuthenticatedSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(id: 'user-1', username: 'reader', role: 'MEMBER'),
    );
  }
}

class _RecordingSessionStore implements AuthSessionStore {
  _RecordingSessionStore({this.refreshToken, this.shouldFailClear = false});

  final String? refreshToken;
  final bool shouldFailClear;
  bool cleared = false;

  @override
  Future<void> clear() async {
    if (shouldFailClear) {
      throw const FormatException('测试存储清理失败');
    }
    cleared = true;
  }

  @override
  String? readAccessToken() => null;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveAccessToken(String? accessToken) async {}

  @override
  Future<void> saveSession(AuthTokenResponse session) async {}
}

class _RecordingAuthClient extends AuthClient {
  _RecordingAuthClient({this.shouldFail = false, this.delay}) : super(Dio());

  final bool shouldFail;
  final Duration? delay;
  int logoutCalls = 0;
  String? lastRefreshToken;

  @override
  Future<void> logout({String? refreshToken}) async {
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    logoutCalls += 1;
    lastRefreshToken = refreshToken;
    if (shouldFail) {
      throw const FormatException('测试登出失败');
    }
  }
}

class _RecordingOfflineDataLifecycle implements OfflineDataLifecycle {
  _RecordingOfflineDataLifecycle({this.shouldFail = false});

  final bool shouldFail;
  String? clearedUserId;

  @override
  Future<void> clearUser(String userId) async {
    clearedUserId = userId;
    OfflineMemoryCache.clearUser(userId);
    if (shouldFail) {
      throw const FormatException('测试清理失败');
    }
  }
}

/// 永不完成，用于验证清理步骤超时后登出仍能结束。
class _HangingSessionStore implements AuthSessionStore {
  @override
  Future<void> clear() => Completer<void>().future;

  @override
  String? readAccessToken() => null;

  @override
  Future<String?> readRefreshToken() => Completer<String?>().future;

  @override
  Future<void> saveAccessToken(String? accessToken) async {}

  @override
  Future<void> saveSession(AuthTokenResponse session) async {}
}

class _HangingOfflineDataLifecycle implements OfflineDataLifecycle {
  @override
  Future<void> clearUser(String userId) => Completer<void>().future;
}

class _HangingAuthClient extends AuthClient {
  _HangingAuthClient() : super(Dio());

  @override
  Future<void> logout({String? refreshToken}) => Completer<void>().future;
}

class _SlowRefreshAuthClient extends AuthClient {
  _SlowRefreshAuthClient({required this.delay}) : super(Dio());

  final Duration delay;
  int refreshCalls = 0;

  @override
  Future<AuthTokenResponse> refresh({String? refreshToken}) async {
    refreshCalls += 1;
    await Future<void>.delayed(delay);
    return AuthTokenResponse(
      tokenType: 'Bearer',
      accessToken: 'access-late',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshToken: 'refresh-late',
      user: UserProfile(id: 'user-1', username: 'reader', role: 'MEMBER'),
    );
  }
}

class _SlowProfileAuthClient extends AuthClient {
  _SlowProfileAuthClient({required this.delay}) : super(Dio());

  final Duration delay;

  @override
  Future<UserProfile> currentUser() async {
    await Future<void>.delayed(delay);
    return UserProfile(
      id: 'user-1',
      username: 'reader-renamed',
      role: 'MEMBER',
    );
  }
}
