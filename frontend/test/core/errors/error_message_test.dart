import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_message.dart';

void main() {
  test('formats app exception message with code', () {
    final message = describeUserFacingError(
      const AppException(code: 'FILE_QUOTA_EXCEEDED', message: '存储配额不足'),
    );

    expect(message.title, 'OPERATION_FAILED');
    // 未提供 l10n 时写入稳定错误码，展示层用 localizeUserFacing 再翻译。
    expect(message.message, 'FILE_QUOTA_EXCEEDED');
    expect(message.code, 'FILE_QUOTA_EXCEEDED');
    expect(message.displayMessage, contains('FILE_QUOTA_EXCEEDED'));
  });

  test('formats dio response message from backend payload', () {
    final message = describeUserFacingError(
      DioException.badResponse(
        statusCode: 400,
        requestOptions: RequestOptions(path: '/files/123'),
        response: Response(
          requestOptions: RequestOptions(path: '/files/123'),
          statusCode: 400,
          data: {'code': 400, 'message': '文件不存在'},
        ),
      ),
    );

    expect(message.message, '文件不存在');
    expect(message.code, '400');
  });

  test('formats dio connection error as network guidance', () {
    final message = describeUserFacingError(
      DioException.connectionError(
        requestOptions: RequestOptions(path: '/files'),
        reason: 'SocketException: Failed host lookup',
      ),
    );

    // 未提供 l10n 时 message 为稳定错误码 NETWORK_ERROR。
    expect(message.message, 'NETWORK_ERROR');
    expect(message.code, 'NETWORK_ERROR');
  });

  test('formats dio transform timeout as request timeout', () {
    final message = describeUserFacingError(
      DioException(
        requestOptions: RequestOptions(path: '/files'),
        type: DioExceptionType.transformTimeout,
        message: 'transforming timeout',
      ),
    );

    // transformTimeout 与其它超时类型一致，message 为稳定错误码 NETWORK_TIMEOUT。
    expect(message.message, 'NETWORK_TIMEOUT');
    expect(message.code, 'REQUEST_TIMEOUT');
  });
}
