import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('local playback queue snapshots are isolated by user', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = SharedPreferencesMusicPlaybackQueueStore();
    final updatedAt = DateTime.utc(2026, 7, 13, 12, 30);
    final snapshot = MusicPlaybackQueueSnapshot(
      items: <MusicPlayableItem>[MusicPlayableItem.local(_track)],
      currentIndex: 0,
      repeatMode: 'all',
      shuffleEnabled: true,
      updatedAt: updatedAt,
    );

    await store.save('user-a', snapshot);

    final restored = await store.load('user-a');
    expect(restored?.currentItem?.playableKey, 'local:track-1');
    expect(restored?.updatedAt, updatedAt);
    expect(await store.load('user-b'), isNull);
  });
}

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Track',
  artistName: 'Artist',
  albumTitle: 'Album',
  format: 'mp3',
  favorite: false,
);
