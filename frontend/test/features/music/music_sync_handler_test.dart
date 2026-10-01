import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_sync_handler.dart';

/// 捕获容器级 Ref，供直接构造同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

RealtimeInvalidation _playHistoryInvalidation(int revision) {
  return RealtimeInvalidation(
    key: 'music-history-$revision',
    scope: RealtimeScope.music,
    resourceType: 'MUSIC_PLAY_HISTORY',
    revision: revision,
    createdAt: DateTime.utc(2026, 9, 20),
  );
}

RealtimeInvalidation _invalidation(String key, String resourceType) {
  return RealtimeInvalidation(
    key: key,
    scope: RealtimeScope.music,
    resourceType: resourceType,
    revision: 1,
    createdAt: DateTime.utc(2026, 9, 20),
  );
}

class _CountingHistoryNotifier extends MusicHistoryController {
  _CountingHistoryNotifier(this.onBuild);

  final void Function() onBuild;

  @override
  Future<MusicHistoryState> build() async {
    onBuild();
    return const MusicHistoryState();
  }
}

/// 记录平台曲库控制器的重建与强刷调用，用于区分 invalidate 与 force 刷新路径。
class _RecordingLibraryNotifier extends MusicPlatformLibraryController {
  _RecordingLibraryNotifier(this.calls);

  final List<String> calls;

  @override
  Future<MusicPlatformLibraryState> build() async {
    calls.add('build');
    return const MusicPlatformLibraryState();
  }

  @override
  Future<void> refreshForRealtime() async {
    calls.add('refreshForRealtime');
  }
}

void main() {
  test('播放历史事件刷新已挂载的历史页缓存', () async {
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        musicHistoryControllerProvider.overrideWith(
          () => _CountingHistoryNotifier(() => builds += 1),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicHistoryControllerProvider.future);
    expect(builds, 1);

    final handler = MusicSyncHandler(container.read(refHolderProvider));
    final consumed = await handler.refresh([_playHistoryInvalidation(1)]);

    expect(consumed, isTrue);
    expect(builds, 2);
  });

  test('未挂载音乐 provider 时播放历史事件直接消费', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = MusicSyncHandler(container.read(refHolderProvider));

    final consumed = await handler.refresh([_playHistoryInvalidation(1)]);

    expect(consumed, isTrue);
    expect(container.exists(musicHistoryControllerProvider), isFalse);
    expect(container.exists(musicCenterControllerProvider), isFalse);
  });

  test('平台账号变更事件走缓存优先重建，不强制回源', () async {
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        musicPlatformLibraryProvider.overrideWith(
          () => _RecordingLibraryNotifier(calls),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    calls.clear();

    final handler = MusicSyncHandler(container.read(refHolderProvider));
    final consumed = await handler.refresh([
      _invalidation('music-platform-1', 'MUSIC_PLATFORM'),
    ]);

    expect(consumed, isTrue);
    // invalidate 重建（命中后端已失效后的缓存或预热），不触发强制回源。
    expect(calls, contains('build'));
    expect(calls, isNot(contains('refreshForRealtime')));
  });

  test('曲库扫描等其余音乐事件保持强制回源刷新', () async {
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        musicPlatformLibraryProvider.overrideWith(
          () => _RecordingLibraryNotifier(calls),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicPlatformLibraryProvider.future);
    calls.clear();

    final handler = MusicSyncHandler(container.read(refHolderProvider));
    final consumed = await handler.refresh([
      _invalidation('music-scan-1', 'MUSIC_LIBRARY'),
    ]);

    expect(consumed, isTrue);
    expect(calls, contains('refreshForRealtime'));
  });
}
