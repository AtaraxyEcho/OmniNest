import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/admin/data/admin_console_api.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';

void main() {
  late AdminConsoleApi adminConsoleApi;

  setUp(() {
    adminConsoleApi = AdminConsoleApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
    );
  });

  test('parses successful admin console summary response', () {
    final summary = adminConsoleApi.parseSummaryResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'users': {
          'total': 3,
          'active': 2,
          'disabled': 1,
          'roleCounts': {'SUPER_ADMIN': 1, 'ADMIN': 1, 'MEMBER': 1, 'GUEST': 0},
        },
        'roles': [
          {
            'code': 'ADMIN',
            'name': '管理员',
            'description': '系统管理员角色',
            'builtIn': true,
            'enabled': true,
            'permissionCount': 2,
            'permissions': ['system:user:read', 'system:config:read'],
          },
        ],
        'configs': {'total': 2, 'hot': 1, 'nextTask': 0, 'restartRequired': 1},
        'tasks': {
          'total': 16,
          'queued': 3,
          'running': 1,
          'completed': 8,
          'failed': 1,
          'cancelled': 2,
          'dlq': 1,
        },
        'storage': {
          'fileCount': 12,
          'folderCount': 4,
          'objectCount': 10,
          'usedBytes': 4096,
          'externalAccountCount': 2,
        },
        'health': [
          {'name': '任务队列', 'status': 'WARN', 'detail': '1 个运行中任务'},
        ],
      },
    });

    expect(summary.users.total, 3);
    expect(summary.users.roleCount(AdminRoles.superAdmin), 1);
    expect(summary.roles.single.code, AdminRoles.admin);
    expect(summary.roles.single.permissionCount, 2);
    expect(summary.configs.restartRequired, 1);
    expect(summary.tasks.total, 16);
    expect(summary.tasks.failed, 1);
    expect(summary.storage.usedBytes, 4096);
    expect(summary.storage.externalAccountCount, 2);
    expect(summary.health.single.status, 'WARN');
  });

  test('throws app exception when admin console response is invalid', () {
    expect(
      () => adminConsoleApi.parseSummaryResponse({
        'code': 200,
        'message': 'success',
        'data': null,
      }),
      throwsA(isA<AppException>()),
    );
  });
}
