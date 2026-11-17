import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';

export 'package:omninest/features/music/application/music_spectrum_frame.dart';

/// 前端音乐响应分析器。
class MusicSpectrumAnalyzer {
  const MusicSpectrumAnalyzer();

  MusicSpectrumFrame analyze({
    required MusicTrack? track,
    required Duration position,
    required bool playing,
    int bandCount = 32,
  }) {
    if (!playing || track == null) {
      return MusicSpectrumFrame.silent(bandCount: bandCount);
    }
    final seconds = position.inMilliseconds / 1000.0;
    final seed = _trackSeed(track);
    final duration = math.max(track.durationSeconds ?? 180, 30);
    final progress = (seconds / duration).clamp(0.0, 1.0).toDouble();
    final tempo = 0.96 + _unit(seed + 3) * 0.62;
    final kickPhase = math.sin(seconds * math.pi * tempo + seed * 0.017);
    final beat = math.pow(kickPhase * 0.5 + 0.5, 9).toDouble();
    final bassPulse = math.sin(seconds * (1.42 + _unit(seed + 7) * 0.54)).abs();
    final vocalWave = math.sin(seconds * 2.70 + seed * 0.011) * 0.5 + 0.5;
    final shimmer =
        math.sin(seconds * 8.8 + seed * 0.013).abs() * 0.65 +
        math.sin(seconds * 14.2 + seed * 0.019).abs() * 0.35;
    final density = _qualityDensity(track);
    final bass = _clampUnit(
      0.12 + bassPulse * 0.24 + beat * 0.36 + density * 0.06,
    );
    final mid = _clampUnit(0.14 + vocalWave * 0.28 + density * 0.04);
    final treble = _clampUnit(0.08 + shimmer * 0.26 + beat * 0.05);
    final energy = _clampUnit(bass * 0.48 + mid * 0.34 + treble * 0.18);
    final bands = List<double>.generate(bandCount, (index) {
      final p = bandCount <= 1 ? 0.0 : index / (bandCount - 1);
      final lowWeight = math.exp(-math.pow(p / 0.34, 2)).toDouble();
      final midWeight = math.exp(-math.pow((p - 0.48) / 0.28, 2)).toDouble();
      final highWeight = math.exp(-math.pow((p - 0.90) / 0.26, 2)).toDouble();
      final phase = seed * 0.021 + index * 0.73;
      final bandMotion =
          math.sin(seconds * (1.4 + p * 5.8) + phase).abs() * 0.62 +
          math.sin(seconds * (5.6 + p * 8.4) + phase * 0.47).abs() * 0.38;
      final breathing = 0.76 + math.sin(progress * math.pi) * 0.16;
      return _clampUnit(
        0.06 +
            breathing *
                bandMotion *
                (bass * lowWeight + mid * midWeight + treble * highWeight) +
            beat * lowWeight * 0.22,
      );
    });
    return MusicSpectrumFrame(
      bands: bands,
      bass: bass,
      mid: mid,
      treble: treble,
      energy: energy,
      beat: beat,
      active: true,
      source: MusicSpectrumSource.estimated,
      confidence: 0.38,
      low: bass,
      body: (bass * 0.36 + mid * 0.28).clamp(0.0, 1.0).toDouble(),
      vocal: mid,
      snap: treble,
      lowDominance:
          (bass / math.max(0.08, mid * 0.90 + treble * 0.18))
              .clamp(0.0, 2.0)
              .toDouble(),
      beatConfidence: beat,
    );
  }

  int _trackSeed(MusicTrack track) {
    var hash = 17;
    for (final unit
        in '${track.id}:${track.title}:${track.artistName}'.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + unit);
    }
    return hash;
  }

  double _qualityDensity(MusicTrack track) {
    final bitrate = track.bitrate ?? 192;
    final sampleRate = track.sampleRate ?? 44100;
    final bitFactor = (bitrate / 320).clamp(0.0, 1.2).toDouble();
    final sampleFactor = (sampleRate / 48000).clamp(0.0, 1.2).toDouble();
    return _clampUnit((bitFactor + sampleFactor) / 2);
  }

  double _unit(int seed) {
    final value = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return value - value.floorToDouble();
  }

  double _clampUnit(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }
}

final musicSpectrumAnalyzerProvider = Provider<MusicSpectrumAnalyzer>((ref) {
  return const MusicSpectrumAnalyzer();
});

/// 当前播放会话拥有的高频视觉数据源。
final musicSpectrumFeedProvider =
    Provider.autoDispose<ValueListenable<MusicSpectrumFrame>>((ref) {
      final player = ref.watch(
        musicPlaybackSessionProvider.select((session) => session.player),
      );
      return player.spectrum;
    });

/// 兼容需要使用 StreamProvider 的非高频消费方。
final musicSpectrumFrameProvider =
    StreamProvider.autoDispose<MusicSpectrumFrame>((ref) async* {
      final feed = ref.watch(musicSpectrumFeedProvider);
      yield feed.value;
      final controller = StreamController<MusicSpectrumFrame>();
      void listener() => controller.add(feed.value);
      feed.addListener(listener);
      ref.onDispose(() {
        feed.removeListener(listener);
        unawaited(controller.close());
      });
      yield* controller.stream;
    });
