import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_action.dart';

/// 通知动作链接映射回归：已知类型给出目标路由，未知类型不渲染链接。
void main() {
  AppLocalizations localizations() {
    return lookupAppLocalizations(const Locale('zh'));
  }

  NotificationDto dto(String type) {
    return NotificationDto(
      id: 'n-1',
      type: type,
      title: '标题',
      message: null,
      read: false,
      createdAt: DateTime(2026, 9, 29, 9),
      metadata: const <String, dynamic>{'taskId': 't-1'},
    );
  }

  test('任务与分享类通知路由到文件模块', () {
    final l10n = localizations();
    expect(notificationActionFor(dto('TASK_COMPLETED'), l10n)?.route, '/files');
    expect(notificationActionFor(dto('TASK_FAILED'), l10n)?.route, '/files');
    expect(notificationActionFor(dto('SHARE_ACCESSED'), l10n)?.route, '/files');
  });

  test('刮削完成路由到媒体库，安全类路由到安全分区', () {
    final l10n = localizations();
    expect(notificationActionFor(dto('MEDIA_SCRAPED'), l10n)?.route, '/video');
    expect(
      notificationActionFor(dto('NEW_DEVICE_LOGIN'), l10n)?.route,
      '/profile?section=security',
    );
    expect(
      notificationActionFor(dto('PASSWORD_CHANGED'), l10n)?.route,
      '/profile?section=security',
    );
  });

  test('未知与纯消息类型不提供动作链接', () {
    final l10n = localizations();
    expect(notificationActionFor(dto('SYSTEM_MESSAGE'), l10n), isNull);
    expect(notificationActionFor(dto('UNKNOWN_TYPE'), l10n), isNull);
  });

  test('metadata 解析自响应负载', () {
    final notification = NotificationDto.fromJson(const {
      'id': 'n-2',
      'type': 'TASK_COMPLETED',
      'title': 't',
      'read': false,
      'createdAt': '2026-09-29T09:00:00Z',
      'metadata': {'taskId': 'task-9'},
    });
    expect(notification.metadata['taskId'], 'task-9');
  });
}
