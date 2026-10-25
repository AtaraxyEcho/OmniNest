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
      case AppErrorCodes.versionUploadIncomplete:
        return filesVersionUploadIncomplete;
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
      case AppErrorCodes.forbidden:
        return errorForbidden;
      case 'VALIDATION_FAILED':
        return errorInvalidResponse;
      case 'MUSIC_LYRICS_LOAD_FAILED':
        return musicLyricsLoadFailed;
      case 'READER_BOOK_DOWNLOAD_TIMEOUT':
        return errorBookDownloadTimeout;
      case 'READER_BOOK_DOWNLOAD_FAILED':
        return errorBookDownloadFailed;
      default:
        final resumableMessage = _resumableFailureMessage(code);
        if (resumableMessage != null) {
          return resumableMessage;
        }
        return (fallback != null && fallback.isNotEmpty)
            ? fallback
            : errorOperationFailed;
    }
  }

  /// 断点续传错误码由各模块前缀加固定后缀组成，按后缀统一映射，
  /// 避免新增下载入口时遗漏本地化、在英文界面回退成中文 message。
  String? _resumableFailureMessage(String code) {
    for (final prefix in const [
      'FILE_DOWNLOAD_',
      'PHOTO_FILE_',
      'PHOTO_BATCH_ARCHIVE_',
      'READER_FILE_',
    ]) {
      if (!code.startsWith(prefix)) {
        continue;
      }
      switch (code.substring(prefix.length)) {
        case 'TICKET_INVALID':
          return errorDownloadTicketInvalid;
        case 'RANGE_INVALID':
          return errorDownloadRangeInvalid;
        case 'TICKET_CHANGED':
          return errorDownloadTicketChanged;
        case 'DOWNLOAD_INCOMPLETE':
          return errorDownloadIncomplete;
        case 'SIZE_MISMATCH':
          return errorDownloadSizeMismatch;
        case 'DIGEST_MISMATCH':
          return errorDownloadDigestMismatch;
      }
    }
    return null;
  }

  String messageForAppException(AppException error) {
    return messageForErrorCode(error.code, fallback: error.message);
  }
}
