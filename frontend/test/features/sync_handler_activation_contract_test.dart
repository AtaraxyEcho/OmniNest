import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/file_sync_handler.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/application/task_sync_handler.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/video_sync_handler.dart';

/// 捕获容器级 Ref，供直接构造各同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

RealtimeInvalidation _invalidation({
  required RealtimeScope scope,
  String resourceType = '*',
}) {
  return RealtimeInvalidation(
    key: 'inv-1',
    scope: scope,
    resourceType: resourceType,
    revision: 1,
    createdAt: DateTime.utc(2026, 9, 16),
  );
}

class _SpyTaskListNotifier extends TaskListNotifier {
  int loads = 0;

  @override
  Future<void> load() async {
    loads += 1;
  }
}

void main() {
  test(
    'task handler consumes invalidation when task module never activated',
    () async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final handler = TaskSyncHandler(container.read(refHolderProvider));

      final consumed = await handler.refresh([
        _invalidation(scope: RealtimeScope.tasks),
      ]);

      expect(consumed, isTrue);
      expect(container.exists(taskListProvider), isFalse);
    },
  );

  test('task handler reloads task list when module activated', () async {
    final container = ProviderContainer.test(
      overrides: [taskListProvider.overrideWith(_SpyTaskListNotifier.new)],
    );
    addTearDown(container.dispose);
    container.read(taskListProvider.notifier);
    final handler = TaskSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      _invalidation(scope: RealtimeScope.tasks),
    ]);

    expect(consumed, isTrue);
    expect(
      (container.read(taskListProvider.notifier) as _SpyTaskListNotifier).loads,
      1,
    );
  });

  test('file task handler consumes invalidation when files module never '
      'activated', () async {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final handler = FileTaskSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      _invalidation(
        scope: RealtimeScope.tasks,
        resourceType: 'TASK_EXTERNAL_IMPORT',
      ),
    ]);

    expect(consumed, isTrue);
    expect(container.exists(fileBrowserControllerProvider), isFalse);
  });

  test(
    'file handler consumes invalidation when files module never activated',
    () async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final handler = FileSyncHandler(container.read(refHolderProvider));

      final consumed = await handler.refresh([
        _invalidation(scope: RealtimeScope.files),
      ]);

      expect(consumed, isTrue);
      expect(container.exists(fileBrowserControllerProvider), isFalse);
    },
  );

  test('video task handler consumes invalidation when video module never '
      'activated', () async {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final handler = VideoTaskSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      _invalidation(
        scope: RealtimeScope.tasks,
        resourceType: 'TASK_VIDEO_TRANSCODE',
      ),
    ]);

    expect(consumed, isTrue);
    expect(container.exists(movieCenterControllerProvider), isFalse);
  });

  test(
    'video handler consumes invalidation when video module never activated',
    () async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final handler = VideoSyncHandler(container.read(refHolderProvider));

      final consumed = await handler.refresh([
        _invalidation(scope: RealtimeScope.video),
      ]);

      expect(consumed, isTrue);
      expect(container.exists(movieCenterControllerProvider), isFalse);
    },
  );
}
