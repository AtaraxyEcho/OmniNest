// 音乐档来源回归：只按已加载曲库做本地过滤（判据与甲板搜索共用一份），
// 无分页语义、空白查询不产结果，结果行落回音乐空间。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_scoped_search_source.dart';
import 'package:omninest/features/music/domain/music_models.dart';

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

class _SeededMusicCenter extends MusicCenterController {
  _SeededMusicCenter(this.tracks);

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

/// AsyncNotifier 在被 read 的瞬间只是 AsyncLoading，先 await future
/// 才能让来源读到 asData。
Future<Ref> _open(List<MusicTrack> tracks) async {
  final container = ProviderContainer.test(
    overrides: [
      musicCenterControllerProvider.overrideWith(
        () => _SeededMusicCenter(tracks),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(musicCenterControllerProvider.future);
  final capture = Provider<Ref>((ref) => ref);
  return container.read(capture);
}

void main() {
  const source = MusicScopedSearchSource();

  test('标题、歌手、专辑任一字段命中都算结果', () async {
    final ref = await _open(<MusicTrack>[
      _track('t-1', title: 'Amber'),
      // 后两条标题里不含关键词，只能靠歌手/专辑字段命中。
      _track('t-2', title: 'Zeta', artist: 'Amber Lines'),
      _track('t-3', title: 'Omega', album: 'An Amber Year'),
      _track('t-4', title: 'Quiet', artist: 'Nobody', album: 'Nothing'),
    ]);

    final results = await source.search(ref, 'amber');

    expect(results.map((item) => item.title), <String>[
      'Amber',
      'Zeta',
      'Omega',
    ]);
    expect(results.every((item) => item.scope == ScopedSearchId.music), isTrue);
    expect(results.every((item) => item.detailRoute == '/music'), isTrue);
    expect(results.first.subtitle, 'Marconi Union · Evening Drift');
  });

  test('单档结果受 perSource 上限约束', () async {
    final many = List<MusicTrack>.generate(
      ScopedSearchLimits.perSource + 5,
      (index) => _track('t-$index', title: 'Amber $index'),
    );
    final ref = await _open(many);

    final results = await source.search(ref, 'amber');

    expect(results, hasLength(ScopedSearchLimits.perSource));
  });

  test('本地过滤没有分页，第二页起回空让加载更多停止', () async {
    final ref = await _open(<MusicTrack>[_track('t-1', title: 'Amber')]);

    expect(await source.search(ref, 'amber', page: 1), isEmpty);
  });

  test('空白查询不产结果', () async {
    final ref = await _open(<MusicTrack>[_track('t-1')]);

    expect(await source.search(ref, '   '), isEmpty);
  });

  test('曲库尚未加载时回空而不是抛错', () async {
    // 不覆盖曲库控制器：provider 处于 AsyncLoading，来源应回空而不是抛错。
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final capture = Provider<Ref>((ref) => ref);
    final ref = container.read(capture);

    final results = await const MusicScopedSearchSource().search(ref, 'amber');

    expect(results, isEmpty);
  });
}
