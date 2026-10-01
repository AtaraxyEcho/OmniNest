import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/data/admin_user_api.dart';

void main() {
  late AdminUserApi adminUserApi;

  setUp(() {
    adminUserApi = AdminUserApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
    );
  });

  test('parses successful admin user page response', () {
    final result = adminUserApi.parseUserPageResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'items': [
          {
            'id': '3c6f7f89-24ef-4c7c-b7d8-28c179217235',
            'username': 'root',
            'displayName': '超级管理员',
            'email': 'root@omninest.local',
            'role': 'SUPER_ADMIN',
            'roles': ['SUPER_ADMIN'],
            'permissions': ['system:user:manage'],
            'quotaBytes': 10737418240,
            'usedBytes': 1024,
          },
        ],
      },
    });

    expect(result.items, hasLength(1));
    expect(result.items.single.username, 'root');
    expect(result.items.single.role, 'SUPER_ADMIN');
    expect(result.items.single.roles, contains('SUPER_ADMIN'));
    expect(result.items.single.usedBytes, 1024);
    expect(result.total, 1);
  });

  test('throws app exception when admin user response is not success', () {
    expect(
      () => adminUserApi.parseUserPageResponse({
        'code': 403,
        'message': '无权限',
        'data': null,
      }),
      throwsA(isA<AppException>()),
    );
  });

  test('用户状态页计算与选择集语义正确', () {
    const state = AdminUserState(
      users: [],
      page: 2,
      pageSize: 10,
      totalElements: 25,
      selectedIds: {'a', 'b'},
    );
    expect(state.totalPages, 3);
    expect(state.hasSelection, isTrue);
    const empty = AdminUserState(users: []);
    expect(empty.totalPages, 0);
    expect(empty.hasSelection, isFalse);
  });
}
