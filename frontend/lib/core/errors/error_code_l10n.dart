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
      case AppErrorCodes.downloadPermissionRequired:
        return errorDownloadPermissionRequired;
      case AppErrorCodes.preferenceVersionConflict:
        return errorPreferenceVersionConflict;
      case 'VALIDATION_FAILED':
        return errorInvalidResponse;
      case 'MUSIC_LYRICS_LOAD_FAILED':
        return musicLyricsLoadFailed;
      case 'READER_BOOK_DOWNLOAD_TIMEOUT':
        return errorBookDownloadTimeout;
      case 'READER_BOOK_DOWNLOAD_FAILED':
        return errorBookDownloadFailed;
      // 常见业务码：登录、上传、任务、配置、媒体与壁纸的高频失败原因。
      case 'PARAM_ERROR':
        return errorParamError;
      case 'BAD_REQUEST':
        return errorBadRequest;
      case 'RATE_LIMITED':
        return errorRateLimited;
      case 'DEPENDENCY_UNAVAILABLE':
        return errorDependencyUnavailable;
      case 'REGISTRATION_DISABLED':
        return errorRegistrationDisabled;
      case 'INTERNAL_ERROR':
        return errorInternalError;
      case 'TASK_STATUS_ILLEGAL':
        return errorTaskStatusIllegal;
      case 'TASK_ALREADY_COMPLETED':
        return errorTaskAlreadyCompleted;
      case 'TASK_DEPENDENCY_NOT_READY':
        return errorTaskDependencyNotReady;
      case 'CONFIG_NOT_FOUND':
        return errorConfigNotFound;
      case 'CONFIG_VALUE_INVALID':
        return errorConfigValueInvalid;
      case 'FILE_UPLOAD_FAILED':
        return errorFileUploadFailed;
      case 'FILE_SIZE_EXCEEDED':
        return errorFileSizeExceeded;
      case 'FILE_QUOTA_EXCEEDED':
        return errorFileQuotaExceeded;
      case 'FILE_PATH_INVALID':
        return errorFilePathInvalid;
      case 'FILE_OBJECT_MISSING':
        return errorFileObjectMissing;
      case 'FILE_SECURITY_REJECTED':
        return errorFileSecurityRejected;
      case 'MEDIA_TRANSCODE_FAILED':
        return errorMediaTranscodeFailed;
      case 'MUSIC_RECOMMENDATION_UNAVAILABLE':
        return errorMusicRecommendationUnavailable;
      case 'MEDIA_FORMAT_UNSUPPORTED':
        return errorMediaFormatUnsupported;
      case 'READING_PROGRESS_INVALID':
        return errorReadingProgressInvalid;
      case 'CHAPTER_TEXT_UNAVAILABLE':
        return errorChapterTextUnavailable;
      case 'BACKDROP_UNSUPPORTED_FORMAT':
        return errorBackdropUnsupportedFormat;
      case 'BACKDROP_QUOTA_EXCEEDED':
        return errorBackdropQuotaExceeded;
      case 'BACKDROP_FILE_TOO_LARGE':
        return errorBackdropFileTooLarge;
      case 'BACKDROP_SCAN_UNAVAILABLE':
        return errorBackdropScanUnavailable;
      case 'BACKDROP_MALWARE_DETECTED':
        return errorBackdropMalwareDetected;
      case 'BACKDROP_SCAN_FAILED':
        return errorBackdropScanFailed;
      case 'TWO_FACTOR_INVALID_CODE':
        return errorTwoFactorInvalidCode;
      case 'TWO_FACTOR_NOT_CONFIGURED':
        return errorTwoFactorNotConfigured;
      case 'TWO_FACTOR_ALREADY_ENABLED':
        return errorTwoFactorAlreadyEnabled;
      default:
        final resumableMessage = _resumableFailureMessage(code);
        if (resumableMessage != null) {
          return resumableMessage;
        }
        // 服务端 message 只有中文一种语言：中文界面回退它比通用文案更具体，
        // 其它语言回退只会把中文漏进界面，宁可显示通用失败文案。
        final localizedFallback = fallback;
        return localeName.startsWith('zh') &&
                localizedFallback != null &&
                localizedFallback.isNotEmpty
            ? localizedFallback
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
