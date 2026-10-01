import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_sync_handler.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/data/admin_user_api.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';

class _MockAdminUserApi extends Mock implements AdminUserApi {}

/// 摘要直接返回静态值：本测试只关注用户表选中集，不触发真实请求。
class _FakeAdminConsoleController extends AdminConsoleController {
  @override
  Future<AdminConsoleSummary> build() => Future.value(
    AdminConsoleSummary(
      users: AdminUserStats(
        total: 2,
        active: 2,
        disabled: 0,
        roleCounts: const {},
      ),
      roles: const [],
      configs: AdminConfigStats(
        total: 0,
        hot: 0,
        nextTask: 0,
        restartRequired: 0,
      ),
      tasks: AdminTaskStats(
        total: 0,
        queued: 0,
        running: 0,
        completed: 0,
        failed: 0,
        cancelled: 0,
        dlq: 0,
      ),
      storage: AdminStorageStats(
        fileCount: 0,
        folderCount: 0,
        objectCount: 0,
        usedBytes: 0,
        externalAccountCount: 0,
      ),
      health: const [],
    ),
  );
}

class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(
        id: 'admin-1',
        username: 'admin-it',
        role: 'ADMIN',
        permissions: const {'system:user:read', 'system:config:read'},
      ),
    );
  }
}

/// 测试内构造 AdminSyncHandler 的载体 provider。
final _syncHandlerProvider = Provider<AdminSyncHandler>((ref) {
  return AdminSyncHandler(ref);
});

AdminUser _user(String id, String username, {Set<String>? roles}) {
  return AdminUser(
    id: id,
    username: username,
    status: 'ACTIVE',
    role: roles?.first ?? 'MEMBER',
    roles: roles ?? const {'MEMBER'},
    permissions: const {},
    quotaBytes: 1024 * 1024 * 1024,
    usedBytes: 1024,
  );
}

RealtimeInvalidation _adminEvent(String resourceType, int revision) {
  return RealtimeInvalidation(
    key: 'admin:$resourceType:$revision',
    scope: RealtimeScope.admin,
    resourceType: resourceType,
    revision: revision,
    createdAt: DateTime(2026, 10, 1),
  );
}

void main() {
  testWidgets('用户表勾选、表头全选与实时事件不清空选中集', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockAdminUserApi();
    var listCalls = 0;
    when(
      () => api.listUsers(
        page: any(named: 'page'),
        size: any(named: 'size'),
        query: any(named: 'query'),
        role: any(named: 'role'),
        sort: any(named: 'sort'),
        dir: any(named: 'dir'),
      ),
    ).thenAnswer((_) async {
      listCalls++;
      return (
        items: [
          _user('u1', 'alice'),
          _user('u2', 'bob'),
          _user('u3', 'root', roles: const {'SUPER_ADMIN'}),
        ],
        total: 3,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_AdminSessionNotifier.new),
          adminConsoleControllerProvider.overrideWith(
            _FakeAdminConsoleController.new,
          ),
          adminUserApiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const AdminDashboardPage(initialSectionSegment: 'users'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminDashboardPage)),
    );
    AdminUserState state() =>
        container.read(adminUserControllerProvider).value!;

    // 复选框顺序：表头全选 + 三行；第三行为超级管理员，禁用不可勾选。
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(4));
    expect(tester.widget<Checkbox>(checkboxes.at(3)).onChanged, isNull);

    // 行勾选 → 选中集更新、批量条出现。
    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();
    expect(state().selectedIds, {'u1'});
    expect(tester.widget<Checkbox>(checkboxes.at(1)).value, true);
    expect(find.text('已选择 1 个用户'), findsOneWidget);

    // 表头三态：部分选中（1/2 可选行）→ 点击补全 → 再点清空。
    expect(tester.widget<Checkbox>(checkboxes.at(0)).value, isNull);
    await tester.tap(checkboxes.at(0));
    await tester.pumpAndSettle();
    expect(state().selectedIds, {'u1', 'u2'}, reason: '超级管理员不进入全选集合');
    expect(tester.widget<Checkbox>(checkboxes.at(0)).value, true);
    expect(find.text('已选择 2 个用户'), findsOneWidget);
    await tester.tap(checkboxes.at(0));
    await tester.pumpAndSettle();
    expect(state().selectedIds, isEmpty);
    expect(find.text('已选择 1 个用户'), findsNothing);
    expect(find.text('已选择 2 个用户'), findsNothing);

    // 与用户表无关的管理事件（配置变更）：不重拉列表、不影响选中集。
    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();
    expect(state().selectedIds, {'u1'});
    final handler = container.read(_syncHandlerProvider);
    var refreshed = await handler.refresh([_adminEvent('config_entries', 1)]);
    await tester.pumpAndSettle();
    expect(refreshed, isTrue, reason: '控制台摘要已挂载，事件可被确认消费');
    expect(listCalls, 1, reason: '无关事件不得重拉用户列表');
    expect(state().selectedIds, {'u1'}, reason: '无关事件不得清空选中集');

    // 账户数据事件（auth_users）：原地重拉列表但保留页码与选中集。
    refreshed = await handler.refresh([_adminEvent('auth_users', 2)]);
    await tester.pumpAndSettle();
    expect(refreshed, isTrue);
    expect(listCalls, 2, reason: '账户事件应原地重拉用户列表');
    expect(state().selectedIds, {'u1'}, reason: '账户事件刷新后选中集保留');
    expect(state().page, 0);
    expect(find.text('已选择 1 个用户'), findsOneWidget);
  });
}
