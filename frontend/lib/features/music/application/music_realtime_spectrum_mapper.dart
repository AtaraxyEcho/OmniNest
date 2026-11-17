import 'dart:math' as math;
import 'dart:typed_data';

import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 音乐实时频谱映射器。
class MusicRealtimeSpectrumMapper {
  static const int defaultBandCount = 32;
  static const double _minimumFrequency = 38;
  static const double _maximumFrequency = 16000;

  double _bassPeak = 0.030;
  double _midPeak = 0.026;
  double _treblePeak = 0.018;
  double _energyPeak = 0.030;
  double _previousEnergy = 0;
  double _smoothBass = 0;
  double _smoothMid = 0;
  double _smoothTreble = 0;
  double _smoothEnergy = 0;
  double _inputGain = 1;
  double _beatPulse = 0;
  double _lastHitAtSeconds = -999;
  int _sequence = 0;
  DateTime? _lastFrameAt;
  Duration? _lastAudioPosition;
  List<double> _smoothedBands = const <double>[];
  List<double> _bandPeaks = const <double>[];
  List<double> _bandNoiseFloors = const <double>[];
  final _RealtimeBeatState _beatState = _RealtimeBeatState();

  /// 将原生 FFT 与波形采样映射为视觉可用的频谱帧。
  MusicSpectrumFrame map({
    required Float32List fftBins,
    required Float32List waveform,
    required MusicTrack track,
    required Duration position,
    int bandCount = defaultBandCount,
  }) {
    final sampleRate = math.max(track.sampleRate ?? 44100, 8000).toInt();
    final now = DateTime.now();
    final previousPosition = _lastAudioPosition;
    final positionDelta =
        previousPosition == null ? Duration.zero : position - previousPosition;
    final wallDelta =
        _lastFrameAt == null
            ? 1 / 60
            : now.difference(_lastFrameAt!).inMicroseconds /
                Duration.microsecondsPerSecond;
    final audioDelta =
        positionDelta > Duration.zero &&
                positionDelta <= const Duration(milliseconds: 120)
            ? positionDelta.inMicroseconds / Duration.microsecondsPerSecond
            : wallDelta;
    final dt = audioDelta.clamp(0.001, 0.080).toDouble();
    _lastFrameAt = now;
    _lastAudioPosition = position;

    final maxFrequency = math.min(_maximumFrequency, sampleRate / 2);
    final kickRaw = _bandAverage(fftBins, sampleRate, 60, 190);
    final vocalRaw = _bandAverage(fftBins, sampleRate, 200, 3000);
    final middleRaw = _bandAverage(fftBins, sampleRate, 3000, 6000);
    final highRaw = _bandAverage(fftBins, sampleRate, 6000, maxFrequency);
    final rmsRaw = _waveformRms(waveform, fftBins);
    final targetGain = _resolveInputGain(
      kick: kickRaw,
      vocal: vocalRaw,
      middle: middleRaw,
      high: highRaw,
      rms: rmsRaw,
    );
    _inputGain = _follow(_inputGain, targetGain, 0.020, 0.180, dt);
    final kick = _scaleNativeValue(kickRaw, _inputGain);
    final vocal = _scaleNativeValue(vocalRaw, _inputGain);
    final middle = _scaleNativeValue(middleRaw, _inputGain);
    final high = _scaleNativeValue(highRaw, _inputGain);
    final rms = _scaleNativeValue(rmsRaw, _inputGain);

    _bassPeak = math.max(_bassPeak * math.pow(0.994, dt * 60), kick);
    _midPeak = math.max(_midPeak * math.pow(0.993, dt * 60), middle);
    _treblePeak = math.max(_treblePeak * math.pow(0.992, dt * 60), high);
    _energyPeak = math.max(_energyPeak * math.pow(0.995, dt * 60), rms);

    final rb = _normalizedBand(
      kick,
      floor: 0.088,
      peak: _bassPeak,
      peakScale: 0.66,
      exponent: 0.78,
    );
    final rm = _normalizedBand(
      middle,
      floor: 0.084,
      peak: _midPeak,
      peakScale: 0.70,
      exponent: 0.86,
    );
    final rt = _normalizedBand(
      high,
      floor: 0.074,
      peak: _treblePeak,
      peakScale: 0.74,
      exponent: 0.92,
    );
    final re = _normalizedBand(
      rms,
      floor: 0.060,
      peak: _energyPeak,
      peakScale: 0.68,
      exponent: 0.82,
    );

    final bassOnset = math.max(0.0, rb - _smoothBass);
    final energyOnset = math.max(0.0, re - _previousEnergy);
    _previousEnergy = _previousEnergy * 0.88 + re * 0.12;

    final beat = _processBeat(
      fftBins: fftBins,
      waveform: waveform,
      sampleRate: sampleRate,
      positionSeconds: position.inMilliseconds / 1000.0,
      dt: dt,
      inputGain: _inputGain,
      rb: rb,
      bassOnset: bassOnset,
      energyOnset: energyOnset,
    );
    if (beat.hit) {
      _beatPulse = math.max(_beatPulse, beat.strength);
    } else if (bassOnset > 0.075 && rb > 0.32 && energyOnset > 0.020) {
      _beatPulse = math.max(_beatPulse, math.min(0.12, bassOnset * 0.18));
    }
    _beatPulse *= math.pow(0.36, dt);

    _smoothBass = _follow(
      _smoothBass,
      math.min(0.82, rb * 0.78 + re * 0.025),
      0.012,
      0.120,
      dt,
    );
    _smoothMid = _follow(
      _smoothMid,
      math.min(0.68, rm * 0.64 + re * 0.025),
      0.014,
      0.105,
      dt,
    );
    _smoothTreble = _follow(
      _smoothTreble,
      math.min(0.78, rt * 0.72),
      0.008,
      0.075,
      dt,
    );
    _smoothEnergy = _follow(
      _smoothEnergy,
      math.min(0.72, re),
      0.012,
      0.120,
      dt,
    );

    final bass = math.min(0.90, _smoothBass * 1.05 + _beatPulse * 0.18);
    final mid = math.min(0.72, _smoothMid * 1.12);
    final treble = math.min(0.84, _smoothTreble * 1.18);
    final energy = math.max(_smoothEnergy, _beatPulse * 0.30);
    final bands = _mapBands(
      fftBins: fftBins,
      sampleRate: sampleRate,
      maxFrequency: maxFrequency,
      bandCount: bandCount,
      bass: bass,
      mid: mid,
      treble: treble,
      beat: _beatPulse,
      inputGain: _inputGain,
      dt: dt,
    );
    return MusicSpectrumFrame(
      bands: bands,
      bass: bass.clamp(0.0, 1.0).toDouble(),
      mid: mid.clamp(0.0, 1.0).toDouble(),
      treble: treble.clamp(0.0, 1.0).toDouble(),
      energy: energy.clamp(0.0, 1.0).toDouble(),
      beat: _beatPulse.clamp(0.0, 1.0).toDouble(),
      active: true,
      source: MusicSpectrumSource.nativeFft,
      confidence: (0.72 + beat.confidence * 0.24).clamp(0.0, 1.0).toDouble(),
      low: beat.low,
      body: beat.body,
      vocal: vocal.clamp(0.0, 1.0).toDouble(),
      snap: beat.snap,
      lowDominance: beat.lowDominance,
      beatConfidence: beat.confidence,
      sequence: ++_sequence,
      capturedAtMicros: now.microsecondsSinceEpoch,
      audioPosition: position,
    );
  }

  /// 重置动态峰值、包络与节拍状态。
  void reset() {
    _bassPeak = 0.030;
    _midPeak = 0.026;
    _treblePeak = 0.018;
    _energyPeak = 0.030;
    _previousEnergy = 0;
    _smoothBass = 0;
    _smoothMid = 0;
    _smoothTreble = 0;
    _smoothEnergy = 0;
    _inputGain = 1;
    _beatPulse = 0;
    _lastHitAtSeconds = -999;
    _sequence = 0;
    _lastFrameAt = null;
    _lastAudioPosition = null;
    _smoothedBands = const <double>[];
    _bandPeaks = const <double>[];
    _bandNoiseFloors = const <double>[];
    _beatState.reset();
  }

  _BeatResult _processBeat({
    required Float32List fftBins,
    required Float32List waveform,
    required int sampleRate,
    required double positionSeconds,
    required double dt,
    required double inputGain,
    required double rb,
    required double bassOnset,
    required double energyOnset,
  }) {
    final sub = _scaleNativeValue(
      _bandRms(fftBins, sampleRate, 35, 110),
      inputGain,
    );
    final kick = _scaleNativeValue(
      _bandRms(fftBins, sampleRate, 65, 190),
      inputGain,
    );
    final body = _scaleNativeValue(
      _bandRms(fftBins, sampleRate, 190, 420),
      inputGain,
    );
    final vocal = _scaleNativeValue(
      _bandRms(fftBins, sampleRate, 420, 2600),
      inputGain,
    );
    final snap = _scaleNativeValue(
      _bandRms(fftBins, sampleRate, 1800, 9200),
      inputGain,
    );
    final low = math.min(1.0, kick * 0.86 + sub * 0.42);
    final rms = _scaleNativeValue(_waveformRms(waveform, fftBins), inputGain);

    _beatState.subFast = _follow(_beatState.subFast, sub, 0.018, 0.064, dt);
    _beatState.subSlow = _follow(_beatState.subSlow, sub, 0.320, 0.520, dt);
    _beatState.lowFast = _follow(_beatState.lowFast, low, 0.016, 0.070, dt);
    _beatState.lowSlow = _follow(_beatState.lowSlow, low, 0.300, 0.540, dt);
    _beatState.bodyFast = _follow(_beatState.bodyFast, body, 0.020, 0.082, dt);
    _beatState.bodySlow = _follow(_beatState.bodySlow, body, 0.360, 0.600, dt);
    _beatState.vocalFast = _follow(
      _beatState.vocalFast,
      vocal,
      0.026,
      0.090,
      dt,
    );
    _beatState.vocalSlow = _follow(
      _beatState.vocalSlow,
      vocal,
      0.340,
      0.580,
      dt,
    );
    _beatState.snapFast = _follow(_beatState.snapFast, snap, 0.012, 0.060, dt);
    _beatState.snapSlow = _follow(_beatState.snapSlow, snap, 0.300, 0.520, dt);

    _trackBeatPeaks(
      sub: sub,
      low: low,
      body: body,
      vocal: vocal,
      snap: snap,
      dt: dt,
    );

    final subFlux = math.max(0.0, sub - _beatState.previousSub);
    final lowFlux = math.max(0.0, low - _beatState.previousLow);
    final bodyFlux = math.max(0.0, body - _beatState.previousBody);
    final vocalFlux = math.max(0.0, vocal - _beatState.previousVocal);
    final snapFlux = math.max(0.0, snap - _beatState.previousSnap);
    final rmsFlux = math.max(0.0, rms - _beatState.previousRms);
    final subRise = math.max(0.0, _beatState.subFast - _beatState.subSlow);
    final lowRise = math.max(0.0, _beatState.lowFast - _beatState.lowSlow);
    final bodyRise = math.max(0.0, _beatState.bodyFast - _beatState.bodySlow);
    final vocalRise = math.max(
      0.0,
      _beatState.vocalFast - _beatState.vocalSlow,
    );
    final snapRise = math.max(0.0, _beatState.snapFast - _beatState.snapSlow);
    final drumOnset =
        subRise * 0.88 + subFlux * 0.66 + lowRise * 1.62 + lowFlux * 1.34;
    final musicalOnset =
        bodyRise * 0.34 +
        bodyFlux * 0.24 +
        vocalRise * 0.52 +
        vocalFlux * 0.36 +
        snapRise * 0.08 +
        snapFlux * 0.06 +
        rmsFlux * 0.20;
    final onset = drumOnset + musicalOnset * 0.16;
    final avgTau = onset > _beatState.onsetAverage ? 1.10 : 0.34;
    _beatState.onsetAverage = _follow(
      _beatState.onsetAverage,
      onset,
      avgTau,
      avgTau,
      dt,
    );
    _beatState.onsetPeak = math.max(
      _beatState.onsetPeak * math.pow(0.988, dt * 60),
      math.max(onset, 0.032),
    );
    final floor = _beatState.onsetAverage * 0.84;
    final score =
        ((onset - floor) / math.max(0.014, _beatState.onsetPeak - floor))
            .clamp(0.0, 1.0)
            .toDouble();
    final subNorm = _normalizePeak(sub, _beatState.subPeak, 0.045, 0.70);
    final lowNorm = _normalizePeak(low, _beatState.lowPeak, 0.060, 0.72);
    final bodyNorm = _normalizePeak(body, _beatState.bodyPeak, 0.045, 0.72);
    final vocalNorm = _normalizePeak(vocal, _beatState.vocalPeak, 0.045, 0.72);
    final snapNorm = _normalizePeak(snap, _beatState.snapPeak, 0.040, 0.72);
    _beatState.primedFrames++;

    final warmingUp = positionSeconds < 0.16 || _beatState.primedFrames < 10;
    final gap = positionSeconds - _lastHitAtSeconds;
    final lowPresence = math.max(lowNorm, subNorm * 0.74);
    final lowAttack =
        lowRise + lowFlux * 0.72 + subRise * 0.58 + subFlux * 0.40;
    final lowDominance =
        low / math.max(0.001, vocal * 0.84 + body * 0.36 + snap * 0.10);
    final lowFluxDominance =
        (lowFlux + subFlux * 0.58) /
        math.max(0.001, vocalFlux * 0.72 + bodyFlux * 0.42 + snapFlux * 0.16);
    final voiceMask =
        vocalNorm > 0.58 && lowDominance < 0.86 && lowFluxDominance < 1.10;
    var drumGate =
        lowPresence > 0.38 &&
        lowAttack > math.max(0.014, _beatState.onsetAverage * 0.34) &&
        !voiceMask;
    drumGate =
        drumGate &&
        (lowDominance > 0.72 || lowFluxDominance > 1.02 || subNorm > 0.56);
    final strongTransient =
        drumGate && score > 0.54 && drumOnset > _beatState.onsetAverage * 0.84;
    final kickTransient =
        drumGate &&
        score > 0.40 &&
        lowAttack > math.max(0.018, _beatState.onsetAverage * 0.46);
    var hit = (strongTransient || kickTransient) && !warmingUp;
    if (hit && gap < 0.220) {
      hit = false;
    }

    _beatState.previousSub = sub;
    _beatState.previousLow = low;
    _beatState.previousBody = body;
    _beatState.previousVocal = vocal;
    _beatState.previousSnap = snap;
    _beatState.previousRms = rms;
    final confidence =
        (score * 0.44 +
                lowPresence * 0.30 +
                math.min(1.0, lowDominance / 1.25) * 0.18 +
                (voiceMask ? 0 : 0.08))
            .clamp(0.0, 1.0)
            .toDouble();
    if (!hit) {
      return _BeatResult(
        hit: false,
        strength: 0,
        low: lowNorm,
        body: bodyNorm,
        vocal: vocalNorm,
        snap: snapNorm,
        lowDominance: lowDominance.clamp(0.0, 2.0).toDouble(),
        confidence: confidence,
      );
    }
    _lastHitAtSeconds = positionSeconds;
    final strength =
        (0.24 +
                score * 0.36 +
                lowPresence * 0.34 +
                math.min(1.25, lowDominance) * 0.07 +
                rmsFlux * 0.95 +
                bassOnset * 0.20 +
                energyOnset * 0.16)
            .clamp(0.0, 1.0)
            .toDouble();
    return _BeatResult(
      hit: true,
      strength: strength,
      low: lowNorm,
      body: bodyNorm,
      vocal: vocalNorm,
      snap: snapNorm,
      lowDominance: lowDominance.clamp(0.0, 2.0).toDouble(),
      confidence: math.max(confidence, strength * 0.72),
    );
  }

  void _trackBeatPeaks({
    required double sub,
    required double low,
    required double body,
    required double vocal,
    required double snap,
    required double dt,
  }) {
    _beatState.subPeak = math.max(
      _beatState.subPeak * math.pow(0.990, dt * 60),
      math.max(sub, 0.045),
    );
    _beatState.lowPeak = math.max(
      _beatState.lowPeak * math.pow(0.989, dt * 60),
      math.max(low, 0.060),
    );
    _beatState.bodyPeak = math.max(
      _beatState.bodyPeak * math.pow(0.990, dt * 60),
      math.max(body, 0.040),
    );
    _beatState.vocalPeak = math.max(
      _beatState.vocalPeak * math.pow(0.990, dt * 60),
      math.max(vocal, 0.040),
    );
    _beatState.snapPeak = math.max(
      _beatState.snapPeak * math.pow(0.990, dt * 60),
      math.max(snap, 0.035),
    );
  }

  List<double> _mapBands({
    required Float32List fftBins,
    required int sampleRate,
    required double maxFrequency,
    required int bandCount,
    required double bass,
    required double mid,
    required double treble,
    required double beat,
    required double inputGain,
    required double dt,
  }) {
    final rawBands = List<double>.generate(bandCount, (index) {
      final startFrequency = _logFrequency(index / bandCount, maxFrequency);
      final endFrequency = _logFrequency((index + 1) / bandCount, maxFrequency);
      return _scaleNativeValue(
        _bandAverage(fftBins, sampleRate, startFrequency, endFrequency),
        inputGain,
      );
    }, growable: false);
    if (_smoothedBands.length != bandCount) {
      _smoothedBands = List<double>.filled(bandCount, 0);
      _bandPeaks = List<double>.filled(bandCount, 0.012);
      _bandNoiseFloors = List<double>.filled(bandCount, 0.004);
    }
    final nextBands = List<double>.generate(bandCount, (index) {
      final progress = bandCount <= 1 ? 0.0 : index / (bandCount - 1);
      final raw = rawBands[index];
      final previousFloor = _bandNoiseFloors[index];
      final floorTau = raw < previousFloor ? 0.30 : 8.0;
      final nextFloor =
          _follow(
            previousFloor,
            raw,
            floorTau,
            floorTau,
            dt,
          ).clamp(0.000001, math.max(0.000001, raw * 0.72)).toDouble();
      _bandNoiseFloors[index] = nextFloor;
      final clean = math.max(0.0, raw - nextFloor * 1.10);
      final nextPeak = math.max(
        _bandPeaks[index] * math.pow(0.994, dt * 60),
        math.max(clean, 0.008),
      );
      _bandPeaks[index] = nextPeak;
      final normalized =
          math
              .pow(
                (clean / math.max(0.008, nextPeak * 0.72)).clamp(0.0, 1.0),
                0.82,
              )
              .toDouble();
      final lowWeight = math.exp(-math.pow(progress / 0.34, 2)).toDouble();
      final midWeight =
          math.exp(-math.pow((progress - 0.48) / 0.30, 2)).toDouble();
      final highWeight =
          math.exp(-math.pow((progress - 0.88) / 0.34, 2)).toDouble();
      final musicalDrive =
          bass * lowWeight * 0.34 +
          mid * midWeight * 0.30 +
          treble * highWeight * 0.24 +
          beat * lowWeight * 0.16;
      final target =
          (normalized * 0.54 + musicalDrive).clamp(0.0, 1.0).toDouble();
      return _follow(
        _smoothedBands[index],
        target,
        0.006,
        0.072,
        dt,
      ).clamp(0.0, 1.0).toDouble();
    }, growable: false);
    _smoothedBands = nextBands;
    return nextBands;
  }

  double _bandAverage(
    Float32List bins,
    int sampleRate,
    double startFrequency,
    double endFrequency,
  ) {
    final range = _binRange(bins, sampleRate, startFrequency, endFrequency);
    var total = 0.0;
    var count = 0;
    for (var index = range.start; index <= range.end; index++) {
      total += bins[index].abs();
      count++;
    }
    return count == 0 ? 0 : total / count;
  }

  double _bandRms(
    Float32List bins,
    int sampleRate,
    double startFrequency,
    double endFrequency,
  ) {
    final range = _binRange(bins, sampleRate, startFrequency, endFrequency);
    var total = 0.0;
    var count = 0;
    for (var index = range.start; index <= range.end; index++) {
      final value = bins[index].abs();
      total += value * value;
      count++;
    }
    return count == 0 ? 0 : math.sqrt(total / count);
  }

  _BinRange _binRange(
    Float32List bins,
    int sampleRate,
    double startFrequency,
    double endFrequency,
  ) {
    if (bins.isEmpty) {
      return const _BinRange(start: 0, end: -1);
    }
    final fftSize = bins.length * 2;
    final binHz = sampleRate / fftSize;
    final start =
        math
            .max(1, (startFrequency / binHz).ceil())
            .clamp(0, bins.length - 1)
            .toInt();
    final end =
        math
            .max(start, (endFrequency / binHz).ceil() - 1)
            .clamp(0, bins.length - 1)
            .toInt();
    return _BinRange(start: start, end: end);
  }

  double _waveformRms(Float32List waveform, Float32List fftBins) {
    final source = waveform.isNotEmpty ? waveform : fftBins;
    if (source.isEmpty) {
      return 0;
    }
    var total = 0.0;
    for (final value in source) {
      total += value * value;
    }
    return math.sqrt(total / source.length).clamp(0.0, 1.0).toDouble();
  }

  double _normalizedBand(
    double value, {
    required double floor,
    required double peak,
    required double peakScale,
    required double exponent,
  }) {
    final divisor = math.max(floor, peak * peakScale);
    return math.pow(value / divisor, exponent).clamp(0.0, 1.0).toDouble();
  }

  double _resolveInputGain({
    required double kick,
    required double vocal,
    required double middle,
    required double high,
    required double rms,
  }) {
    final peak = <double>[
      kick,
      vocal,
      middle,
      high,
      rms,
    ].fold<double>(0, math.max);
    if (peak <= 0.0000001) {
      return 1;
    }
    return (0.075 / peak).clamp(1.0, 1400.0).toDouble();
  }

  double _scaleNativeValue(double value, double gain) {
    return (value * gain).clamp(0.0, 1.0).toDouble();
  }

  double _normalizePeak(
    double value,
    double peak,
    double floor,
    double peakScale,
  ) {
    return (value / math.max(floor, peak * peakScale))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _follow(
    double current,
    double next,
    double upTau,
    double downTau,
    double dt,
  ) {
    final tau = next > current ? upTau : downTau;
    final amount = 1 - math.exp(-dt / math.max(0.001, tau));
    return current + (next - current) * amount;
  }

  double _logFrequency(double progress, double maxFrequency) {
    final minFrequency = math.min(_minimumFrequency, maxFrequency * 0.5);
    final ratio = maxFrequency / math.max(minFrequency, 1);
    return (minFrequency * math.pow(ratio, progress.clamp(0.0, 1.0)))
        .toDouble();
  }
}

class _RealtimeBeatState {
  double subFast = 0;
  double subSlow = 0;
  double lowFast = 0;
  double lowSlow = 0;
  double bodyFast = 0;
  double bodySlow = 0;
  double vocalFast = 0;
  double vocalSlow = 0;
  double snapFast = 0;
  double snapSlow = 0;
  double subPeak = 0.045;
  double lowPeak = 0.060;
  double bodyPeak = 0.040;
  double vocalPeak = 0.040;
  double snapPeak = 0.035;
  double previousSub = 0;
  double previousLow = 0;
  double previousBody = 0;
  double previousVocal = 0;
  double previousSnap = 0;
  double previousRms = 0;
  double onsetAverage = 0;
  double onsetPeak = 0.032;
  int primedFrames = 0;

  void reset() {
    subFast = 0;
    subSlow = 0;
    lowFast = 0;
    lowSlow = 0;
    bodyFast = 0;
    bodySlow = 0;
    vocalFast = 0;
    vocalSlow = 0;
    snapFast = 0;
    snapSlow = 0;
    subPeak = 0.045;
    lowPeak = 0.060;
    bodyPeak = 0.040;
    vocalPeak = 0.040;
    snapPeak = 0.035;
    previousSub = 0;
    previousLow = 0;
    previousBody = 0;
    previousVocal = 0;
    previousSnap = 0;
    previousRms = 0;
    onsetAverage = 0;
    onsetPeak = 0.032;
    primedFrames = 0;
  }
}

class _BeatResult {
  const _BeatResult({
    required this.hit,
    required this.strength,
    required this.low,
    required this.body,
    required this.vocal,
    required this.snap,
    required this.lowDominance,
    required this.confidence,
  });

  final bool hit;
  final double strength;
  final double low;
  final double body;
  final double vocal;
  final double snap;
  final double lowDominance;
  final double confidence;
}

class _BinRange {
  const _BinRange({required this.start, required this.end});

  final int start;
  final int end;
}
