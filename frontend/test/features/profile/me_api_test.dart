import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/profile/data/me_api.dart';

void main() {
  test('修改密码发送当前密码和新密码', () async {
    final adapter = _CapturingHttpClientAdapter();
    final api = MeApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.changePassword(
      oldPassword: 'current-password',
      newPassword: 'new-password',
    );

    expect(adapter.lastMethod, 'PUT');
    expect(adapter.lastPath, '/me/password');
    expect(adapter.lastData, {
      'oldPassword': 'current-password',
      'newPassword': 'new-password',
    });
  });

  test('关闭两步验证接受 Void 响应（data 为空不再报响应格式错误）', () async {
    final adapter = _CapturingHttpClientAdapter();
    final api = MeApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.twoFactorDisable(password: 'correct-password');

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/me/2fa/disable');
    expect(adapter.lastData, {'password': 'correct-password'});
  });
}

class _CapturingHttpClientAdapter implements HttpClientAdapter {
  String? lastMethod;
  String? lastPath;
  Object? lastData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastData = options.data;
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': null}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
