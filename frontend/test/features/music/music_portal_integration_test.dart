import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_portal_integration.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

class _RecentItemsCenter extends MusicCenterController {
  _RecentItemsCenter(this.recent);

  final List<MusicPlayableItem> recent;

  @override
  Future<MusicCenterState> build() async => MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const <MusicTrack>[],
    albums: const <MusicAlbum>[],
    artists: const <MusicArtist>[],
    playlists: const <MusicPlaylist>[],
    recentItems: recent,
  );
}

void main() {
  test('Portal 音乐投影限制列表容量并保留当前播放信息', () {
    final tracks = List<MusicTrack>.generate(
      8,
      (index) =>
          _track('$index', lyricsRaw: index == 0 ? '[00:01.00]第一行' : null),
    );
    final items = tracks.map(MusicPlayableItem.local).toList();
    final state = MusicCenterState(
      dashboard: MusicDashboard(
        trackCount: tracks.length,
        albumCount: 1,
        artistCount: 1,
        playHistoryCount: tracks.length,
        recentTracks: tracks,
        recentAlbums: const <MusicAlbum>[],
        featuredArtists: const <MusicArtist>[],
      ),
      tracks: tracks,
      albums: const <MusicAlbum>[],
      artists: const <MusicArtist>[],
      playlists: const <MusicPlaylist>[],
      currentItem: items.first,
      playbackItems: <MusicPlayableItem>[...items, items.first],
      playbackIndex: 0,
      recentItems: items,
      isPlaying: true,
    );

    final snapshot = projectMusicPortalSnapshot(state);

    expect(snapshot.featuredTrack?.id, '0');
    expect(snapshot.activeTrack?.id, '0');
    expect(snapshot.activeTrack?.lyrics.single.text, '第一行');
    expect(snapshot.queuePreview.map((track) => track.id), <String>[
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
    ]);
    expect(snapshot.recentTracks, hasLength(5));
    expect(snapshot.recentPlayCount, 8);
    expect(snapshot.isPlaying, isTrue);
  });

  test('Portal 音乐投影按队列索引和仪表盘专辑回退', () {
    final queued = MusicPlayableItem.local(_track('queued'));
    const album = MusicAlbum(
      id: 'album-1',
      title: '专辑',
      artistName: '作者',
      trackCount: 1,
    );
    final state = MusicCenterState(
      dashboard: const MusicDashboard(
        trackCount: 0,
        albumCount: 1,
        artistCount: 0,
        playHistoryCount: 0,
        recentTracks: <MusicTrack>[],
        recentAlbums: <MusicAlbum>[album],
        featuredArtists: <MusicArtist>[],
      ),
      tracks: const <MusicTrack>[],
      albums: const <MusicAlbum>[album],
      artists: const <MusicArtist>[],
      playlists: const <MusicPlaylist>[],
      playbackItems: <MusicPlayableItem>[queued],
      playbackIndex: 0,
    );

    final snapshot = projectMusicPortalSnapshot(state);

    expect(snapshot.featuredTrack?.id, 'queued');
    expect(snapshot.featuredAlbum?.title, '专辑');
    expect(snapshot.activeTrack, isNull);
    expect(snapshot.isPlaying, isFalse);
  });

  test('recentItemsIndexOf 按曲目 ID 定位最近列表下标', () {
    final items = <MusicPlayableItem>[
      MusicPlayableItem.local(_track('a')),
      MusicPlayableItem.local(_track('b')),
      MusicPlayableItem.local(_track('c')),
    ];

    expect(MusicPortalActions.recentItemsIndexOf(items, 'b'), 1);
    expect(MusicPortalActions.recentItemsIndexOf(items, 'missing'), -1);
    expect(MusicPortalActions.recentItemsIndexOf(const [], 'a'), -1);
  });

  test('playRecentTrack 对不在最近列表的曲目静默忽略', () async {
    final items = <MusicPlayableItem>[MusicPlayableItem.local(_track('a'))];
    final container = ProviderContainer(
      overrides: [
        musicCenterControllerProvider.overrideWith(
          () => _RecentItemsCenter(items),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final actions = container.read(musicPortalActionsProvider);

    // 不抛异常且不触发真实播放链路即为通过（命中 -1 短路）。
    await actions.playRecentTrack('missing');
  });
}

MusicTrack _track(String id, {String? lyricsRaw}) {
  return MusicTrack(
    id: id,
    fileNodeId: 'file-$id',
    title: '歌曲 $id',
    artistName: '作者 $id',
    albumTitle: '专辑 $id',
    format: 'FLAC',
    favorite: false,
    lyricsRaw: lyricsRaw,
  );
}
