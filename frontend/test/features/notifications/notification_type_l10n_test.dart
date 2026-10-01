import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

NotificationDto _dto(
  String type, {
  String? title,
  Map<String, dynamic> metadata = const <String, dynamic>{},
}) {
  return NotificationDto(
    id: 'n-1',
    type: type,
    title: title,
    message: null,
    read: false,
    createdAt: DateTime.utc(2026, 9, 29),
    metadata: metadata,
  );
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));

  group('synthesizedNotificationText', () {
    test('完成类通知带文件名时合成具名文案', () {
      final text = synthesizedNotificationText(
        _dto(
          'MEDIA_AUTO_IMPORT_COMPLETED',
          metadata: const {'fileName': 'holiday.mp4'},
        ),
        l10n,
      );
      expect(
        text,
        l10n.notificationMediaImportCompletedWithName('holiday.mp4'),
      );
    });

    test('失败类通知无文件名时合成通用文案', () {
      final text = synthesizedNotificationText(
        _dto('MEDIA_AUTO_IMPORT_FAILED'),
        l10n,
      );
      expect(text, l10n.notificationMediaImportFailed);
    });

    test('已有 title 的通知不参与合成', () {
      final text = synthesizedNotificationText(
        _dto('MEDIA_AUTO_IMPORT_COMPLETED', title: '照片扫描完成'),
        l10n,
      );
      expect(text, isNull);
    });

    test('不可合成的类型返回 null 交由调用方兜底', () {
      expect(synthesizedNotificationText(_dto('TASK_COMPLETED'), l10n), isNull);
    });

    test('新类型接入既有标签与图标映射', () {
      expect(
        notificationTypeLabel('MEDIA_AUTO_IMPORT_COMPLETED', l10n),
        l10n.notificationTypeMediaImportCompleted,
      );
      expect(
        notificationTypeDescription('MEDIA_AUTO_IMPORT_FAILED', l10n),
        l10n.notificationTypeMediaImportFailedDesc,
      );
      expect(
        notificationTypeIcon('MEDIA_AUTO_IMPORT_FAILED'),
        Icons.error_outline_rounded,
      );
    });
  });
}
