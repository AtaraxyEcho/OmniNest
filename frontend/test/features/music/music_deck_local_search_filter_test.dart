// 甲板本地曲目过滤回归：标题/歌手/专辑任一字段命中都算结果、命中量封顶 40、
// 少于两个字符不起搜索、曲库还在加载时不抛错。
// 音乐档的全库检索已交给 `/music/search?q=`，这里只保证甲板页内那条本地判据不塌。
//
// 时钟用 fake_async 推进：控制器里的 300ms 防抖是真实 Timer，用 sleep 等它等于
// 随机种下抖动用例（覆盖层那侧已经是 tester.pump 的同一口径）。
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_deck_search_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

MusicTrack _track(String id, {String? title, String? artist, String? album}) {
  return MusicTrack(
    id: id,
    fileNodeId: 'file-$id',
    title: title ?? 'Track $id',
    artistName: artist ?? 'Marconi Union',
    albumTitle: album ?? 'Evening Drift',
    format: 'flac',
    favorite: false,
  );
}

class _SeededCenter extends MusicCenterController {
  _SeededCenter(this.tracks);

  /// null 表示曲库永远停在 AsyncLoading，用来验本地判据不抛错。
  final List<MusicTrack>? tracks;

  @override
  Future<MusicCenterState> build() {
    final seed = tracks;
    if (seed == null) {
      return Completer<MusicCenterState>().future;
    }
    return Future<MusicCenterState>.value(
      MusicCenterState(
        dashboard: MusicDashboard.empty(),
        tracks: seed,
        albums: const <MusicAlbum>[],
        artists: const <MusicArtist>[],
        playlists: const <MusicPlaylist>[],
      ),
    );
  }
}

/// 在假时钟里跑一次甲板本地搜索：建容器 → 让曲库 build 落地 → 发查询 → 越过防抖窗口。
List<MusicPlayableItem> _localResults({
  required String query,
  List<MusicTrack>? tracks,
}) {
  late MusicDeckSearchState state;
  fakeAsync((async) {
    final container = ProviderContainer.test(
      overrides: [
        musicCenterControllerProvider.overrideWith(() => _SeededCenter(tracks)),
      ],
    );
    addTearDown(container.dispose);
    // 曲库 provider 被读到才开始 build；不先落到 asData，本地判据会把它当"不可用"。
    container.read(musicCenterControllerProvider);
    async.flushMicrotasks();
    // autoDispose 控制器裸 read 会被立即释放，onDispose 顺手取消防抖 Timer。
    final keepAlive = container.listen<MusicDeckSearchState>(
      musicDeckSearchProvider,
      (previous, next) {},
    );
    addTearDown(keepAlive.close);

    container.read(musicDeckSearchProvider.notifier).updateQuery(
      query,
      <MusicPlatform>{MusicPlatform.local},
    );
    async.elapse(const Duration(milliseconds: 400));
    state = container.read(musicDeckSearchProvider);
  });
  return state.results[MusicPlatform.local] ?? const <MusicPlayableItem>[];
}

void main() {
  test('标题、歌手、专辑任一字段命中都算本地结果', () {
    final results = _localResults(
      query: 'amber',
      tracks: <MusicTrack>[
        _track('t-1', title: 'Amber'),
        // 后两条标题里不含关键词，只能靠歌手/专辑字段命中。
        _track('t-2', title: 'Zeta', artist: 'Amber Lines'),
        _track('t-3', title: 'Omega', album: 'An Amber Year'),
        _track('t-4', title: 'Quiet', artist: 'Nobody', album: 'Nothing'),
      ],
    );

    expect(results.map((item) => item.track.title), <String>[
      'Amber',
      'Zeta',
      'Omega',
    ]);
  });

  test('本地结果封顶 40 条', () {
    final results = _localResults(
      query: 'amber',
      tracks: List<MusicTrack>.generate(
        45,
        (index) => _track('t-$index', title: 'Amber $index'),
      ),
    );

    expect(results, hasLength(40));
  });

  test('少于两个字符不起搜索', () {
    final results = _localResults(
      query: 'a',
      tracks: <MusicTrack>[_track('t-1', title: 'Amber')],
    );

    expect(results, isEmpty);
  });

  test('曲库还在加载时不产本地结果也不抛错', () {
    final results = _localResults(query: 'amber');

    expect(results, isEmpty);
  });
}
