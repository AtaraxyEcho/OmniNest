import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';

void main() {
  group('NotificationTypeConfig', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 'abc-123',
        'typeCode': 'TASK_COMPLETED',
        'label': '任务完成',
        'description': '异步任务执行成功',
        'icon': 'check_circle_rounded',
        'color': '#34D399',
        'sortOrder': 1,
        'enabled': true,
      };

      final config = NotificationTypeConfig.fromJson(json);

      expect(config.typeCode, 'TASK_COMPLETED');
      expect(config.label, '任务完成');
      expect(config.description, '异步任务执行成功');
      expect(config.icon, 'check_circle_rounded');
      expect(config.color, '#34D399');
      expect(config.sortOrder, 1);
      expect(config.enabled, true);
    });

    test('fromJson handles missing fields with defaults', () {
      final config = NotificationTypeConfig.fromJson({});

      expect(config.typeCode, '');
      expect(config.label, '');
      expect(config.description, isNull);
      expect(config.icon, isNull);
      expect(config.color, isNull);
      expect(config.sortOrder, 0);
      expect(config.enabled, true);
    });

    test('fallbackTypes contains all supported default types', () {
      expect(NotificationTypeConfig.fallbackTypes, hasLength(11));
      expect(
        NotificationTypeConfig.fallbackTypes.map((t) => t.typeCode),
        containsAll([
          'TASK_COMPLETED',
          'TASK_FAILED',
          'SHARE_ACCESS',
          'SYSTEM_MESSAGE',
          'MEDIA_SCRAPED',
          'SHARE_ACCESSED',
          'QUOTA_WARNING',
          'NEW_DEVICE_LOGIN',
          'PASSWORD_CHANGED',
          'SECURITY_THREAT',
          'SECURITY_SCAN_FAILED',
        ]),
      );
    });
  });

  group('NotificationPreferences', () {
    test('fromJson parses all fields', () {
      final json = {
        'enabled': true,
        'types': {'TASK_COMPLETED': false, 'TASK_FAILED': true},
        'quietHours': {'enabled': true, 'start': '23:00', 'end': '07:00'},
        'sound': false,
        'showPreview': true,
      };

      final prefs = NotificationPreferences.fromJson(json);

      expect(prefs.enabled, true);
      expect(prefs.types['TASK_COMPLETED'], false);
      expect(prefs.types['TASK_FAILED'], true);
      expect(prefs.quietHours.enabled, true);
      expect(prefs.quietHours.start, '23:00');
      expect(prefs.quietHours.end, '07:00');
      expect(prefs.sound, false);
      expect(prefs.showPreview, true);
    });

    test('fromJson defaults to enabled when empty', () {
      final prefs = NotificationPreferences.fromJson({});

      expect(prefs.enabled, true);
      expect(prefs.types, isEmpty);
      expect(prefs.quietHours.enabled, false);
      expect(prefs.sound, true);
      expect(prefs.showPreview, true);
    });

    test('isTypeEnabled returns true for unconfigured types', () {
      final prefs = NotificationPreferences.fromJson({
        'types': {'TASK_COMPLETED': false},
      });

      expect(prefs.isTypeEnabled('TASK_COMPLETED'), false);
      expect(prefs.isTypeEnabled('TASK_FAILED'), true);
    });

    test('toJson round-trips correctly', () {
      const prefs = NotificationPreferences(
        enabled: false,
        types: {'TASK_COMPLETED': false},
        quietHours: QuietHours(enabled: true, start: '23:00', end: '07:00'),
        sound: false,
        showPreview: false,
      );

      final json = prefs.toJson();
      final restored = NotificationPreferences.fromJson(json);

      expect(restored.enabled, prefs.enabled);
      expect(restored.types, prefs.types);
      expect(restored.quietHours.enabled, prefs.quietHours.enabled);
      expect(restored.sound, prefs.sound);
      expect(restored.showPreview, prefs.showPreview);
    });
  });

  group('QuietHours', () {
    test('fromJson parses correctly', () {
      final json = {'enabled': true, 'start': '23:00', 'end': '07:00'};

      final quietHours = QuietHours.fromJson(json);

      expect(quietHours.enabled, true);
      expect(quietHours.start, '23:00');
      expect(quietHours.end, '07:00');
    });

    test('fromJson defaults when empty', () {
      final quietHours = QuietHours.fromJson({});

      expect(quietHours.enabled, false);
      expect(quietHours.start, '22:00');
      expect(quietHours.end, '08:00');
    });
  });
}
