import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/domain/initial_setup_status.dart';

void main() {
  test('未认证访问受保护页面时跳转登录并保留目标地址', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        location: '/admin',
      ),
      '/login?redirect=%2Fadmin',
    );
  });

  test('已认证访问登录页时跳转首页', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/login',
      ),
      '/portal',
    );
  });

  test('已认证访问带 redirect 的登录页时跳转目标页面', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/login?redirect=%2Fadmin%2Fusers',
      ),
      '/admin/users',
    );
  });

  test('认证检查期间不触发跳转', () {
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        location: '/admin',
      ),
      isNull,
    );
  });

  test('安装状态检查期间不触发跳转', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        isSetupChecking: true,
        location: '/portal',
      ),
      isNull,
    );
  });

  test('首次安装未完成时所有客户端入口统一跳转安装向导', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        setupRequired: true,
        location: '/login',
      ),
      '/setup',
    );
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        setupRequired: true,
        location: '/setup',
      ),
      isNull,
    );
  });

  test('首次安装完成后不能再次进入安装向导', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        location: '/setup',
      ),
      '/login',
    );
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/setup',
      ),
      '/portal',
    );
  });

  test('普通用户访问管理页面时跳转到门户', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/admin/users',
        userRole: 'MEMBER',
      ),
      '/portal',
    );
  });

  test('持有 task:admin 的非管理员角色可进入管理端', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/admin/tasks',
        userRole: 'MEMBER',
        userPermissions: {'task:read', 'task:admin'},
      ),
      isNull,
    );
  });

  test('仅持有 task:read 的成员不可进入管理端', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/admin/tasks',
        userRole: 'MEMBER',
        userPermissions: {'task:read', 'media:write'},
      ),
      '/portal',
    );
  });

  test('管理员访问管理页面时允许通过', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/admin/users',
        userRole: 'ADMIN',
      ),
      isNull,
    );
  });

  test('超级管理员访问管理页面时允许通过', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/admin/config',
        userRole: 'SUPER_ADMIN',
      ),
      isNull,
    );
  });

  test('未指定角色的已认证用户访问管理页面时跳转到门户', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        location: '/admin',
        userRole: null,
      ),
      '/portal',
    );
  });

  test('认证状态刷新时保持同一个路由实例', () async {
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_MutableAuthSessionNotifier.new),
        initialSetupProvider.overrideWith(_CompletedSetupNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final router = container.read(appRouterProvider);

    final notifier =
        container.read(authSessionProvider.notifier)
            as _MutableAuthSessionNotifier;
    notifier.refreshProfile();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appRouterProvider), same(router));
  });

  test('Reader Shell 可以推入详情路由并保持有效位置', () async {
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_MutableAuthSessionNotifier.new),
        initialSetupProvider.overrideWith(_CompletedSetupNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final router = container.read(appRouterProvider);

    router.go('/reader');
    router.push('/reader/items/book-1');
    await Future<void>.delayed(Duration.zero);

    expect(
      router.routeInformationProvider.value.uri.path,
      '/reader/items/book-1',
    );
  });
}

class _CompletedSetupNotifier extends InitialSetupController {
  @override
  Future<InitialSetupStatus> build() async {
    return const InitialSetupStatus(
      setupRequired: false,
      setupAvailable: false,
    );
  }
}

class _MutableAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(id: 'user-1', username: 'reader', role: 'MEMBER'),
    );
  }

  void refreshProfile() {
    state = AsyncData(state.requireValue);
  }
}
