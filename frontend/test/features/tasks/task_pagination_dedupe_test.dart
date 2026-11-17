import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/data/task_api.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

void main() {
  test('翻页追加按 id 去重，位移返回的重复任务不会生成重复卡片', () async {
    final api = _MockTaskApi();
    final firstPage = [
      for (var i = 0; i < 20; i++) _task('task-$i', 'PENDING'),
    ];
    when(() => api.list(page: 0)).thenAnswer((_) async => firstPage);
    // 后台新任务入队使第二页回带上一页最后一条。
    when(() => api.list(page: 1)).thenAnswer(
      (_) async => [_task('task-19', 'PENDING'), _task('task-20', 'PENDING')],
    );
    final container = ProviderContainer(
      overrides: [taskApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(taskListProvider.notifier).load();
    await container.read(taskListProvider.notifier).loadMore();

    final ids =
        container.read(taskListProvider).map((task) => task.id).toList();
    expect(ids.length, 21);
    expect(ids.toSet().length, 21);
    expect(ids.last, 'task-20');
  });
}

TaskRecord _task(String id, String status) {
  return TaskRecord(
    id: id,
    taskType: 'test',
    status: status,
    retryCount: 0,
    maxRetries: 3,
    createdAt: DateTime.utc(2026, 7, 14),
  );
}

class _MockTaskApi extends Mock implements TaskApi {}
