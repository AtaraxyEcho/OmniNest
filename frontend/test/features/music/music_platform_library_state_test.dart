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
      playlistTracks: <String, List<OnlineTrack>>{
        'netease:playlist-1': <OnlineTrack>[
          OnlineTrack(
            platform: 'netease',
            songId: 'song-1',
            title: 'Track',
            artistName: 'Artist',
            coverUrl: 'https://example.com/track.jpg',
          ),
        ],
      },
    );

    expect(
      state.coverUrlForPlaylist(playlist),
      'https://example.com/track.jpg',
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
      playlistTracks: <String, List<OnlineTrack>>{
        'netease:playlist-2': <OnlineTrack>[
          OnlineTrack(
            platform: 'netease',
            songId: 'song-2',
            title: 'Track',
            artistName: 'Artist',
          ),
        ],
      },
    );

    expect(
      state.coverUrlForPlaylist(playlist),
      'https://example.com/playlist.jpg',
    );
  });
}
