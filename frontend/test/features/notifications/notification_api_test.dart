import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/notifications/data/notification_api.dart';

void main() {
  test('删除通知使用当前用户资源路径', () async {
    final adapter = _NotificationAdapter();

    await NotificationApi(_apiClient(adapter)).deleteNotification('notice-1');

    expect(adapter.lastMethod, 'DELETE');
    expect(adapter.lastPath, '/notifications/notice-1');
  });

  test('清空通知遇到业务失败时不返回伪成功', () async {
    final adapter = _NotificationAdapter(
      statusCode: 403,
      responseBody: {'code': 403, 'message': '没有清理权限', 'data': null},
    );

    expect(
      NotificationApi(_apiClient(adapter)).clearAll,
      throwsA(isA<AppException>()),
    );
  });

  test('未读筛选仅在显式开启时携带 unreadOnly 参数', () async {
    final adapter = _NotificationAdapter(
      responseBody: {
        'code': 200,
        'message': 'success',
        'data': {'items': <Map<String, dynamic>>[], 'totalElements': 0},
      },
    );

    await NotificationApi(_apiClient(adapter)).list(unreadOnly: true);
    expect(adapter.lastQuery?['unreadOnly'], isTrue);

    await NotificationApi(_apiClient(adapter)).list();
    expect(adapter.lastQuery?.containsKey('unreadOnly'), isFalse);
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

class _NotificationAdapter implements HttpClientAdapter {
  _NotificationAdapter({
    this.statusCode = 200,
    this.responseBody = const {'code': 200, 'message': 'success', 'data': null},
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastQuery = options.queryParameters.cast<String, dynamic>();
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
