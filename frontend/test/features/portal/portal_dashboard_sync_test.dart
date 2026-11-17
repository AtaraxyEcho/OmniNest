import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';

PortalDashboardActions _actions(
  Map<PortalDashboardSection, int> counters, {
  Duration sectionThrottle = const Duration(seconds: 4),
  Future<void> Function(PortalDashboardSection section)? onRefresh,
}) {
  return PortalDashboardActions(
    {
      for (final section in PortalDashboardSection.values)
        section:
            () =>
                onRefresh?.call(section) ??
                Future<void>.delayed(
                  const Duration(milliseconds: 20),
                  () => counters[section] = (counters[section] ?? 0) + 1,
                ),
    },
    sectionThrottle: sectionThrottle,
    hasCachedData: () => true,
  );
}

void main() {
  test('同一分区节流窗口内的重复刷新被跳过', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = _actions(counters);
    expect(await actions.retry(PortalDashboardSection.storage), isTrue);
    expect(await actions.retry(PortalDashboardSection.storage), isTrue);
    expect(counters[PortalDashboardSection.storage], 1);
  });

  test('force 刷新不受节流限制', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = _actions(counters);
    await actions.retry(PortalDashboardSection.storage);
    await actions.retry(PortalDashboardSection.storage, force: true);
    expect(counters[PortalDashboardSection.storage], 2);
  });

  test('在飞期间的重复请求合并为一次尾部刷新', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = _actions(counters);
    final first = actions.retry(PortalDashboardSection.video);
    final second = actions.retry(PortalDashboardSection.video);
    final third = actions.retry(PortalDashboardSection.video);
    await Future.wait([first, second, third]);
    // 尾部刷新由首个刷新收尾后异步触发，等待其完成再断言。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // 首次刷新 + 至多一次尾部刷新。
    expect(counters[PortalDashboardSection.video], 2);
  });

  test('分区刷新互不干扰，单个失败不影响其他分区', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = PortalDashboardActions({
      for (final section in PortalDashboardSection.values)
        section:
            section == PortalDashboardSection.storage
                ? () => Future<void>.error(StateError('boom'))
                : () => Future<void>.delayed(
                  const Duration(milliseconds: 10),
                  () => counters[section] = (counters[section] ?? 0) + 1,
                ),
    }, sectionThrottle: const Duration(seconds: 4));
    final result = await actions.refreshAll();
    expect(result.succeeded, isFalse);
    expect(result.failedSections, {PortalDashboardSection.storage});
    expect(counters[PortalDashboardSection.video], 1);
  });

  test('无缓存数据时进入页面刷新被跳过', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = PortalDashboardActions({
      PortalDashboardSection.storage:
          () async => counters[PortalDashboardSection.storage] = 1,
    }, hasCachedData: () => false);
    await actions.refreshOnEntry();
    expect(counters[PortalDashboardSection.storage], isNull);
  });

  test('有缓存数据时进入页面触发节流全量刷新', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = _actions(counters);
    await actions.refreshOnEntry();
    expect(counters[PortalDashboardSection.storage], 1);
    // 紧接着的聚焦刷新落在全量节流窗口内，被跳过。
    await actions.maybeRefreshAll();
    expect(counters[PortalDashboardSection.storage], 1);
  });

  test('脏范围按映射合并刷新，无关范围被忽略', () async {
    final counters = <PortalDashboardSection, int>{};
    final actions = _actions(
      counters,
      sectionThrottle: const Duration(milliseconds: 50),
    );
    final controller = StreamController<Set<RealtimeScope>>.broadcast();
    addTearDown(controller.close);
    final container = ProviderContainer(
      overrides: [
        realtimeDirtyScopesStreamProvider.overrideWithValue(controller.stream),
        portalDashboardActionsProvider.overrideWithValue(actions),
      ],
    );
    addTearDown(container.dispose);
    // Riverpod 3 默认 autoDispose：read 不构成监听，listen 维持 binder 存活。
    container.listen(portalDashboardRealtimeBinderProvider, (_, _) {});
    container.read(portalDashboardRealtimeBinderProvider);

    controller.add({RealtimeScope.files, RealtimeScope.tasks});
    controller.add({RealtimeScope.files, RealtimeScope.video});
    // 等待 800ms 合并窗口与刷新本身完成。
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    // 合并窗口内 files 出现两次只刷一次 storage；tasks 无映射被忽略。
    expect(counters[PortalDashboardSection.storage], 1);
    expect(counters[PortalDashboardSection.video], 1);
    expect(counters.containsKey(PortalDashboardSection.admin), isFalse);

    // 再次脏事件落在节流窗口外，可再次刷新。
    controller.add({RealtimeScope.files});
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(counters[PortalDashboardSection.storage], 2);
  });
}
