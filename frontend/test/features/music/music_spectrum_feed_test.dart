import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';

void main() {
  test('无监听者时不读原生采样，重新挂载后恢复', () {
    final player = _FakeSpectrumPlayback();
    final sampler = MusicSpectrumSampler(readFrame: player.readSpectrumFrame)
      ..setTrack(_track);
    var notifications = 0;
    void listener() => notifications++;

    sampler.addListener(listener);
    sampler.tick(elapsed: const Duration(milliseconds: 16), playing: true);
    expect(player.readCount, 1);
    expect(sampler.value.sequence, 1);
    expect(notifications, 1);

    sampler.removeListener(listener);
    sampler.tick(elapsed: const Duration(milliseconds: 48), playing: true);
    sampler.tick(elapsed: const Duration(milliseconds: 148), playing: true);
    expect(player.readCount, 1, reason: '无监听者时不应读取原生采样');
    expect(sampler.value.sequence, 1);

    sampler.addListener(listener);
    sampler.tick(elapsed: const Duration(milliseconds: 164), playing: true);
    expect(player.readCount, 2);
    expect(sampler.value.sequence, 2);
    expect(notifications, 2);
    sampler.dispose();
  });

  test('暂停时不读原生采样', () {
    final player = _FakeSpectrumPlayback();
    final sampler = MusicSpectrumSampler(readFrame: player.readSpectrumFrame)
      ..setTrack(_track);
    sampler.addListener(() {});
    sampler.tick(elapsed: const Duration(milliseconds: 16), playing: false);
    expect(player.readCount, 0);
    sampler.dispose();
  });
}

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Track',
  artistName: 'Artist',
  albumTitle: 'Album',
  format: 'FLAC',
  favorite: false,
);

class _FakeSpectrumPlayback implements MusicAudioPlayback {
  int readCount = 0;

  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState();

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  MusicAudioPlayerStreams get stream => const MusicAudioPlayerStreams(
    position: Stream<Duration>.empty(),
    duration: Stream<Duration>.empty(),
    volume: Stream<double>.empty(),
    completed: Stream<bool>.empty(),
    log: Stream<MusicAudioLog>.empty(),
  );

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) {
    readCount++;
    return MusicSpectrumFrame(
      bands: List<double>.filled(32, 0.6),
      bass: 0.7,
      mid: 0.5,
      treble: 0.4,
      energy: 0.62,
      beat: 0.5,
      active: true,
      source: MusicSpectrumSource.nativeFft,
      confidence: 0.9,
      sequence: readCount,
    );
  }

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  void setVolume(double volume) {}

  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  Future<void> dispose() async {}
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
