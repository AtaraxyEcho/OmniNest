import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';
import 'package:omninest/core/errors/error_codes.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('resumable download failures localize by module prefix', () {
    for (final code in const [
      'FILE_DOWNLOAD_TICKET_INVALID',
      'PHOTO_FILE_RANGE_INVALID',
      'PHOTO_BATCH_ARCHIVE_TICKET_CHANGED',
      'READER_FILE_DOWNLOAD_INCOMPLETE',
      'READER_FILE_SIZE_MISMATCH',
      'READER_FILE_DIGEST_MISMATCH',
    ]) {
      final message = l10n.messageForErrorCode(code, fallback: '中文回退');
      expect(message, isNot('中文回退'));
      expect(message, isNot('Operation failed'));
    }
  });

  test('reader book download failures localize without falling back', () {
    expect(
      l10n.messageForErrorCode('READER_BOOK_DOWNLOAD_TIMEOUT', fallback: '超时'),
      l10n.errorBookDownloadTimeout,
    );
    expect(
      l10n.messageForErrorCode('READER_BOOK_DOWNLOAD_FAILED', fallback: '失败'),
      l10n.errorBookDownloadFailed,
    );
  });

  test('共享空间缺下载位有自己的文案，不回落到通用无权限', () {
    expect(
      l10n.messageForErrorCode(
        AppErrorCodes.downloadPermissionRequired,
        fallback: '回退',
      ),
      l10n.errorDownloadPermissionRequired,
    );
    expect(l10n.errorDownloadPermissionRequired, isNot(l10n.errorForbidden));
  });

  test('常见业务码有本地化文案，不回落到服务端中文', () {
    for (final code in const [
      'PARAM_ERROR',
      'RATE_LIMITED',
      'FILE_QUOTA_EXCEEDED',
      'FILE_SIZE_EXCEEDED',
      'FILE_SECURITY_REJECTED',
      'MEDIA_TRANSCODE_FAILED',
      'BACKDROP_MALWARE_DETECTED',
      'TWO_FACTOR_INVALID_CODE',
      'TWO_FACTOR_ALREADY_ENABLED',
    ]) {
      final message = l10n.messageForErrorCode(code, fallback: '服务端中文');
      expect(message, isNot('服务端中文'), reason: code);
      expect(message, isNot(l10n.errorOperationFailed), reason: code);
    }
  });

  test('未知码只在中文界面回落服务端文案，英文界面用通用失败文案', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final zh = lookupAppLocalizations(const Locale('zh'));

    expect(
      en.messageForErrorCode('SOME_UNMAPPED_CODE', fallback: '服务端中文'),
      en.errorOperationFailed,
    );
    expect(
      zh.messageForErrorCode('SOME_UNMAPPED_CODE', fallback: '服务端中文'),
      '服务端中文',
    );
  });
}
