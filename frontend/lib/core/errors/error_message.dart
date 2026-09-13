import 'package:dio/dio.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';
import 'package:omninest/core/errors/error_codes.dart';

class UserFacingError {
  const UserFacingError({
    required this.title,
    required this.message,
    this.code,
  });

  final String title;
  final String message;
  final String? code;

  String get displayMessage =>
      code == null || code!.isEmpty ? message : '$message（$code）';
}

/// 将异常映射为用户可见错误。
///
/// 提供 [l10n] 时优先使用本地化文案；未提供时返回稳定错误码，
/// 展示层用 [UserFacingErrorL10n.localizeUserFacing] 再映射。
UserFacingError describeUserFacingError(
  Object error, {
  AppLocalizations? l10n,
}) {
  if (error is AppException) {
    return _describeAppException(error, l10n);
  }
  if (error is DioException) {
    return _describeDioException(error, l10n);
  }
  final raw = error.toString();
  return UserFacingError(
    title: l10n?.errorOperationFailed ?? AppErrorCodes.operationFailed,
    message:
        raw.isEmpty
            ? (l10n?.errorRequestFailedRetry ?? AppErrorCodes.unknown)
            : raw,
  );
}

UserFacingError _describeAppException(
  AppException error,
  AppLocalizations? l10n,
) {
  final message =
      l10n != null
          ? l10n.messageForErrorCode(error.code, fallback: error.message)
          : error.code;
  return UserFacingError(
    title: l10n?.errorOperationFailed ?? AppErrorCodes.operationFailed,
    message: message,
    code: error.code,
  );
}

UserFacingError _describeDioException(
  DioException error,
  AppLocalizations? l10n,
) {
  final backend = _backendError(error.response?.data, l10n);
  if (backend != null) {
    return backend;
  }
  final code = error.response?.statusCode?.toString();
  final title = l10n?.errorOperationFailed ?? AppErrorCodes.operationFailed;
  if (error.response?.statusCode == 503) {
    return UserFacingError(
      title: title,
      message: l10n?.errorServiceUnavailable ?? 'SERVICE_UNAVAILABLE',
      code: 'SERVICE_UNAVAILABLE',
    );
  }
  return switch (error.type) {
    DioExceptionType.connectionError => UserFacingError(
      title: title,
      message: l10n?.errorCannotConnect ?? AppErrorCodes.networkError,
      code: 'NETWORK_ERROR',
    ),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => UserFacingError(
      title: title,
      message: l10n?.errorNetworkTimeout ?? AppErrorCodes.networkTimeout,
      code: 'REQUEST_TIMEOUT',
    ),
    DioExceptionType.cancel => UserFacingError(
      title: title,
      message: l10n?.errorRequestCancelled ?? 'REQUEST_CANCELLED',
      code: 'REQUEST_CANCELLED',
    ),
    DioExceptionType.badCertificate => UserFacingError(
      title: title,
      message: l10n?.errorBadCertificate ?? 'BAD_CERTIFICATE',
      code: 'BAD_CERTIFICATE',
    ),
    DioExceptionType.badResponse => UserFacingError(
      title: title,
      message:
          code == null
              ? (l10n?.errorRequestFailedRetry ?? 'BAD_RESPONSE')
              : (l10n?.errorServerCode(code) ?? code),
      code: code,
    ),
    DioExceptionType.unknown => UserFacingError(
      title: title,
      message:
          error.message?.isNotEmpty == true
              ? error.message!
              : (l10n?.errorRequestFailedRetry ??
                  AppErrorCodes.operationFailed),
      code: code,
    ),
  };
}

UserFacingError? _backendError(Object? data, AppLocalizations? l10n) {
  final title = l10n?.errorOperationFailed ?? AppErrorCodes.operationFailed;
  if (data is Map<String, dynamic>) {
    final message = data['message']?.toString();
    final errorName = data['errorName']?.toString();
    if (message == null || message.isEmpty) {
      return null;
    }
    final resolved =
        (l10n != null && errorName != null && errorName.isNotEmpty)
            ? l10n.messageForErrorCode(errorName, fallback: message)
            : message;
    return UserFacingError(
      title: title,
      message: resolved,
      code: errorName ?? data['code']?.toString(),
    );
  }
  if (data is Map) {
    final message = data['message']?.toString();
    final errorName = data['errorName']?.toString();
    if (message == null || message.isEmpty) {
      return null;
    }
    final resolved =
        (l10n != null && errorName != null && errorName.isNotEmpty)
            ? l10n.messageForErrorCode(errorName, fallback: message)
            : message;
    return UserFacingError(
      title: title,
      message: resolved,
      code: errorName ?? data['code']?.toString(),
    );
  }
  return null;
}
