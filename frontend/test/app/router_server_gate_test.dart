import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/router.dart';

void main() {
  test('未配置时任意受保护目标进入引导页并保留地址', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: false,
        isAuthenticated: false,
        location: '/portal',
      ),
      '/server-setup?redirect=%2Fportal',
    );
  });

  test('未配置时公开分享链接同样进入引导页并保留地址', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: false,
        isAuthenticated: false,
        location: '/s/abc123',
      ),
      '/server-setup?redirect=%2Fs%2Fabc123',
    );
  });

  test('未配置时停留在引导页不重复跳转', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: false,
        isAuthenticated: false,
        location: '/server-setup',
      ),
      isNull,
    );
  });

  test('登录页与根路径进入引导页不携带 redirect', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: false,
        isAuthenticated: false,
        location: '/login',
      ),
      '/server-setup',
    );
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: false,
        isAuthenticated: false,
        location: '/',
      ),
      '/server-setup',
    );
  });

  test('配置加载期间停泊引导页', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: true,
        isConfigured: true,
        isAuthenticated: false,
        location: '/portal',
      ),
      '/server-setup?redirect=%2Fportal',
    );
  });

  test('Web 端跳过服务器门控', () {
    expect(
      serverGateRedirectPath(
        isWeb: true,
        isConfigLoading: false,
        isConfigured: false,
        isAuthenticated: false,
        location: '/portal',
      ),
      isNull,
    );
  });

  test('已配置后访问引导页按认证状态离开', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: false,
        location: '/server-setup',
      ),
      '/login',
    );
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: true,
        location: '/server-setup',
      ),
      '/portal',
    );
  });

  test('已配置后访问带目标的引导页续跳原目标', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: false,
        location: '/server-setup?redirect=%2Fs%2Fabc123',
      ),
      '/login?redirect=%2Fs%2Fabc123',
    );
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: true,
        location: '/server-setup?redirect=%2Ffiles',
      ),
      '/files',
    );
  });

  test('已配置普通路径放行进入后续门控链', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: false,
        location: '/login',
      ),
      isNull,
    );
  });

  test('显式切换参数放行引导页（任意认证状态）', () {
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: true,
        location: '/server-setup?switch=1',
      ),
      isNull,
    );
    expect(
      serverGateRedirectPath(
        isWeb: false,
        isConfigLoading: false,
        isConfigured: true,
        isAuthenticated: false,
        location: '/server-setup?switch=1',
      ),
      isNull,
    );
  });
}
