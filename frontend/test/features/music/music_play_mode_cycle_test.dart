import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// 播放模式三态互斥：顺序播放（首尾循环）→ 随机播放 → 单曲循环 → 顺序播放，
/// 以及与后端快照 off/all/one + shuffleEnabled 字段的互逆映射。

void main() {
  /// 恢复链路据播放队列快照还原播放模式。
  _StubMusicApi stubWith({required bool shuffle, required String repeatMode}) {
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

  Future<MusicCenterState> startWith(_StubMusicApi api) async {
    final container = containerWith(api);
    return container.read(musicCenterControllerProvider.future);
  }

  MusicCenterState stateOf(ProviderContainer container) =>
      container.read(musicCenterControllerProvider).value!;

  test('无快照状态时默认顺序播放', () async {
    final container = containerWith(
      stubWith(shuffle: false, repeatMode: 'off'),
    );
    final state = await container.read(musicCenterControllerProvider.future);
    expect(state.playMode, MusicPlayMode.sequential);
  });

  test('单按钮轮换走完三态后回到顺序播放', () async {
    final container = containerWith(
      stubWith(shuffle: false, repeatMode: 'off'),
    );
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.cyclePlayMode();
    expect(stateOf(container).playMode, MusicPlayMode.shuffle);

    controller.cyclePlayMode();
    expect(stateOf(container).playMode, MusicPlayMode.repeatOne);

    controller.cyclePlayMode();
    expect(stateOf(container).playMode, MusicPlayMode.sequential);
  });

  test('旧的 off 与 all 快照都归入顺序播放档', () async {
    expect(
      (await startWith(stubWith(shuffle: false, repeatMode: 'off'))).playMode,
      MusicPlayMode.sequential,
    );
    expect(
      (await startWith(stubWith(shuffle: false, repeatMode: 'all'))).playMode,
      MusicPlayMode.sequential,
    );
  });

  test('随机位优先于循环位，one 归入单曲循环', () async {
    expect(
      (await startWith(stubWith(shuffle: true, repeatMode: 'all'))).playMode,
      MusicPlayMode.shuffle,
    );
    expect(
      (await startWith(stubWith(shuffle: false, repeatMode: 'one'))).playMode,
      MusicPlayMode.repeatOne,
    );
  });

  test('播放模式按后端契约编码回快照', () async {
    final api = stubWith(shuffle: false, repeatMode: 'off');
    final container = containerWith(api);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    controller.setPlayMode(MusicPlayMode.repeatOne);
    await controller.flushPlaybackQueue();
    expect(api.remoteSaves.last.repeatMode, 'one', reason: '单曲循环沿用后端 one 位');
    expect(api.remoteSaves.last.shuffleEnabled, isFalse);

    controller.setPlayMode(MusicPlayMode.shuffle);
    await controller.flushPlaybackQueue();
    expect(api.remoteSaves.last.shuffleEnabled, isTrue);

    controller.setPlayMode(MusicPlayMode.sequential);
    await controller.flushPlaybackQueue();
    expect(
      api.remoteSaves.last.repeatMode,
      'all',
      reason: '顺序播放即列表首尾循环，沿用后端 all 位',
    );
    expect(api.remoteSaves.last.shuffleEnabled, isFalse);
  });
}

class _MemoryMusicPlaybackQueueStore implements MusicPlaybackQueueStore {
  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async => null;

  @override
  Future<void> save(
    String ownerId,
    MusicPlaybackQueueSnapshot snapshot,
  ) async {}
}

/// 仅实现构建链路与播放模式轮换用到的接口方法；未实现的方法按契约抛错。
class _StubMusicApi implements MusicApi {
  MusicPlaybackQueueSnapshot? queueSnapshot;

  /// 远端回写的播放队列快照：用于断言播放模式的编码。
  final List<MusicPlaybackQueueSnapshot> remoteSaves =
      <MusicPlaybackQueueSnapshot>[];

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
  ) async {
    remoteSaves.add(snapshot);
    return snapshot;
  }

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
