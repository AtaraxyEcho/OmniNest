import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';

void main() {
  test('外部歌单优先使用第一首歌曲封面', () {
    const playlist = OnlinePlaylist(
      platform: 'netease',
      playlistId: 'playlist-1',
      name: 'Daily',
      coverUrl: 'https://example.com/playlist.jpg',
    );
    const state = MusicPlatformLibraryState(
      playlistTracks: <String, MusicPagedResult<OnlineTrack>>{
        'netease:playlist-1': MusicPagedResult<OnlineTrack>(
          items: <OnlineTrack>[
            OnlineTrack(
              platform: 'netease',
              songId: 'song-1',
              title: 'Track',
              artistName: 'Artist',
              coverUrl: 'https://example.com/track.jpg',
              thumbUrl: 'https://example.com/track-300.jpg',
            ),
          ],
          page: 0,
          size: 50,
          totalElements: 800,
        ),
      },
    );

    // 预热页首曲的缩略位优先于原图，封面网格不下载全尺寸图片。
    expect(
      state.coverUrlForPlaylist(playlist),
      'https://example.com/track-300.jpg',
    );
  });

  test('歌曲没有缩放地址时回退到歌单自身的缩略位', () {
    const playlist = OnlinePlaylist(
      platform: 'netease',
      playlistId: 'playlist-3',
      name: 'Daily',
      coverUrl: 'https://example.com/playlist.jpg',
      thumbUrl: 'https://example.com/playlist-300.jpg',
    );
    const state = MusicPlatformLibraryState(
      playlistTracks: <String, MusicPagedResult<OnlineTrack>>{
        'netease:playlist-3': MusicPagedResult<OnlineTrack>(
          items: <OnlineTrack>[
            OnlineTrack(
              platform: 'netease',
              songId: 'song-3',
              title: 'Track',
              artistName: 'Artist',
              coverUrl: 'https://example.com/track.jpg',
            ),
          ],
          page: 0,
          size: 50,
          totalElements: 1,
        ),
      },
    );

    // 首曲原图仍优于歌单缩略位：只在没有首曲封面时才回退。
    expect(
      state.coverUrlForPlaylist(playlist),
      'https://example.com/track.jpg',
    );
    expect(
      const MusicPlatformLibraryState().coverUrlForPlaylist(playlist),
      'https://example.com/playlist-300.jpg',
    );
  });

  test('第一首歌曲没有封面时回退到平台歌单封面', () {
    const playlist = OnlinePlaylist(
      platform: 'netease',
      playlistId: 'playlist-2',
      name: 'Daily',
      coverUrl: 'https://example.com/playlist.jpg',
    );
    const state = MusicPlatformLibraryState(
      playlistTracks: <String, MusicPagedResult<OnlineTrack>>{
        'netease:playlist-2': MusicPagedResult<OnlineTrack>(
          items: <OnlineTrack>[
            OnlineTrack(
              platform: 'netease',
              songId: 'song-2',
              title: 'Track',
              artistName: 'Artist',
            ),
          ],
          page: 0,
          size: 50,
          totalElements: 2,
        ),
      },
    );

    expect(
      state.coverUrlForPlaylist(playlist),
      'https://example.com/playlist.jpg',
    );
  });
}
