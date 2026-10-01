import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';

void main() {
  late AdminOperationsApi api;

  setUp(() {
    api = AdminOperationsApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
    );
  });

  test('parses role management response', () {
    final view = api.parseRoleManagementResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'roles': [
          {
            'code': 'ADMIN',
            'name': '管理员',
            'description': '系统管理员',
            'builtIn': true,
            'enabled': true,
            'permissions': ['system:user:read'],
          },
        ],
        'permissions': [
          {
            'code': 'system:user:read',
            'name': '读取用户',
            'module': 'system',
            'description': '允许读取用户',
            'enabled': true,
          },
        ],
      },
    });

    expect(view.roles.single.code, 'ADMIN');
    expect(view.permissions.single.module, 'system');
  });

  test('parses admin task response', () {
    final tasks = api.parseTaskResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'items': [
          {
            'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'taskType': 'FILE_INDEX',
            'status': 'FAILED',
            'progress': 30,
            'routingKey': 'omninest.file.index',
            'errorSummary': '索引失败',
            'retryCount': 2,
            'createdAt': '2026-05-20T09:00:00Z',
            'updatedAt': '2026-05-20T09:10:00Z',
          },
        ],
      },
    });

    expect(tasks.items.single.status, 'FAILED');
    expect(tasks.items.single.retryCount, 2);
  });

  test('parses audit log payload and tolerates invalid payload', () {
    final view = api.parseLogResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'items': [
          {
            'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
            'actorUserId': 'user-1',
            'action': 'ADMIN_CONFIG_UPDATE',
            'resourceType': 'config',
            'ipAddress': '127.0.0.1',
            'createdAt': '2026-09-28T09:00:00Z',
            'payload': {
              'oldValue': 'false',
              'newValue': 'true',
              'reason': '启用功能',
              'nested': {'depth': 1},
              'empty': null,
            },
          },
          {
            'id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
            'action': 'LOGIN',
            'resourceType': 'auth_users',
            'ipAddress': '127.0.0.1',
            'createdAt': '2026-09-28T09:05:00Z',
            'payload': 'not-a-map',
          },
        ],
      },
    });

    final first = view.items.first;
    expect(first.payload['oldValue'], 'false');
    expect(first.payload['newValue'], 'true');
    expect(first.payload['nested'], isA<Map<String, dynamic>>());
    expect(first.payload, isNot(contains('empty')));
    expect(view.items.last.payload, isEmpty);
  });

  test('parses controlled config metadata without a sensitive value', () {
    final view = api.parseConfigResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'items': [
          {
            'key': 'media.metadata-provider.tmdb.api-key',
            'value': null,
            'valueType': 'STRING',
            'category': 'media',
            'refreshScope': 'HOT',
            'updatedAt': '2026-08-14T08:00:00Z',
            'description': 'TMDB v3 API Key',
            'surface': 'INTEGRATION',
            'displayCode': 'config.integration.tmdb.apiKey',
            'editable': true,
            'sensitiveConfigured': true,
            'allowedValues': <String>[],
          },
        ],
      },
    });

    final item = view.items.single;
    expect(item.value, isEmpty);
    expect(item.surface, 'INTEGRATION');
    expect(item.sensitiveConfigured, isTrue);
    expect(item.displayCode, 'config.integration.tmdb.apiKey');
  });

  test('parses configured storage buckets', () {
    final view = api.parseStorageResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'buckets': [
          {'name': 'user-files', 'purpose': '用户文件', 'status': 'CONFIGURED'},
        ],
      },
    });

    expect(view.buckets.single.name, 'user-files');
  });

  test('throws app exception when admin operations response is invalid', () {
    expect(
      () => api.parseTaskResponse({
        'code': 200,
        'message': 'success',
        'data': null,
      }),
      throwsA(isA<AppException>()),
    );
  });
}
