import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';

AppException mapBackendError(Map<String, Object?> payload) {
  final errorName = payload['errorName']?.toString();
  final code = payload['code']?.toString();
  return AppException(
    code: errorName ?? code ?? AppErrorCodes.unknown,
    message: payload['message']?.toString() ?? AppErrorCodes.unknown,
    details: {
      ...payload,
      if (errorName != null) 'errorName': errorName,
      if (code != null) 'code': code,
    },
  );
}
