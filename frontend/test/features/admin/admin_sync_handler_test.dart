import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_sync_handler.dart';

final _handlerProvider = Provider<AdminSyncHandler>(AdminSyncHandler.new);

void main() {
  test('未进入管理模块时按已消费确认全作用域重置请求', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(_handlerProvider);

    final invalidation = RealtimeInvalidation(
      key: 'admin-reset',
      scope: RealtimeScope.admin,
      resourceType: '*',
      revision: 1,
      createdAt: DateTime.utc(2026, 7, 17),
    );

    expect(handler.appliesTo(invalidation), isTrue);
    // 从未挂载说明没有本地状态可刷：必须确认消费，否则分发器会永久重试。
    expect(await handler.refresh([invalidation]), isTrue);

    expect(container.exists(adminConsoleSummaryProvider), isFalse);
  });

  test('管理事件刷新已挂载的连接器 OAuth 应用缓存', () async {
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        adminConnectorOAuthAppsProvider.overrideWith((ref) async {
          builds += 1;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(adminConnectorOAuthAppsProvider.future);
    expect(builds, 1);

    final handler = container.read(_handlerProvider);
    final invalidation = RealtimeInvalidation(
      key: 'admin-oauth-refresh',
      scope: RealtimeScope.admin,
      resourceType: '*',
      revision: 2,
      createdAt: DateTime.utc(2026, 9, 20),
    );

    final consumed = await handler.refresh([invalidation]);

    expect(builds, 2);
    // 已挂载的附属缓存刷新成功：即使管理主模块未挂载也必须确认消费。
    expect(consumed, isTrue);
  });
}
