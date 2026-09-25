import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';

/// 将稳定错误码映射为用户可见文案；未知码回退为服务端 message 或通用失败。
extension AppErrorCodeL10n on AppLocalizations {
  String messageForErrorCode(String code, {String? fallback}) {
    switch (code) {
      case AppErrorCodes.invalidResponse:
        return errorInvalidResponse;
      case AppErrorCodes.emptyResponse:
        return errorEmptyResponse;
      case AppErrorCodes.operationFailed:
        return errorOperationFailed;
      case AppErrorCodes.networkTimeout:
        return errorNetworkTimeout;
      case AppErrorCodes.networkError:
        return errorNetworkError;
      case AppErrorCodes.unknown:
        return errorUnknown;
      case AppErrorCodes.needPassword:
      case AppErrorCodes.sharePasswordRequired:
        return errorNeedPassword;
      case AppErrorCodes.passwordInvalid:
        return errorPasswordInvalid;
      case AppErrorCodes.oldPasswordInvalid:
        return errorOldPasswordInvalid;
      case AppErrorCodes.shareSessionInvalid:
        return errorShareSessionInvalid;
      case AppErrorCodes.unnamedFile:
        return errorUnnamedFile;
      case AppErrorCodes.unnamedResource:
        return errorUnnamedResource;
      case AppErrorCodes.uploadUrlMissing:
        return errorUploadUrlMissing;
      case AppErrorCodes.securityScanFailed:
        return errorSecurityScanFailed;
      case AppErrorCodes.other:
        return errorOtherCategory;
      case 'READER_WEB_PDF_TOO_LARGE':
        return errorWebPdfTooLarge;
      case 'READER_WEB_FILE_TOO_LARGE':
        return errorWebBookTooLarge;
      case 'FILE_NOT_FOUND':
        return errorFileNotFound;
      case 'CONFLICT':
        return errorConflict;
      case 'UNAUTHORIZED':
        return errorUnauthorized;
      case 'FORBIDDEN':
        return errorForbidden;
      case 'VALIDATION_FAILED':
        return errorInvalidResponse;
      default:
        return (fallback != null && fallback.isNotEmpty)
            ? fallback
            : errorOperationFailed;
    }
  }

  String messageForAppException(AppException error) {
    return messageForErrorCode(error.code, fallback: error.message);
  }
}
