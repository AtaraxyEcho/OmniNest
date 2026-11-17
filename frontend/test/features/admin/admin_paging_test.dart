import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';

void main() {
  test('分页响应保留服务端分页元数据和条目顺序', () {
    final page = AdminPage.fromJson(<String, dynamic>{
      'items': [
        <String, dynamic>{
          'id': 'task-1',
          'taskType': 'PHOTO_SCAN',
          'status': 'RUNNING',
          'progress': 25,
          'routingKey': 'omni.photo.scan',
          'retryCount': 1,
          'createdAt': '2026-08-25T00:00:00Z',
          'updatedAt': '2026-08-25T00:01:00Z',
        },
      ],
      'page': 1,
      'size': 25,
      'totalElements': 51,
      'totalPages': 3,
    }, AdminTaskRecord.fromJson);

    expect(page.items.single.id, 'task-1');
    expect(page.page, 1);
    expect(page.size, 25);
    expect(page.totalElements, 51);
    expect(page.totalPages, 3);
    expect(page.hasPrevious, isTrue);
    expect(page.hasNext, isTrue);
  });

  test('非法条目集合降级为空页而不把弱类型数据传播到界面', () {
    final page = AdminPage.fromJson(<String, dynamic>{
      'items': <Object?>['invalid', 3],
      'page': 'not-a-number',
      'size': null,
      'totalElements': 'bad',
      'totalPages': 0,
    }, AdminTaskRecord.fromJson);

    expect(page.items, isEmpty);
    expect(page.page, 0);
    expect(page.size, 0);
    expect(page.totalElements, 0);
    expect(page.totalPages, 0);
    expect(page.hasPrevious, isFalse);
    expect(page.hasNext, isFalse);
  });
}
