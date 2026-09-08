/// Admin 模块共享响应解析：拆解统一 ApiResponse 外壳并提取 data 字段。
library;

import 'package:omninest/core/errors/app_exception.dart';

/// 校验响应外壳业务码为 200 并返回完整外壳。
///
/// body 为空或业务码非 200 时抛出 [AppException]；业务码缺失时使用
/// [defaultErrorCode]，错误消息缺失时使用 [defaultMessage]。
Map<String, dynamic> parseAdminEnvelope(
  Map<String, dynamic>? body, {
  required String defaultErrorCode,
  required String defaultMessage,
}) {
  if (body == null) {
    throw AppException(code: 'EMPTY_RESPONSE', message: defaultMessage);
  }
  final code = body['code'];
  if (code != 200) {
    throw AppException(
      code: code?.toString() ?? defaultErrorCode,
      message: body['message']?.toString() ?? defaultMessage,
    );
  }
  return body;
}

/// 在 [parseAdminEnvelope] 基础上要求 data 为对象并返回。
Map<String, dynamic> parseAdminData(
  Map<String, dynamic>? body, {
  required String defaultErrorCode,
  required String defaultMessage,
  required String invalidDataMessage,
}) {
  final envelope = parseAdminEnvelope(
    body,
    defaultErrorCode: defaultErrorCode,
    defaultMessage: defaultMessage,
  );
  final data = envelope['data'];
  if (data is! Map<String, dynamic>) {
    throw AppException(code: 'INVALID_RESPONSE', message: invalidDataMessage);
  }
  return data;
}
