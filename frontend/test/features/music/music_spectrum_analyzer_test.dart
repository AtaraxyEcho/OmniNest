import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_realtime_spectrum_mapper.dart';
import 'package:omninest/features/music/application/music_spectrum_analyzer.dart';
import 'package:omninest/features/music/domain/music_models.dart';

void main() {
  const track = MusicTrack(
    id: 'track-1',
    fileNodeId: 'file-1',
    title: 'Night Drive',
    artistName: 'Omni Band',
    albumTitle: 'Unknown Album',
    durationSeconds: 180,
    format: 'flac',
    bitrate: 960,
    sampleRate: 48000,
    favorite: false,
  );

  test('silent frame keeps stable band count', () {
    final frame = MusicSpectrumFrame.silent(bandCount: 16);

    expect(frame.active, isFalse);
    expect(frame.source, MusicSpectrumSource.silent);
    expect(frame.bands, hasLength(16));
    expect(frame.energy, greaterThan(0));
  });

  test('analyzer produces active normalized spectrum bands while playing', () {
    const analyzer = MusicSpectrumAnalyzer();
    final frame = analyzer.analyze(
      track: track,
      position: const Duration(seconds: 42),
      playing: true,
      bandCount: 24,
    );

    expect(frame.active, isTrue);
    expect(frame.source, MusicSpectrumSource.estimated);
    expect(frame.confidence, inExclusiveRange(0, 1));
    expect(frame.bands, hasLength(24));
    expect(frame.energy, inInclusiveRange(0, 1));
    expect(frame.bands.every((band) => band >= 0 && band <= 1), isTrue);
  });

  test('native mapper treats incoming SoLoud data as FFT bands', () {
    final mapper = MusicRealtimeSpectrumMapper();
    final fft = Float32List(256);
    final waveform = Float32List(256);
    for (var index = 1; index < fft.length; index++) {
      final frequency = index * (track.sampleRate! / (fft.length * 2));
      if (frequency >= 52 && frequency <= 165) {
        fft[index] = 0.72;
      } else if (frequency >= 420 && frequency <= 2600) {
        fft[index] = 0.12;
      } else if (frequency >= 6000 && frequency <= 12000) {
        fft[index] = 0.05;
      } else {
        fft[index] = 0.015;
      }
    }
    for (var index = 0; index < waveform.length; index++) {
      waveform[index] = math.sin(index / waveform.length * math.pi * 2) * 0.4;
    }

    MusicSpectrumFrame frame = MusicSpectrumFrame.silent();
    for (var step = 0; step < 14; step++) {
      frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: track,
        position: Duration(milliseconds: step * 32),
      );
    }

    expect(frame.source, MusicSpectrumSource.nativeFft);
    expect(
      frame.bands,
      hasLength(MusicRealtimeSpectrumMapper.defaultBandCount),
    );
    expect(frame.bands.every((band) => band >= 0 && band <= 1), isTrue);
    expect(frame.bass, greaterThan(frame.mid));
    expect(frame.bass, greaterThan(frame.treble));
    expect(frame.energy, inInclusiveRange(0, 1));
    expect(frame.sequence, 14);
    expect(frame.capturedAtMicros, greaterThan(0));
    expect(frame.audioPosition, const Duration(milliseconds: 416));
  });

  test('native mapper keeps vocal energy out of mid beat drive', () {
    final mapper = MusicRealtimeSpectrumMapper();
    final fft = Float32List(256);
    final waveform = Float32List(256);
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 420,
      toHz: 2600,
      value: 0.82,
    );
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 3000,
      toHz: 6000,
      value: 0.035,
    );
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 52,
      toHz: 165,
      value: 0.030,
    );
    _fillWaveform(waveform, amplitude: 0.16);

    MusicSpectrumFrame frame = MusicSpectrumFrame.silent();
    for (var step = 0; step < 16; step++) {
      frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: track,
        position: Duration(milliseconds: step * 32),
      );
    }

    expect(frame.vocal, greaterThan(frame.body));
    expect(frame.vocal, greaterThan(frame.mid));
    expect(frame.lowDominance, lessThan(0.72));
    expect(frame.beat, lessThan(0.10));
  });

  test('native mapper exposes independent high frequency snap response', () {
    final mapper = MusicRealtimeSpectrumMapper();
    final fft = Float32List(256);
    final waveform = Float32List(256);
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 6000,
      toHz: 12000,
      value: 0.76,
    );
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 52,
      toHz: 165,
      value: 0.045,
    );
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 3000,
      toHz: 6000,
      value: 0.06,
    );
    _fillWaveform(waveform, amplitude: 0.22);

    MusicSpectrumFrame frame = MusicSpectrumFrame.silent();
    for (var step = 0; step < 16; step++) {
      frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: track,
        position: Duration(milliseconds: step * 32),
      );
    }

    final lowPeak = frame.bands.take(8).fold<double>(0, math.max);
    final highPeak = frame.bands.skip(20).fold<double>(0, math.max);

    expect(frame.snap, greaterThan(0.45));
    expect(frame.treble, greaterThan(frame.bass));
    expect(frame.treble, greaterThan(frame.mid));
    expect(highPeak, greaterThan(lowPeak));
  });

  test('native mapper rescales quiet shadow visualization input', () {
    final mapper = MusicRealtimeSpectrumMapper();
    final fft = Float32List(256);
    final waveform = Float32List(256);
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 52,
      toHz: 165,
      value: 0.000072,
      floor: 0.0000015,
    );
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 420,
      toHz: 2600,
      value: 0.000018,
      floor: 0.0000015,
    );
    _fillWaveform(waveform, amplitude: 0.000040);

    MusicSpectrumFrame frame = MusicSpectrumFrame.silent();
    for (var step = 0; step < 42; step++) {
      frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: track,
        position: Duration(milliseconds: step * 32),
      );
    }

    expect(frame.source, MusicSpectrumSource.nativeFft);
    expect(frame.bass, greaterThan(0.12));
    expect(frame.energy, greaterThan(0.04));
    expect(frame.bands.take(8).fold<double>(0, math.max), greaterThan(0.12));
  });

  test('native mapper responds to a bass onset in the first fresh frame', () {
    final mapper = MusicRealtimeSpectrumMapper();
    final fft = Float32List(256);
    final waveform = Float32List(256);
    var frame = MusicSpectrumFrame.silent();
    for (var step = 0; step < 12; step++) {
      frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: track,
        position: Duration(milliseconds: step * 16),
      );
    }
    final silentBass = frame.bass;
    final silentLowBand = frame.bands.take(8).fold<double>(0, math.max);
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 52,
      toHz: 190,
      value: 0.76,
      floor: 0.008,
    );
    _fillWaveform(waveform, amplitude: 0.52);

    frame = mapper.map(
      fftBins: fft,
      waveform: waveform,
      track: track,
      position: const Duration(milliseconds: 192),
    );

    expect(frame.bass, greaterThan(silentBass + 0.30));
    expect(frame.bass, greaterThan(0.36));
    expect(
      frame.bands.take(8).fold<double>(0, math.max),
      greaterThan(silentLowBand + 0.28),
    );
  });

  test(
    'missing online sample metadata does not delay the first bass frame',
    () {
      const onlineTrack = MusicTrack(
        id: 'netease:track-1',
        fileNodeId: '',
        title: 'Online Track',
        artistName: 'Online Artist',
        albumTitle: 'Online Album',
        format: 'ONLINE',
        favorite: false,
      );
      final mapper = MusicRealtimeSpectrumMapper();
      final fft = Float32List(256);
      final waveform = Float32List(256);
      for (var step = 0; step < 12; step++) {
        mapper.map(
          fftBins: fft,
          waveform: waveform,
          track: onlineTrack,
          position: Duration(milliseconds: step * 16),
        );
      }
      _fillBand(
        fft,
        sampleRate: 44100,
        fromHz: 52,
        toHz: 190,
        value: 0.76,
        floor: 0.008,
      );
      _fillWaveform(waveform, amplitude: 0.52);

      final frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: onlineTrack,
        position: const Duration(milliseconds: 192),
      );

      expect(frame.source, MusicSpectrumSource.nativeFft);
      expect(frame.bass, greaterThan(0.36));
    },
  );

  test('single high frequency spike does not collapse unrelated bands', () {
    final mapper = MusicRealtimeSpectrumMapper();
    final fft = Float32List(256);
    final waveform = Float32List(256);
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 52,
      toHz: 190,
      value: 0.48,
    );
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 3000,
      toHz: 6000,
      value: 0.18,
    );
    _fillWaveform(waveform, amplitude: 0.42);

    MusicSpectrumFrame frame = MusicSpectrumFrame.silent();
    for (var step = 0; step < 32; step++) {
      frame = mapper.map(
        fftBins: fft,
        waveform: waveform,
        track: track,
        position: Duration(milliseconds: step * 24),
      );
    }
    final lowBefore = frame.bands.take(8).fold<double>(0, math.max);
    _fillBand(
      fft,
      sampleRate: track.sampleRate!,
      fromHz: 6000,
      toHz: 15000,
      value: 0.98,
    );
    frame = mapper.map(
      fftBins: fft,
      waveform: waveform,
      track: track,
      position: const Duration(milliseconds: 768),
    );
    final lowAfter = frame.bands.take(8).fold<double>(0, math.max);

    expect(lowAfter, greaterThan(lowBefore * 0.82));
  });
}

void _fillBand(
  Float32List fft, {
  required int sampleRate,
  required double fromHz,
  required double toHz,
  required double value,
  double floor = 0.012,
}) {
  final fftSize = fft.length * 2;
  for (var index = 1; index < fft.length; index++) {
    final frequency = index * (sampleRate / fftSize);
    if (frequency >= fromHz && frequency <= toHz) {
      fft[index] = value;
    } else if (fft[index] == 0) {
      fft[index] = floor;
    }
  }
}

void _fillWaveform(Float32List waveform, {required double amplitude}) {
  for (var index = 0; index < waveform.length; index++) {
    waveform[index] =
        math.sin(index / waveform.length * math.pi * 2) * amplitude;
  }
}
