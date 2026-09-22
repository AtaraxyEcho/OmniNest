import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

void main() {
  test('本地曲目使用类型安全的本地引用', () {
    const track = MusicTrack(
      id: 'track-1',
      fileNodeId: 'file-1',
      title: 'Local Song',
      artistName: 'Local Artist',
      albumTitle: 'Local Album',
      format: 'flac',
      favorite: false,
    );

    final item = MusicPlayableItem.local(track);

    expect(item.ref, isA<LocalMusicRef>());
    expect(item.playableKey, 'local:track-1');
    expect(item.track, same(track));
  });

  test('在线曲目保留平台歌曲标识和媒体标识', () {
    const track = OnlineTrack(
      platform: 'netease',
      songId: 'song-1',
      title: 'Online Song',
      artistName: 'Online Artist',
      albumTitle: 'Online Album',
      durationSeconds: 180,
    );

    final item = MusicPlayableItem.online(track);
    final ref = item.ref as OnlineMusicRef;

    expect(ref.platform, MusicPlatform.netease);
    expect(ref.songId, 'song-1');
    expect(item.playableKey, 'online:netease:song-1');
    expect(item.track.id, item.playableKey);
  });

  test('未知在线平台不会降级为本地来源', () {
    expect(
      () => MusicPlayableItem.online(
        const OnlineTrack(
          platform: 'unknown',
          songId: 'song-1',
          title: 'Unknown Song',
          artistName: 'Unknown Artist',
        ),
      ),
      throwsFormatException,
    );
  });
}
