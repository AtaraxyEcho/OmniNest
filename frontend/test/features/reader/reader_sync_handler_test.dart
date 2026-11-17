import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_sync_handler.dart';
import 'package:omninest/features/reader/domain/reader_stats.dart';

/// 捕获容器级 Ref，供直接构造同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

void main() {
  test('阅读事件刷新已挂载的统计总览缓存', () async {
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        readerStatsOverviewProvider.overrideWith((ref) async {
          builds += 1;
          return const ReaderStatsOverview(
            dailyMinutes: [],
            completedCount: 0,
            inProgressCount: 0,
            totalItems: 0,
            inProgressItems: [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(readerStatsOverviewProvider.future);
    expect(builds, 1);

    final handler = ReaderSyncHandler(container.read(refHolderProvider));
    final consumed = await handler.refresh([
      RealtimeInvalidation(
        key: 'reader-overview-refresh',
        scope: RealtimeScope.reader,
        resourceType: '*',
        revision: 1,
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ]);

    expect(builds, 2);
    expect(consumed, isTrue);
  });

  test('阅读模块未激活时失效记录直接消费', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = ReaderSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      RealtimeInvalidation(
        key: 'reader-inactive',
        scope: RealtimeScope.reader,
        resourceType: '*',
        revision: 2,
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ]);

    expect(consumed, isTrue);
    expect(container.exists(readerCenterControllerProvider), isFalse);
  });
}
