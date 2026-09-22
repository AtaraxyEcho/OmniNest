import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_sync_handler.dart';

final _handlerProvider = Provider<AdminSyncHandler>(AdminSyncHandler.new);

void main() {
  test('未进入管理模块时不会因全作用域重置请求管理接口', () async {
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
    expect(await handler.refresh([invalidation]), isFalse);

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
    expect(consumed, isFalse);
  });
}
