import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
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

class _CountingHistoryNotifier extends MusicHistoryController {
  _CountingHistoryNotifier(this.onBuild);

  final void Function() onBuild;

  @override
  Future<MusicHistoryState> build() async {
    onBuild();
    return const MusicHistoryState();
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
}
