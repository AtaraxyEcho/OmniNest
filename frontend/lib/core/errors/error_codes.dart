/// 稳定错误码：data 层只抛码，presentation 用 l10n 映射文案。
abstract final class AppErrorCodes {
  static const invalidResponse = 'INVALID_RESPONSE';
  static const emptyResponse = 'EMPTY_RESPONSE';
  static const operationFailed = 'OPERATION_FAILED';
  static const networkTimeout = 'NETWORK_TIMEOUT';
  static const networkError = 'NETWORK_ERROR';
  static const unknown = 'UNKNOWN';
  static const needPassword = 'NEED_PASSWORD';
  static const shareSessionInvalid = 'SHARE_SESSION_INVALID';
  static const unnamedFile = 'UNNAMED_FILE';
  static const unnamedResource = 'UNNAMED_RESOURCE';
  static const uploadUrlMissing = 'UPLOAD_URL_MISSING';
  static const securityScanFailed = 'SECURITY_SCAN_FAILED';
  static const passwordInvalid = 'PASSWORD_INVALID';
  static const oldPasswordInvalid = 'OLD_PASSWORD_INVALID';
  static const sharePasswordRequired = 'SHARE_PASSWORD_REQUIRED';
  static const other = 'OTHER';
}
