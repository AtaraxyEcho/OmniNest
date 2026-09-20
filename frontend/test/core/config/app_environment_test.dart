import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';

void main() {
  test('无预置且无浏览器来源时返回 null（服务器未配置）', () {
    expect(AppEnvironment.fromDefinesOrNull(), isNull);
  });

  test('web origin derives same-origin HTTPS endpoints', () {
    final environment = AppEnvironment.resolve(
      browserOrigin: 'https://omni.example.com',
    );

    expect(environment.apiBaseUrl, 'https://omni.example.com/api/v1');
    expect(environment.wsBaseUrl, 'wss://omni.example.com/ws');
  });

  test('explicit endpoints override browser origin', () {
    final environment = AppEnvironment.resolve(
      configuredApiBaseUrl: 'https://api.example.com/api/v1',
      configuredWsBaseUrl: 'wss://realtime.example.com/ws',
      configuredWebBaseUrl: 'https://share.example.com',
      browserOrigin: 'https://omni.example.com',
    );

    expect(environment.apiBaseUrl, 'https://api.example.com/api/v1');
    expect(environment.wsBaseUrl, 'wss://realtime.example.com/ws');
    expect(environment.effectiveWebBaseUrl, 'https://share.example.com');
  });

  test('invalid browser origin falls back to native local endpoints', () {
    final environment = AppEnvironment.resolve(browserOrigin: 'file:///app');

    expect(environment.apiBaseUrl, 'http://localhost:8080/api/v1');
    expect(environment.wsBaseUrl, 'ws://localhost:8080/ws');
  });
}
