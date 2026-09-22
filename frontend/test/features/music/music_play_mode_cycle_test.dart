import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// 播放模式单按钮轮换：顺序 → 随机 → 循环 → 顺序，三种模式互斥。

void main() {
  /// 播放队列快照桩：恢复链路据此还原随机/循环状态。
  _StubMusicApi stubWith({
    required bool shuffle,
    required String repeatMode,
  }) {
    final api = _StubMusicApi();
    api.queueSnapshot = MusicPlaybackQueueSnapshot.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'playableKey': 'netease:1',
          'platform': 'netease',
          'songId': '1',
          'track': <String, dynamic>{
            'id': 'netease:1',
            'title': 'Track',
            'artistName': 'A',
            'albumTitle': 'B',
            'format': 'mp3',
          },
        },
      ],
      'currentIndex': 0,
      'shuffleEnabled': shuffle,
      'repeatMode': repeatMode,
    });
    return api;
  }

  ProviderContainer containerWith(_StubMusicApi api) {
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('顺序 → 随机：开启洗牌并保持循环关闭', () async {
    final container = containerWith(
      stubWith(shuffle: false, repeatMode: 'off'),
    );
    await container.read(musicCenterControllerProvider.future);
    container.read(musicCenterControllerProvider.notifier).cyclePlayMode();
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.shuffleEnabled, isTrue);
    expect(state.repeatMode, MusicRepeatMode.off);
  });

  test('随机 → 循环：关闭洗牌并进入列表循环', () async {
    final container = containerWith(
      stubWith(shuffle: true, repeatMode: 'off'),
    );
    await container.read(musicCenterControllerProvider.future);
    container.read(musicCenterControllerProvider.notifier).cyclePlayMode();
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.shuffleEnabled, isFalse);
    expect(state.repeatMode, MusicRepeatMode.all);
  });

  test('循环 → 顺序：关闭循环且不启用随机', () async {
    final container = containerWith(
      stubWith(shuffle: false, repeatMode: 'all'),
    );
    await container.read(musicCenterControllerProvider.future);
    container.read(musicCenterControllerProvider.notifier).cyclePlayMode();
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.shuffleEnabled, isFalse);
    expect(state.repeatMode, MusicRepeatMode.off);
  });

  test('从随机与循环叠加的组合态轮换：归一到循环档且互斥', () async {
    final container = containerWith(
      stubWith(shuffle: true, repeatMode: 'all'),
    );
    await container.read(musicCenterControllerProvider.future);
    container.read(musicCenterControllerProvider.notifier).cyclePlayMode();
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.shuffleEnabled, isFalse);
    expect(state.repeatMode, MusicRepeatMode.all);
  });

  test('旧的单曲循环状态轮换后归一到随机', () async {
    final container = containerWith(
      stubWith(shuffle: false, repeatMode: 'one'),
    );
    await container.read(musicCenterControllerProvider.future);
    container.read(musicCenterControllerProvider.notifier).cyclePlayMode();
    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.shuffleEnabled, isTrue);
    expect(state.repeatMode, MusicRepeatMode.off);
  });
}

class _MemoryMusicPlaybackQueueStore implements MusicPlaybackQueueStore {
  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async => null;

  @override
  Future<void> save(String ownerId, MusicPlaybackQueueSnapshot snapshot) async {}
}

/// 仅实现构建链路与播放模式轮换用到的接口方法；未实现的方法按契约抛错。
class _StubMusicApi implements MusicApi {
  MusicPlaybackQueueSnapshot? queueSnapshot;

  MusicPagedResult<T> _emptyPage<T>() =>
      MusicPagedResult<T>(items: <T>[], page: 0, size: 30);

  @override
  Future<MusicDashboard> dashboard() async =>
      MusicDashboard.fromJson(const <String, dynamic>{});

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => _emptyPage<MusicTrack>();

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async => _emptyPage<MusicAlbum>();

  @override
  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async => _emptyPage<MusicArtist>();

  @override
  Future<List<MusicPlaylist>> playlists() async => const <MusicPlaylist>[];

  @override
  Future<List<MusicRecentEntry>> recentItems() async =>
      const <MusicRecentEntry>[];

  @override
  Future<MusicTrack?> lastPlayed() async => null;

  @override
  Future<MusicPlaybackQueueSnapshot> playbackQueue() async =>
      queueSnapshot ??
      MusicPlaybackQueueSnapshot.fromJson(const <String, dynamic>{});

  @override
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async => snapshot;

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
