import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/application/notification_sync_handler.dart';

/// 捕获容器级 Ref，供直接构造同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

void main() {
  test('通知模块未激活时失效记录直接消费', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = NotificationSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      RealtimeInvalidation(
        key: 'notification-inactive',
        scope: RealtimeScope.notifications,
        resourceType: '*',
        revision: 1,
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ]);

    expect(consumed, isTrue);
    expect(container.exists(notificationControllerProvider), isFalse);
  });
}
