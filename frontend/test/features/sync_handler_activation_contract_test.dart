import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/sync/preference_sync_handler.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_sync_handler.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/file_sync_handler.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/application/task_sync_handler.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/video_sync_handler.dart';

/// 捕获容器级 Ref，供直接构造各同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

RealtimeInvalidation _invalidation({
  required RealtimeScope scope,
  String resourceType = '*',
  String? resourceId,
}) {
  return RealtimeInvalidation(
    key: 'inv-1',
    scope: scope,
    resourceType: resourceType,
    resourceId: resourceId,
    revision: 1,
    createdAt: DateTime.utc(2026, 9, 16),
  );
}

/// 已挂载但远端刷新必然失败的阅读偏好控制器。
class _ThrowingReaderPreferences extends ReaderPreferencesController {
  @override
  Future<Map<String, dynamic>> build() async => const <String, dynamic>{};

  @override
  Future<void> refreshFromRemote() async {
    throw StateError('测试用远端偏好刷新失败');
  }
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
      overrides: [
        taskListProvider.overrideWith(_SpyTaskListNotifier.new),
        // GUEST 门控会跳过列表重载；本用例验证 task:read 用户的重载路径。
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

  test(
    'admin handler consumes invalidation when admin module never activated',
    () async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final handler = AdminSyncHandler(container.read(refHolderProvider));

      final consumed = await handler.refresh([
        _invalidation(scope: RealtimeScope.admin),
      ]);

      expect(consumed, isTrue);
      expect(container.exists(adminConsoleControllerProvider), isFalse);
    },
  );

  test('admin handler consumes invalidation when only auxiliary caches are '
      'mounted', () async {
    final container = ProviderContainer.test(
      overrides: [
        adminConnectorOAuthAppsProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    await container.read(adminConnectorOAuthAppsProvider.future);
    final handler = AdminSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      _invalidation(scope: RealtimeScope.admin),
    ]);

    // 已挂载的附属缓存刷新成功，管理主模块未挂载：事件必须确认消费。
    expect(consumed, isTrue);
    expect(container.exists(adminConsoleControllerProvider), isFalse);
  });

  test('preference handler consumes invalidation when preference target never '
      'activated', () async {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final handler = PreferenceSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([
      _invalidation(
        scope: RealtimeScope.preferences,
        resourceType: readerPreferenceScope,
        resourceId: readerPreferenceScope,
      ),
    ]);

    expect(consumed, isTrue);
    expect(container.exists(readerPreferencesProvider), isFalse);
  });

  test('preference handler keeps retrying when a mounted target refresh '
      'throws', () async {
    final container = ProviderContainer.test(
      overrides: [
        readerPreferencesProvider.overrideWith(_ThrowingReaderPreferences.new),
      ],
    );
    addTearDown(container.dispose);
    // 先挂载目标，模拟用户正停在依赖该偏好的页面。
    await container.read(readerPreferencesProvider.future);
    final handler = PreferenceSyncHandler(container.read(refHolderProvider));

    await expectLater(
      handler.refresh([
        _invalidation(
          scope: RealtimeScope.preferences,
          resourceType: readerPreferenceScope,
          resourceId: readerPreferenceScope,
        ),
      ]),
      throwsA(isA<StateError>()),
    );
  });
}
