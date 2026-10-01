import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/data/admin_user_api.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';

class _MockAdminUserApi extends Mock implements AdminUserApi {}

void main() {
  const user = AdminUser(
    id: 'user-1',
    username: 'member-1',
    status: 'ACTIVE',
    role: 'MEMBER',
    roles: {'MEMBER'},
    permissions: {'file:read'},
    quotaBytes: 1024,
    usedBytes: 512,
  );

  late _MockAdminUserApi api;

  setUp(() {
    api = _MockAdminUserApi();
    when(
      () => api.listUsers(
        page: any(named: 'page'),
        size: any(named: 'size'),
        query: any(named: 'query'),
        role: any(named: 'role'),
        sort: any(named: 'sort'),
        dir: any(named: 'dir'),
      ),
    ).thenAnswer((_) async => (items: <AdminUser>[user], total: 1));
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer.test(
      overrides: [adminUserApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('读取 provider 即拉取第一页，无需显式触发加载', () async {
    final container = buildContainer();

    final state = await container.read(adminUserControllerProvider.future);

    verify(
      () => api.listUsers(
        page: 0,
        size: AdminUserState.defaultPageSize,
        query: '',
        role: 'ALL',
        sort: 'username',
        dir: 'asc',
      ),
    ).called(1);
    expect(state.users, isNotEmpty);
    expect(state.users.single.id, 'user-1');
    expect(state.page, 0);
    expect(state.totalElements, 1);
  });

  test('分区切换 invalidate 重建后重新拉取首页而非回到空表', () async {
    final container = buildContainer();
    await container.read(adminUserControllerProvider.future);

    container.invalidate(adminUserControllerProvider);
    final state = await container.read(adminUserControllerProvider.future);

    verify(
      () => api.listUsers(
        page: 0,
        size: AdminUserState.defaultPageSize,
        query: '',
        role: 'ALL',
        sort: 'username',
        dir: 'asc',
      ),
    ).called(2);
    expect(state.users.single.id, 'user-1');
  });

  group('批量选中', () {
    test('toggleSelection 增删选中 id 且不重建列表', () async {
      final container = buildContainer();
      final controller = container.read(adminUserControllerProvider.notifier);
      await container.read(adminUserControllerProvider.future);

      controller.toggleSelection('user-1');
      expect(container.read(adminUserControllerProvider).value!.selectedIds, {
        'user-1',
      });

      controller.toggleSelection('user-1');
      expect(
        container.read(adminUserControllerProvider).value!.selectedIds,
        isEmpty,
      );
      verify(
        () => api.listUsers(
          page: any(named: 'page'),
          size: any(named: 'size'),
          query: any(named: 'query'),
          role: any(named: 'role'),
          sort: any(named: 'sort'),
          dir: any(named: 'dir'),
        ),
      ).called(1);
    });

    test('selectAllVisible 跳过超级管理员并在已全选时清空', () async {
      final superAdmin = AdminUser(
        id: 'root',
        username: 'root',
        status: 'ACTIVE',
        role: 'SUPER_ADMIN',
        roles: {'SUPER_ADMIN'},
        permissions: {},
        quotaBytes: -1,
        usedBytes: 0,
      );
      when(
        () => api.listUsers(
          page: any(named: 'page'),
          size: any(named: 'size'),
          query: any(named: 'query'),
          role: any(named: 'role'),
          sort: any(named: 'sort'),
          dir: any(named: 'dir'),
        ),
      ).thenAnswer((_) async => (items: [user, superAdmin], total: 2));

      final container = buildContainer();
      final controller = container.read(adminUserControllerProvider.notifier);
      await container.read(adminUserControllerProvider.future);

      controller.selectAllVisible();
      expect(container.read(adminUserControllerProvider).value!.selectedIds, {
        'user-1',
      }, reason: '超级管理员不可进入批量选中集');

      controller.selectAllVisible();
      expect(
        container.read(adminUserControllerProvider).value!.selectedIds,
        isEmpty,
        reason: '已全选时再次全选应清空',
      );
    });

    test('当前页只剩超级管理员时全选只做清空，不产生假选中', () async {
      when(
        () => api.listUsers(
          page: any(named: 'page'),
          size: any(named: 'size'),
          query: any(named: 'query'),
          role: any(named: 'role'),
          sort: any(named: 'sort'),
          dir: any(named: 'dir'),
        ),
      ).thenAnswer(
        (_) async => (
          items: [
            AdminUser(
              id: 'root',
              username: 'root',
              status: 'ACTIVE',
              role: 'SUPER_ADMIN',
              roles: {'SUPER_ADMIN'},
              permissions: {},
              quotaBytes: -1,
              usedBytes: 0,
            ),
          ],
          total: 1,
        ),
      );

      final container = buildContainer();
      final controller = container.read(adminUserControllerProvider.notifier);
      await container.read(adminUserControllerProvider.future);

      controller.selectAllVisible();
      expect(
        container.read(adminUserControllerProvider).value!.selectedIds,
        isEmpty,
      );
    });

    test('refreshUsers 保留页码与选中集并修剪已离开当前页的用户', () async {
      final container = buildContainer();
      final controller = container.read(adminUserControllerProvider.notifier);
      await container.read(adminUserControllerProvider.future);
      controller.toggleSelection('user-1');
      controller.toggleSelection('user-gone');

      // 模拟另一端删除了 user-gone：刷新后该 id 应被修剪出选中集，
      // 页码与筛选保持不变，其余选中保留。
      when(
        () => api.listUsers(
          page: any(named: 'page'),
          size: any(named: 'size'),
          query: any(named: 'query'),
          role: any(named: 'role'),
          sort: any(named: 'sort'),
          dir: any(named: 'dir'),
        ),
      ).thenAnswer((_) async => (items: <AdminUser>[user], total: 1));

      await controller.refreshUsers();

      final state = container.read(adminUserControllerProvider).value!;
      expect(state.page, 0);
      expect(state.selectedIds, {'user-1'});
    });

    test('setSort 回第一页清空选择并携带排序参数；同序不重复请求', () async {
      final container = buildContainer();
      final controller = container.read(adminUserControllerProvider.notifier);
      await container.read(adminUserControllerProvider.future);
      controller.toggleSelection('user-1');

      controller.setSort('usedBytes', false);

      // setSort 触发的 _fetch 不经过 provider 重建，read(future) 等不到，
      // 冲刷微任务队列等待回写完成。
      await pumpEventQueue();
      final state = container.read(adminUserControllerProvider).value!;
      expect(state.sortField, 'usedBytes');
      expect(state.sortAscending, false);
      expect(state.selectedIds, isEmpty, reason: '排序变更后清空批量选择');
      verify(
        () => api.listUsers(
          page: 0,
          size: AdminUserState.defaultPageSize,
          query: '',
          role: 'ALL',
          sort: 'usedBytes',
          dir: 'desc',
        ),
      ).called(1);

      controller.setSort('usedBytes', false);
      verifyNever(
        () => api.listUsers(
          page: 0,
          size: AdminUserState.defaultPageSize,
          query: '',
          role: 'ALL',
          sort: 'usedBytes',
          dir: 'desc',
        ),
      );
    });
  });
}
