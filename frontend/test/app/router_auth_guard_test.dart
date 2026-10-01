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
        canAccessAdminConsole: true,
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
        canAccessAdminConsole: true,
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
        canAccessAdminConsole: true,
        location: '/login?redirect=%2Fadmin%2Fusers',
      ),
      '/admin/users',
    );
  });

  test('认证检查期间受保护路径停泊到引导页并保留目标', () {
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/portal',
      ),
      '/boot?redirect=%2Fportal',
    );
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/',
      ),
      '/boot?redirect=%2Fportal',
    );
  });

  test('认证检查期间公开路径与引导页正常放行', () {
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/login',
      ),
      isNull,
    );
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/s/tok-1',
      ),
      isNull,
    );
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/shared/photos/item/tok-1',
      ),
      isNull,
    );
    expect(
      authRedirectPath(
        isChecking: true,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/boot',
      ),
      isNull,
    );
  });

  test('检查结束后引导页按认证结果落位', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        canAccessAdminConsole: true,
        location: '/boot?redirect=%2Fadmin%2Fusers',
      ),
      '/admin/users',
    );
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        location: '/boot?redirect=%2Fportal',
      ),
      '/login?redirect=%2Fportal',
    );
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        canAccessAdminConsole: true,
        location: '/boot',
      ),
      '/portal',
    );
  });

  test('安装状态检查期间受保护路径同样停泊到引导页', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        isSetupChecking: true,
        location: '/portal',
      ),
      '/boot?redirect=%2Fportal',
    );
  });

  test('首次安装未完成时所有客户端入口统一跳转安装向导', () {
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        canAccessAdminConsole: true,
        setupRequired: true,
        location: '/login',
      ),
      '/setup',
    );
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: false,
        canAccessAdminConsole: true,
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
        canAccessAdminConsole: true,
        location: '/setup',
      ),
      '/login',
    );
    expect(
      authRedirectPath(
        isChecking: false,
        isAuthenticated: true,
        canAccessAdminConsole: true,
        location: '/setup',
      ),
      '/portal',
    );
  });

  // 管理台可达性（权限与手机形态）由 canAccessAdminConsoleProvider 统一求值，
  // 路由侧只按布尔决策；权限与形态的推导变体见 test/app/phone_form_factor_test.dart
  // 与 admin 模块既有 domain 测试。
  test('管理台入口不可达时已认证用户被重定向到门户', () {
    for (final location in ['/admin', '/admin/users', '/admin/config']) {
      expect(
        authRedirectPath(
          isChecking: false,
          isAuthenticated: true,
          canAccessAdminConsole: false,
          location: location,
        ),
        '/portal',
        reason: location,
      );
    }
  });

  test('管理台入口可达时管理页面放行', () {
    for (final location in ['/admin', '/admin/users', '/admin/config']) {
      expect(
        authRedirectPath(
          isChecking: false,
          isAuthenticated: true,
          canAccessAdminConsole: true,
          location: location,
        ),
        isNull,
        reason: location,
      );
    }
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
