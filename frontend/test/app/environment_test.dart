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
}
