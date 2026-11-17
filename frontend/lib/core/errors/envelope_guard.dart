import 'package:omninest/core/errors/app_exception.dart';

/// 校验后端 `ApiResponse` 信封，非 200 时抛出 [AppException]。
///
/// `ApiClient` 的 `validateStatus < 500` 会让 HTTP 4xx 以正常响应返回；
/// 只关心副作用的写接口必须显式调用本函数，否则业务失败会被当成成功。
void ensureEnvelopeSuccess(
  Map<String, dynamic>? body, {
  String fallbackMessage = '操作失败',
}) {
  if (body == null) {
    throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回结果');
  }
  final code = body['code'];
  if (code == 200) {
    return;
  }
  final errorName = body['errorName']?.toString();
  throw AppException(
    code: errorName ?? code?.toString() ?? 'INVALID_RESPONSE',
    message: body['message']?.toString() ?? fallbackMessage,
    details: {
      if (errorName != null) 'errorName': errorName,
      if (code != null) 'code': code.toString(),
    },
  );
}

/// 校验并返回信封中的 `data` 对象。
Map<String, dynamic> requireEnvelopeData(
  Map<String, dynamic>? body, {
  String fallbackMessage = '操作失败',
  String invalidMessage = '响应格式不正确',
}) {
  ensureEnvelopeSuccess(body, fallbackMessage: fallbackMessage);
  final data = body!['data'];
  if (data is Map<String, dynamic>) {
    return data;
  }
  throw AppException(code: 'INVALID_RESPONSE', message: invalidMessage);
}
