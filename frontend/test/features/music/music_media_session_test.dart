import 'dart:async';

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
      artResolver: _fileUriResolver,
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
    await pumpEventQueue();

    final mediaItem = handler.mediaItem.value;
    expect(mediaItem?.title, 'Media Track');
    expect(mediaItem?.artist, 'Media Artist');
    expect(mediaItem?.album, 'Media Album');
    expect(mediaItem?.duration, const Duration(seconds: 245));
    // 系统侧只按文件路径解码封面，地址必须是落盘后的 file URI 而非网络地址。
    expect(mediaItem?.artUri, Uri.file('/tmp/cover.jpg'));

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

  test('封面解析未完成前不下发地址，完成后补投同一曲目', () async {
    final pending = Completer<Uri?>();
    final handler = _handler(artResolver: (_) => pending.future);

    await handler.updateNowPlaying(
      track: _track,
      playing: true,
      position: Duration.zero,
      duration: const Duration(seconds: 245),
    );
    expect(handler.mediaItem.value?.artUri, isNull);

    pending.complete(Uri.file('/tmp/cover.jpg'));
    await pumpEventQueue();
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/cover.jpg'));
    expect(handler.mediaItem.value?.title, 'Media Track');
  });

  test('切歌后迟到的封面解析不得覆盖新曲目', () async {
    final completers = <String, Completer<Uri?>>{};
    final handler = _handler(
      artResolver: (url) => (completers[url] ??= Completer<Uri?>()).future,
    );
    final emitted = <MediaItem?>[];
    final subscription = handler.mediaItem.listen(emitted.add);
    addTearDown(subscription.cancel);

    await handler.updateNowPlaying(
      track: _track,
      playing: true,
      position: Duration.zero,
      duration: const Duration(seconds: 245),
    );
    await handler.updateNowPlaying(
      track: _otherTrack,
      playing: true,
      position: Duration.zero,
      duration: const Duration(seconds: 200),
    );
    final emittedBefore = emitted.length;

    completers[_track.listCoverUrl!]!.complete(Uri.file('/tmp/stale.jpg'));
    await pumpEventQueue();

    // 迟到的旧封面只能丢弃：当前曲目仍是 _otherTrack，且不得再触发一次
    // 系统元数据更新（Android 侧每次 mediaItem 投递都会重建通知）。
    expect(handler.mediaItem.value?.title, 'Other Track');
    expect(handler.mediaItem.value?.artUri, isNull);
    expect(emitted, hasLength(emittedBefore));
  });

  test('同一封面的重复进度同步不重复解析', () async {
    final resolved = <String>[];
    final pending = Completer<Uri?>();
    final handler = _handler(
      artResolver: (url) async {
        resolved.add(url);
        return pending.future;
      },
    );

    for (var i = 0; i < 3; i++) {
      await handler.updateNowPlaying(
        track: _track,
        playing: true,
        position: Duration(seconds: i),
        duration: const Duration(seconds: 245),
      );
    }
    expect(resolved, hasLength(1));

    pending.complete(Uri.file('/tmp/cover.jpg'));
    await pumpEventQueue();
    expect(resolved, [_track.listCoverUrl]);
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/cover.jpg'));
  });

  test('封面解析失败不影响元数据与播放状态', () async {
    final handler = _handler(
      artResolver: (_) async => throw StateError('unreachable'),
    );

    await handler.updateNowPlaying(
      track: _track,
      playing: true,
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 245),
    );
    await pumpEventQueue();

    expect(handler.mediaItem.value?.title, 'Media Track');
    expect(handler.mediaItem.value?.artUri, isNull);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });
}

const MusicTrack _otherTrack = MusicTrack(
  id: 'track-2',
  fileNodeId: 'file-2',
  title: 'Other Track',
  artistName: 'Other Artist',
  albumTitle: 'Other Album',
  format: 'flac',
  favorite: false,
  durationSeconds: 200,
  coverUrl: 'https://example.com/other.jpg',
);

Future<Uri?> _fileUriResolver(String url) async => Uri.file('/tmp/cover.jpg');

MusicMediaSessionHandler _handler({
  required Future<Uri?> Function(String url) artResolver,
}) {
  return MusicMediaSessionHandler(
    artResolver: artResolver,
    callbacks: MusicMediaCommandCallbacks(
      onPlay: () async {},
      onPause: () async {},
      onNext: () async {},
      onPrevious: () async {},
      onPlayPauseToggle: () async {},
      onSeek: (_) async {},
    ),
  );
}
