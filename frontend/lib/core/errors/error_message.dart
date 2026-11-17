import 'package:dio/dio.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/errors/user_facing_error_locale.dart';

class UserFacingError {
  const UserFacingError({
    required this.title,
    required this.message,
    this.code,
  });

  final String title;
  final String message;
  final String? code;

  String get displayMessage {
    if (code == null || code!.isEmpty || code == message) {
      return message;
    }
    // 稳定符号（ErrorCode 枚举名）只用于映射与日志，不展示给用户；
    // 仅保留旧数字码的括号后缀，便于排障。
    final numericCode = code!;
    if (int.tryParse(numericCode) == null) {
      return message;
    }
    return '$message（$numericCode）';
  }
}

/// 嵌入本地化模板时使用的失败原因短句。
///
/// 调用点普遍把它塞进 `l10n.xxxFailed(reason)` 这类模板里；没有 `l10n` 时
/// 这里会退回服务端原文，非中文用户看到的就不是本地化文案。
String errorReason(Object error, AppLocalizations l10n) =>
    describeUserFacingError(error, l10n: l10n).message;

/// 动作失败提示：既有动作文案 + 能映射出含义的原因。
///
/// 只拼「有稳定错误码」的原因（业务码或网络分类），未映射的意外异常保留原文案
/// 而不追加 `error.toString()`——那会把 Dart 内部类型、甚至异常里带的路径与
/// URL 直接抛到界面上，用户读不懂，也违反日志与展示的边界。
String failureToast(AppLocalizations l10n, String actionLabel, Object error) {
  final described = describeUserFacingError(error, l10n: l10n);
  final code = described.code;
  if (code == null || code.isEmpty) {
    return actionLabel;
  }
  return l10n.commonFailureWithReason(actionLabel, described.message);
}

/// 同 [describeUserFacingError]，未给 [l10n] 时按当前 UI 语言解析。
///
/// 供需要同时读取 `message` 与 `code` 的控制器使用：直接调用
/// [describeUserFacingError] 不传 `l10n` 会保留服务端中文原文。
UserFacingError localizedUserFacingError(
  Object error, {
  AppLocalizations? l10n,
}) => describeUserFacingError(
  error,
  l10n: l10n ?? UserFacingErrorLocale.resolve(),
);

/// 取可直接展示的错误文案。
///
/// 应用层（Riverpod Notifier、导入/扫描队列等）没有 `BuildContext`，把结果写进
/// `state.errorMessage` 后由界面直接展示：不给 [l10n] 时按当前 UI 语言解析，
/// 才能让英文界面看到英文；直接取 `describeUserFacingError(error).message`
/// 会保留中文服务端原文。有上下文的展示层可显式传入 `context.l10n`。
String userFacingErrorText(Object error, {AppLocalizations? l10n}) =>
    localizedUserFacingError(error, l10n: l10n).message;

/// 同 [userFacingErrorText]，但保留旧数字错误码的括号后缀。
///
/// 文件上传等长驻任务条目会长期展示这句话，排障时需要看到服务端下发的数字码；
/// 稳定符号码（ErrorCode 枚举名）仍不会出现在文案里。
String userFacingErrorDisplayText(Object error, {AppLocalizations? l10n}) =>
    localizedUserFacingError(error, l10n: l10n).displayMessage;

/// 将异常映射为用户可见错误。
///
/// 提供 [l10n] 时优先使用本地化文案；未提供时返回稳定错误码，
/// 展示层用 [UserFacingErrorL10n.localizeUserFacing] 再映射。控制器层请改用
/// [userFacingErrorText]，它按当前 UI 语言解析。
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
  // 无 l10n 时保留服务端文案，稳定错误码只放进 code 供展示层再映射。
  // 之前直接用 code 覆盖 message，导致未传 l10n 的页面只剩裸数字码。
  final message =
      l10n != null
          ? l10n.messageForErrorCode(error.code, fallback: error.message)
          : (error.message.isNotEmpty ? error.message : error.code);
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
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => UserFacingError(
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
