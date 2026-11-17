import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/setup/data/initial_setup_api.dart';

void main() {
  test('安装状态接口使用公开请求并解析状态', () async {
    final adapter = _SetupAdapter(
      responseBody: {
        'code': 200,
        'message': 'success',
        'data': {
          'setupRequired': true,
          'setupAvailable': true,
          'persistentStateEnabled': true,
        },
      },
    );

    final status = await InitialSetupApi(_apiClient(adapter)).status();

    expect(status.setupRequired, isTrue);
    expect(status.setupAvailable, isTrue);
    expect(status.persistentStateEnabled, isTrue);
    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/setup/status');
    expect(adapter.lastExtra[ApiClient.skipAuthorizationKey], isTrue);
  });

  test('创建超级管理员只通过安装令牌提交初始化凭据', () async {
    final adapter = _SetupAdapter();

    await InitialSetupApi(_apiClient(adapter)).createSuperAdmin(
      setupToken: '0123456789abcdef0123456789abcdef',
      username: 'root',
      displayName: '管理员',
      email: 'root@example.com',
      password: 'ChangeMe123!',
    );

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/setup/super-admin');
    expect(
      adapter.lastHeaders['X-Setup-Token'],
      '0123456789abcdef0123456789abcdef',
    );
    expect(adapter.lastHeaders.containsKey('Authorization'), isFalse);
    expect(adapter.lastData, {
      'username': 'root',
      'displayName': '管理员',
      'email': 'root@example.com',
      'password': 'ChangeMe123!',
      'instanceName': 'OmniNest',
      'defaultLocale': 'zh-CN',
      'defaultTimezone': 'Asia/Shanghai',
    });
  });

  test('安装接口业务失败时抛出统一异常', () async {
    final adapter = _SetupAdapter(
      statusCode: 403,
      responseBody: {'code': 403, 'message': '安装凭据无效', 'data': null},
    );

    expect(
      () => InitialSetupApi(_apiClient(adapter)).createSuperAdmin(
        setupToken: 'invalid',
        username: 'root',
        displayName: '',
        email: '',
        password: 'ChangeMe123!',
      ),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          '安装凭据无效',
        ),
      ),
    );
  });
}

ApiClient _apiClient(HttpClientAdapter adapter) {
  return ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
    httpClientAdapter: adapter,
  );
}

class _SetupAdapter implements HttpClientAdapter {
  _SetupAdapter({
    this.statusCode = 200,
    this.responseBody = const {'code': 200, 'message': 'success', 'data': null},
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  String? lastMethod;
  String? lastPath;
  Object? lastData;
  Map<String, dynamic> lastHeaders = const {};
  Map<String, dynamic> lastExtra = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastData = options.data;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    lastExtra = Map<String, dynamic>.from(options.extra);
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
