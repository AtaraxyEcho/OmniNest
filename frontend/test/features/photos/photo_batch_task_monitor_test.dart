import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/photos/application/photo_batch_task_monitor.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo_batch_task.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

void main() {
  test('monitor stops after a terminal task', () async {
    final repository = _MockPhotoRepository();
    when(() => repository.getBatchTask('task-1')).thenAnswer(
      (_) async => PhotoBatchTask(
        id: 'task-1',
        taskType: 'TAG',
        status: 'COMPLETED',
        totalItems: 1,
        processedItems: 1,
        createdAt: DateTime(2026),
      ),
    );
    final container = ProviderContainer(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      photoBatchTaskMonitorProvider('task-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final value = await container.read(
      photoBatchTaskMonitorProvider('task-1').future,
    );

    expect(value.task?.isCompleted, isTrue);
    verify(() => repository.getBatchTask('task-1')).called(1);
  });

  test('monitor reports not found as a terminal issue', () async {
    final repository = _MockPhotoRepository();
    when(
      () => repository.getBatchTask('missing'),
    ).thenThrow(const AppException(code: 'TASK_NOT_FOUND', message: 'missing'));
    final container = ProviderContainer(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      photoBatchTaskMonitorProvider('missing'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final value = await container.read(
      photoBatchTaskMonitorProvider('missing').future,
    );

    expect(value.issue, PhotoBatchTaskMonitorIssue.notFound);
    verify(() => repository.getBatchTask('missing')).called(1);
  });

  test('monitor has a finite total duration', () async {
    final repository = _MockPhotoRepository();
    final container = ProviderContainer(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        photoBatchTaskMonitorPolicyProvider.overrideWithValue(
          const PhotoBatchTaskMonitorPolicy(maximumDuration: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      photoBatchTaskMonitorProvider('task-2'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final value = await container.read(
      photoBatchTaskMonitorProvider('task-2').future,
    );

    expect(value.issue, PhotoBatchTaskMonitorIssue.timedOut);
    verifyNever(() => repository.getBatchTask(any()));
  });
}
