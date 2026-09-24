import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';

void main() {
  test('显式配置优先：API 与 WS 均使用配置值', () {
    final env = AppEnvironment.resolve(
      configuredApiBaseUrl: 'https://example.com/api/v1',
      configuredWsBaseUrl: 'wss://example.com/custom-ws',
    );
    expect(env.apiBaseUrl, 'https://example.com/api/v1');
    expect(env.wsBaseUrl, 'wss://example.com/custom-ws');
  });

  test('仅配置 API 时 WS 从 API 同域推导（https 升 wss）', () {
    final env = AppEnvironment.resolve(
      configuredApiBaseUrl: 'https://example.com/api/v1',
    );
    expect(env.wsBaseUrl, 'wss://example.com/ws');
  });

  test('无配置无浏览器来源时回落本地开发地址（WS 由 API 推导）', () {
    final env = AppEnvironment.resolve();
    expect(env.apiBaseUrl, 'http://localhost:8080/api/v1');
    expect(env.wsBaseUrl, 'ws://localhost:8080/ws');
  });

  test('浏览器同源推导 API 与 WS', () {
    final env = AppEnvironment.resolve(
      browserOrigin: 'https://nest.example.com',
    );
    expect(env.apiBaseUrl, 'https://nest.example.com/api/v1');
    expect(env.wsBaseUrl, 'wss://nest.example.com/ws');
  });

  test('子路径部署下 API 与 WS 继承页面前缀', () {
    final env = AppEnvironment.resolve(
      browserOrigin: 'https://nas.example.com',
      pagePath: '/omninest/',
    );
    expect(env.basePrefix, '/omninest/');
    expect(env.apiBaseUrl, 'https://nas.example.com/omninest/api/v1');
    expect(env.wsBaseUrl, 'wss://nas.example.com/omninest/ws');
  });

  test('页面路径缺前导或尾斜杠时仍归一为前缀', () {
    final env = AppEnvironment.resolve(
      browserOrigin: 'https://nas.example.com',
      pagePath: 'omninest',
    );
    expect(env.basePrefix, '/omninest/');
    expect(env.apiBaseUrl, 'https://nas.example.com/omninest/api/v1');
  });

  test('显式配置子路径 API 时前缀由 API 地址反推，WS 与分享基址同前缀', () {
    final env = AppEnvironment.resolve(
      configuredApiBaseUrl: 'https://nas.example.com/omninest/api/v1',
    );
    expect(env.basePrefix, '/omninest/');
    expect(env.wsBaseUrl, 'wss://nas.example.com/omninest/ws');
    // 分享页挂在前端站点的子路径下，剥掉「前缀 + api/v1」而非整个路径。
    expect(env.effectiveWebBaseUrl, 'https://nas.example.com/omninest');
  });

  test('根部署与自定义 API 路径的分享基址行为不变', () {
    expect(
      AppEnvironment.resolve(
        configuredApiBaseUrl: 'https://api.example.com/api/v1',
      ).effectiveWebBaseUrl,
      'https://api.example.com',
    );
    expect(
      AppEnvironment.resolve(
        configuredApiBaseUrl: 'https://api.example.com/v1',
      ).effectiveWebBaseUrl,
      'https://api.example.com',
    );
  });
}
