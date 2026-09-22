import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/video_sync_handler.dart';

/// 捕获容器级 Ref，供直接构造同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

void main() {
  test('库源事件刷新挂载中的库源列表', () async {
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        videoLibrarySourcesProvider.overrideWith((ref) async {
          builds += 1;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 需要监听保活。
    final subscription = container.listen(
      videoLibrarySourcesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(videoLibrarySourcesProvider.future);
    expect(builds, 1);

    final handler = VideoSyncHandler(container.read(refHolderProvider));
    final consumed = await handler.refresh([
      RealtimeInvalidation(
        key: 'video-library-source',
        scope: RealtimeScope.video,
        resourceType: 'VIDEO_LIBRARY',
        resourceId: 'source-1',
        revision: 1,
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ]);

    expect(consumed, isTrue);
    expect(builds, 2);
  });

  test('本地媒体库发现与入库任务进入影视任务白名单', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = VideoTaskSyncHandler(container.read(refHolderProvider));

    bool appliesToTask(String resourceType) {
      return handler.appliesTo(
        RealtimeInvalidation(
          key: 'task-$resourceType',
          scope: RealtimeScope.tasks,
          resourceType: resourceType,
          revision: 1,
          createdAt: DateTime.utc(2026, 9, 20),
        ),
      );
    }

    expect(appliesToTask('TASK_LOCAL_VIDEO_LIBRARY_DISCOVERY'), isTrue);
    expect(appliesToTask('TASK_LOCAL_VIDEO_LIBRARY_APPLY'), isTrue);
    expect(appliesToTask('TASK_UNRELATED'), isFalse);
  });
}
