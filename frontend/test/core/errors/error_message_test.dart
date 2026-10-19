import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_message.dart';

void main() {
  test('formats app exception message with code', () {
    final message = describeUserFacingError(
      const AppException(code: 'FILE_QUOTA_EXCEEDED', message: '存储配额不足'),
    );

    expect(message.title, 'OPERATION_FAILED');
    // 未提供 l10n 时保留服务端文案；稳定错误码放在 code 供展示层再映射。
    expect(message.message, '存储配额不足');
    expect(message.code, 'FILE_QUOTA_EXCEEDED');
    expect(message.displayMessage, '存储配额不足');
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

  testWidgets('带本地化时未知连接失败不回显裸错误码', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final message = describeUserFacingError(
      DioException(
        requestOptions: RequestOptions(path: '/files'),
        type: DioExceptionType.unknown,
      ),
      l10n: l10n,
    );

    // 导入弹窗此前漏传 l10n，网络失败被兜底成裸码 OPERATION_FAILED 直接给用户看。
    expect(message.displayMessage, isNotEmpty);
    expect(message.displayMessage, isNot('OPERATION_FAILED'));
  });
}
