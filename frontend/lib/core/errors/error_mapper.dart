import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';

AppException mapBackendError(Map<String, Object?> payload) {
  return AppException(
    code: payload['code']?.toString() ?? AppErrorCodes.unknown,
    message: payload['message']?.toString() ?? AppErrorCodes.unknown,
    details: payload,
  );
}
