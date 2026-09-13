import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_media_session.dart';
import 'package:omninest/features/music/domain/music_models.dart';

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Media Track',
  artistName: 'Media Artist',
  albumTitle: 'Media Album',
  format: 'flac',
  favorite: false,
  durationSeconds: 245,
  coverUrl: 'https://example.com/cover.jpg',
);

void main() {
  test('updateNowPlaying 发布元数据与 ready 播放状态', () async {
    var playCalls = 0;
    var pauseCalls = 0;
    var nextCalls = 0;
    var previousCalls = 0;
    final handler = MusicMediaSessionHandler(
      callbacks: MusicMediaCommandCallbacks(
        onPlay: () async => playCalls++,
        onPause: () async => pauseCalls++,
        onNext: () async => nextCalls++,
        onPrevious: () async => previousCalls++,
        onPlayPauseToggle: () async {},
        onSeek: (_) async {},
      ),
    );

    await handler.updateNowPlaying(
      track: _track,
      playing: true,
      position: const Duration(seconds: 42),
      duration: const Duration(seconds: 245),
    );

    final mediaItem = handler.mediaItem.value;
    expect(mediaItem?.title, 'Media Track');
    expect(mediaItem?.artist, 'Media Artist');
    expect(mediaItem?.album, 'Media Album');
    expect(mediaItem?.duration, const Duration(seconds: 245));
    expect(mediaItem?.artUri, Uri.parse('https://example.com/cover.jpg'));

    final playbackState = handler.playbackState.value;
    expect(playbackState.playing, isTrue);
    expect(playbackState.processingState, AudioProcessingState.ready);
    expect(playbackState.updatePosition, const Duration(seconds: 42));

    await handler.play();
    await handler.pause();
    await handler.skipToNext();
    await handler.skipToPrevious();
    expect(playCalls, 1);
    expect(pauseCalls, 1);
    expect(nextCalls, 1);
    expect(previousCalls, 1);
  });

  test('updateNowPlaying without track reports idle and paused', () async {
    final handler = MusicMediaSessionHandler(
      callbacks: MusicMediaCommandCallbacks(
        onPlay: () async {},
        onPause: () async {},
        onNext: () async {},
        onPrevious: () async {},
        onPlayPauseToggle: () async {},
        onSeek: (_) async {},
      ),
    );

    await handler.updateNowPlaying(
      track: null,
      playing: false,
      position: Duration.zero,
      duration: Duration.zero,
    );

    expect(handler.mediaItem.value, isNull);
    final playbackState = handler.playbackState.value;
    expect(playbackState.playing, isFalse);
    expect(playbackState.processingState, AudioProcessingState.idle);
  });
}
