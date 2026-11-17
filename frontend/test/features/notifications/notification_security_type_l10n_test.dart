import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('安全类通知类型映射为本地化文案而非原始码', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(notificationTypeLabel('SECURITY_THREAT', l10n), '安全威胁');
    expect(notificationTypeLabel('SECURITY_SCAN_FAILED', l10n), '安全扫描失败');
    expect(notificationTypeDescription('SECURITY_THREAT', l10n), isNotEmpty);
    expect(
      notificationTypeDescription('SECURITY_SCAN_FAILED', l10n),
      isNotEmpty,
    );

    // 英文侧同样映射，不再回落到原始码。
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      notificationTypeLabel('SECURITY_THREAT', en),
      isNot(equals('SECURITY_THREAT')),
    );
  });

  test('fallback 字典包含安全类通知类型', () {
    final codes =
        NotificationTypeConfig.fallbackTypes
            .map((type) => type.typeCode)
            .toSet();
    expect(
      codes,
      containsAll(<String>['SECURITY_THREAT', 'SECURITY_SCAN_FAILED']),
    );
  });
}
