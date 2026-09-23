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

  test('在线曲目的缩略位随统一模型下发', () {
    const online = OnlineTrack(
      platform: 'netease',
      songId: 'song-1',
      title: 'Online Song',
      artistName: 'Online Artist',
      albumTitle: 'Online Album',
      coverUrl: 'https://example.com/full.jpg',
      thumbUrl: 'https://example.com/full.jpg?paramSize=300x300',
    );

    final track = MusicPlayableItem.online(online).track;

    // 列表取缩放图，大图与沉浸卡组继续用原图。
    expect(
      track.listCoverUrl,
      'https://example.com/full.jpg?paramSize=300x300',
    );
    expect(track.coverUrl, 'https://example.com/full.jpg');

    const withoutThumb = OnlineTrack(
      platform: 'netease',
      songId: 'song-2',
      title: 'No Thumb',
      artistName: 'Online Artist',
      coverUrl: 'https://example.com/plain.jpg',
    );
    expect(
      MusicPlayableItem.online(withoutThumb).track.listCoverUrl,
      'https://example.com/plain.jpg',
    );

    const local = MusicTrack(
      id: 'track-1',
      fileNodeId: 'file-1',
      title: 'Local Song',
      artistName: 'Local Artist',
      albumTitle: 'Local Album',
      format: 'flac',
      favorite: false,
      coverUrl: '/api/v1/music/covers/file-1',
    );
    // 本地曲库没有缩放端点，回退稳定鉴权路径。
    expect(local.listCoverUrl, '/api/v1/music/covers/file-1');
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
