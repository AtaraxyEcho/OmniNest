import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';

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
}
