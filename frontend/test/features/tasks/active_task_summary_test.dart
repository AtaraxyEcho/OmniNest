import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/data/task_api.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

void main() {
  test('活动任务摘要优先展示失败任务并统计活动数量', () {
    final summary = ActiveTaskSummary.fromRecords([
      _task('pending', 'PENDING'),
      _task('running', 'RUNNING'),
      _task('failed', 'FAILED'),
      _task('completed', 'COMPLETED'),
    ]);

    expect(summary.activeCount, 2);
    expect(summary.failedCount, 1);
    expect(summary.priorityTask?.id, 'failed');
    expect(summary.hasActivity, isTrue);
  });

  test('活动任务 Provider 不依赖任务页面列表状态', () async {
    final api = _MockTaskApi();
    when(
      () => api.list(page: 0, size: 100),
    ).thenAnswer((_) async => [_task('running', 'RUNNING')]);
    final container = ProviderContainer(
      overrides: [
        taskApiProvider.overrideWithValue(api),
        // 摘要接口分支按能力门控；本用例验证 task:read 用户走列表推导。
        userCapabilitiesProvider.overrideWithValue(
          const UserCapabilities(
            canBrowseContent: true,
            canContributeContent: true,
            canManageOwnActivity: true,
            canManagePreferences: true,
            canManageAccount: true,
            canUseBackdropLibrary: true,
            canUploadBackdrop: true,
            canViewOwnTasks: true,
            canAdminTasks: true,
            canManageMediaLibrary: true,
            canManagePhotos: true,
            canAdminUsers: true,
            canReadSystemConfig: true,
            canManageSystemConfig: true,
            canAccessAdminConsole: true,
            canSharedBrowse: true,
            canSharedUpload: true,
            canReadWeather: true,
            canReportLocation: true,
            canManageTwoFactor: true,
            canReadActivity: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(taskListProvider), isEmpty);
    final summary = await container.read(activeTaskSummaryProvider.future);

    expect(summary.activeCount, 1);
    expect(summary.priorityTask?.id, 'running');
    verify(() => api.list(page: 0, size: 100)).called(1);
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
