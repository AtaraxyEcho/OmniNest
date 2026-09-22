import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 契约：会话域 data provider 必须接入 sessionEpochProvider。
///
/// 仅依赖失效清单（invalidate）会让上一次的数据以「刷新中保留旧值」的形式
/// 被渲染，换号后闪现上一账号内容；接入世代后按依赖变化重建，旧值不可见。
/// 新增承载用户内容的常驻 provider 时须同步登记（同时登记 session_reset 清单）。
void main() {
  const epochWiredFiles = <String>[
    'lib/features/files/application/file_browser_controller.dart',
    'lib/features/music/application/music_controller.dart',
    'lib/features/music/application/music_providers.dart',
    'lib/features/music/application/music_platform_library_controller.dart',
    'lib/features/music/application/music_history_controller.dart',
    'lib/features/music/application/music_daily_recommendation_controller.dart',
    'lib/features/music/application/music_platform_qr_session_controller.dart',
    'lib/features/video/application/movie_controller.dart',
    'lib/features/photos/application/photo_controller.dart',
    'lib/features/photos/application/photo_center_providers.dart',
    'lib/features/reader/application/reader_controller.dart',
    'lib/features/admin/application/admin_console_controller.dart',
    'lib/features/admin/application/admin_operations_controller.dart',
    'lib/features/admin/application/admin_user_controller.dart',
    'lib/features/tasks/application/task_controller.dart',
    'lib/features/notifications/application/notification_controller.dart',
    'lib/features/portal/application/portal_paged_cards.dart',
    'lib/features/profile/application/profile_controller.dart',
  ];

  test('会话域 provider 均已接入 sessionEpochProvider', () {
    final missing = <String>[];
    for (final path in epochWiredFiles) {
      final source = File(path).readAsStringSync();
      if (!source.contains('sessionEpochProvider')) {
        missing.add(path);
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          '以下文件未接入会话世代，换号后会闪现上一账号数据：\n${missing.join('\n')}\n'
          '（part 文件在宿主库中接入；新增此类 provider 时同步本清单）',
    );
  });

  test('会话重置协调器在换号时递增世代', () {
    final source =
        File(
          'lib/app/session/session_reset_coordinator.dart',
        ).readAsStringSync();
    expect(source, contains('sessionEpochProvider.notifier'));
    expect(source, contains('bump()'));
  });
}
