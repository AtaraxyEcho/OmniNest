import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';

void main() {
  test('Admin 分区切换失效对应常驻缓存 provider', () async {
    final counts = <String, int>{};
    void bump(String key) {
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final container = ProviderContainer(
      overrides: [
        // 悬挂 Future 避免构造领域视图，仅统计重建次数。
        adminMonitoringProvider.overrideWith((ref) {
          bump('monitoring');
          return Completer<AdminMonitoringView>().future;
        }),
        adminRolesProvider.overrideWith((ref) {
          bump('roles');
          return Completer<AdminRoleManagementView>().future;
        }),
        adminConfigsProvider.overrideWith((ref) {
          bump('configs');
          return Completer<AdminConfigManagementView>().future;
        }),
        adminExternalStorageProvider.overrideWith((ref) {
          bump('externalStorage');
          return Completer<AdminExternalStorageView>().future;
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(adminMonitoringProvider);
    container.read(adminRolesProvider);
    container.read(adminConfigsProvider);
    container.read(adminExternalStorageProvider);
    expect(counts, {
      'monitoring': 1,
      'roles': 1,
      'configs': 1,
      'externalStorage': 1,
    });

    final refresher = container.read(adminSectionRefreshProvider);

    refresher.invalidate(AdminSection.monitoring);
    // 无监听 provider 惰性重建，重新读取触发。
    container.read(adminMonitoringProvider);
    expect(counts['monitoring'], 2);
    expect(counts['roles'], 1);

    refresher.invalidate(AdminSection.roles);
    container.read(adminRolesProvider);
    expect(counts['roles'], 2);

    refresher.invalidate(AdminSection.config);
    container.read(adminConfigsProvider);
    expect(counts['configs'], 2);

    refresher.invalidate(AdminSection.externalStorage);
    container.read(adminExternalStorageProvider);
    expect(counts['externalStorage'], 2);

    // autoDispose 分区为空操作，不影响任何常驻缓存。
    refresher.invalidate(AdminSection.tasks);
    container.read(adminMonitoringProvider);
    expect(counts['monitoring'], 2);
  });
}
