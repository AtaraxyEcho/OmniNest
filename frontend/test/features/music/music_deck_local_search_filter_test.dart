// 甲板本地曲目过滤回归：标题/歌手/专辑任一字段命中都算结果，命中量封顶 40。
// 音乐档的全库检索已交给 `/music/search?q=`，这里只保证甲板页内那条本地判据不塌。
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

  final List<MusicTrack> tracks;

  @override
  Future<MusicCenterState> build() async {
    return MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: tracks,
      albums: const <MusicAlbum>[],
      artists: const <MusicArtist>[],
      playlists: const <MusicPlaylist>[],
    );
  }
}

/// `tracks == null` 表示曲库停在 AsyncLoading，用来验本地判据不抛错。
///
/// 三个非显然的前置：控制器是 autoDispose，裸 `read` 之后元素立即释放，`onDispose`
/// 会取消防抖 Timer，所以必须挂监听保住它；曲库 provider 被读到才开始 build，不先
/// await 的话搜索瞬间拿到的是 null；防抖是 300ms 真实 Timer，要等它跑完。
Future<MusicDeckSearchState> _search({
  required String query,
  List<MusicTrack>? tracks,
}) async {
  final container = ProviderContainer.test(
    overrides: [
      if (tracks != null)
        musicCenterControllerProvider.overrideWith(() => _SeededCenter(tracks)),
    ],
  );
  addTearDown(container.dispose);
  if (tracks != null) {
    await container.read(musicCenterControllerProvider.future);
  }
  final keepAlive = container.listen<MusicDeckSearchState>(
    musicDeckSearchProvider,
    (previous, next) {},
  );
  addTearDown(keepAlive.close);

  container.read(musicDeckSearchProvider.notifier).updateQuery(
    query,
    <MusicPlatform>{MusicPlatform.local},
  );
  await Future<void>.delayed(const Duration(milliseconds: 600));
  return container.read(musicDeckSearchProvider);
}

void main() {
  test('标题、歌手、专辑任一字段命中都算本地结果', () async {
    final state = await _search(
      query: 'amber',
      tracks: <MusicTrack>[
        _track('t-1', title: 'Amber'),
        // 后两条标题里不含关键词，只能靠歌手/专辑字段命中。
        _track('t-2', title: 'Zeta', artist: 'Amber Lines'),
        _track('t-3', title: 'Omega', album: 'An Amber Year'),
        _track('t-4', title: 'Quiet', artist: 'Nobody', album: 'Nothing'),
      ],
    );

    expect(
      state.results[MusicPlatform.local]?.map((item) => item.track.title),
      <String>['Amber', 'Zeta', 'Omega'],
    );
  });

  test('本地结果封顶 40 条', () async {
    final state = await _search(
      query: 'amber',
      tracks: List<MusicTrack>.generate(
        45,
        (index) => _track('t-$index', title: 'Amber $index'),
      ),
    );

    expect(state.results[MusicPlatform.local], hasLength(40));
  });

  test('曲库尚未加载时不产本地结果也不抛错', () async {
    final state = await _search(query: 'amber');

    expect(state.results, isEmpty);
  });
}
