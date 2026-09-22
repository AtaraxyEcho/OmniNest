import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:omninest/features/music/application/music_realtime_spectrum_mapper.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 音乐播放状态。
class MusicAudioPlayerState {
  const MusicAudioPlayerState({
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.speed = 1,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final double speed;

  MusicAudioPlayerState copyWith({
    bool? playing,
    Duration? position,
    Duration? duration,
    double? volume,
    double? speed,
  }) {
    return MusicAudioPlayerState(
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
    );
  }
}

/// 音乐播放事件流。
class MusicAudioPlayerStreams {
  const MusicAudioPlayerStreams({
    required this.position,
    required this.duration,
    required this.volume,
    required this.completed,
    required this.log,
  });

  final Stream<Duration> position;
  final Stream<Duration> duration;
  final Stream<double> volume;
  final Stream<bool> completed;
  final Stream<MusicAudioLog> log;
}

/// 音乐播放日志。
class MusicAudioLog {
  const MusicAudioLog(this.text, {this.playbackFailure = false});

  final String text;
  final bool playbackFailure;
}

/// 跨平台音乐播放与同源频谱接口。
abstract interface class MusicAudioPlayback {
  MusicAudioPlayerState get state;

  MusicAudioPlayerStreams get stream;

  ValueListenable<MusicSpectrumFrame> get spectrum;

  Future<void> openUrl(String url, {required bool play});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  void setVolume(double volume);

  /// 设置相对播放速度（1.0 为原速），实现不支持时静默忽略。
  void setRelativePlaySpeed(double speed);

  void setSpectrumTrack(MusicTrack? track);

  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track});

  Future<void> dispose();
}

/// SoLoud 音乐播放器。
class MusicAudioPlayer implements MusicAudioPlayback {
  MusicAudioPlayer({
    SoLoud? soLoud,
    MusicRealtimeSpectrumMapper? spectrumMapper,
  }) : _soLoud = soLoud ?? SoLoud.instance,
       _spectrumMapper = spectrumMapper ?? MusicRealtimeSpectrumMapper();

  static const Duration _tickInterval = Duration(milliseconds: 16);
  static const Duration _completionTolerance = Duration(milliseconds: 180);

  final SoLoud _soLoud;
  final MusicRealtimeSpectrumMapper _spectrumMapper;
  late final MusicSpectrumSampler _spectrumSampler = MusicSpectrumSampler(
    readFrame: readSpectrumFrame,
  );
  final Stopwatch _spectrumClock = Stopwatch()..start();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: _durationController.stream,
    volume: _volumeController.stream,
    completed: _completedController.stream,
    log: _logController.stream,
  );

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<MusicAudioLog> _logController =
      StreamController<MusicAudioLog>.broadcast();

  MusicAudioPlayerState _state = const MusicAudioPlayerState();
  AudioData? _audioData;
  AudioSource? _source;
  SoundHandle? _handle;
  StreamSubscription<StreamSoundEvent>? _soundEventSub;
  Timer? _ticker;
  String? _url;
  bool _opening = false;
  bool _disposed = false;
  bool _completedEmitted = false;

  @override
  MusicAudioPlayerState get state => _state;

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum => _spectrumSampler;

  /// 打开播放地址。
  @override
  Future<void> openUrl(String url, {required bool play}) async {
    if (_disposed) {
      return;
    }
    final normalized = url.trim();
    if (normalized.isEmpty) {
      await pause();
      return;
    }
    if (_url == normalized && _source != null && !_opening) {
      // 同一地址重复打开：
      // - 句柄仍有效：直接切换播放/暂停。
      // - 句柄已失效（上一首播放完毕后 SoLoud 回收了 voice，句柄未再更新）：
      //   声源仍在，直接从头上重新起播，避免对失效句柄操作报错。
      final handle = _handle;
      if (handle != null) {
        if (play) {
          await this.play();
        } else {
          await pause();
        }
        return;
      }
      if (play) {
        await _restartSource(_source!);
      } else {
        await pause();
      }
      return;
    }
    _opening = true;
    _completedEmitted = false;
    try {
      await _disposeCurrentSource();
      await _ensureInitialized();
      final source = await _soLoud.loadUrl(
        normalized,
        mode: LoadMode.disk,
        autoDispose: false,
      );
      if (_disposed) {
        await _disposeSourceInstance(source);
        return;
      }
      final duration = _safeLength(source);
      final handle = _soLoud.play(
        source,
        volume: (_state.volume / 100).clamp(0.0, 1.0),
        paused: !play,
      );
      _source = source;
      _handle = handle;
      _url = normalized;
      _state = _state.copyWith(
        playing: play,
        position: Duration.zero,
        duration: duration,
      );
      _durationController.add(duration);
      _positionController.add(Duration.zero);
      _bindSoundEvents(source, handle);
      _startTicker();
    } on Exception catch (error) {
      _log('SoLoud 音乐打开失败: $error', playbackFailure: true);
      rethrow;
    } finally {
      _opening = false;
    }
  }

  /// 播放当前音频。
  @override
  Future<void> play() async {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    try {
      _soLoud.setPause(handle, false);
      _state = _state.copyWith(playing: true);
      _startTicker();
    } on SoLoudSoundHandleNotFoundCppException {
      // 句柄已在 C++ 侧失效（上一条音轨播完、声源被回收等）：丢弃死句柄，
      // 由播放会话按需重新 openUrl 起播，而不是反复对死句柄操作报错。
      _handle = null;
      _log('SoLoud 句柄已失效，等待重新加载音源', playbackFailure: true);
    } on Exception catch (error) {
      _log('SoLoud 播放失败: $error', playbackFailure: true);
    }
  }

  /// 从当前声源的起点重新起播（用于播放完毕后重放同一地址）。
  Future<void> _restartSource(AudioSource source) async {
    try {
      final handle = _soLoud.play(
        source,
        volume: (_state.volume / 100).clamp(0.0, 1.0),
        paused: false,
      );
      _handle = handle;
      _bindSoundEvents(source, handle);
      _completedEmitted = false;
      _state = _state.copyWith(playing: true, position: Duration.zero);
      _positionController.add(Duration.zero);
      _startTicker();
    } on Exception catch (error) {
      _log('SoLoud 重新起播失败: $error', playbackFailure: true);
    }
  }

  /// 暂停当前音频。
  @override
  Future<void> pause() async {
    final handle = _handle;
    if (handle == null) {
      _state = _state.copyWith(playing: false);
      return;
    }
    try {
      _soLoud.setPause(handle, true);
      _state = _state.copyWith(playing: false);
      _spectrumSampler.reset();
      _emitPosition();
    } on SoLoudSoundHandleNotFoundCppException {
      _handle = null;
    } on Exception catch (error) {
      _log('SoLoud 暂停失败: $error');
    }
  }

  /// 跳转播放进度。
  @override
  Future<void> seek(Duration position) async {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final duration = _state.duration;
    final target =
        duration > Duration.zero && position > duration ? duration : position;
    try {
      _soLoud.seek(handle, target);
      _completedEmitted = false;
      _state = _state.copyWith(position: target);
      _positionController.add(target);
    } on SoLoudSoundHandleNotFoundCppException {
      _handle = null;
      _log('SoLoud 句柄已失效，跳转被忽略');
    } on Exception catch (error) {
      _log('SoLoud 跳转失败: $error');
    }
  }

  /// 设置音量，范围为 0 到 100。
  @override
  void setVolume(double volume) {
    final next = volume.clamp(0.0, 100.0).toDouble();
    _state = _state.copyWith(volume: next);
    _volumeController.add(next);
    final handle = _handle;
    if (handle == null) {
      return;
    }
    try {
      _soLoud.setVolume(handle, next / 100);
    } on SoLoudSoundHandleNotFoundCppException {
      _handle = null;
    } on Exception catch (error) {
      _log('SoLoud 音量设置失败: $error');
    }
  }

  /// 设置相对播放速度，范围为 0.5 到 2.0。
  @override
  void setRelativePlaySpeed(double speed) {
    final next = speed.clamp(0.5, 2.0).toDouble();
    _state = _state.copyWith(speed: next);
    final handle = _handle;
    if (handle == null) {
      return;
    }
    try {
      _soLoud.setRelativePlaySpeed(handle, next);
    } on SoLoudSoundHandleNotFoundCppException {
      _handle = null;
    } on Exception catch (error) {
      _log('SoLoud 倍速设置失败: $error');
    }
  }

  /// 更新当前频谱映射使用的曲目信息。
  @override
  void setSpectrumTrack(MusicTrack? track) {
    _spectrumSampler.setTrack(track);
  }

  /// 读取与真实播放同源的频谱帧。
  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) {
    final audioData = _audioData;
    final handle = _handle;
    if (audioData == null || handle == null || !_state.playing) {
      return null;
    }
    try {
      audioData.updateSamples();
      final samples = audioData.getAudioData(alwaysReturnData: false);
      if (samples.length < 256) {
        return null;
      }
      final fftBins = Float32List.sublistView(samples, 0, 256);
      final waveform =
          samples.length >= 512
              ? Float32List.sublistView(samples, 256, 512)
              : Float32List(0);
      if (!_hasSignal(fftBins, waveform)) {
        return null;
      }
      return _spectrumMapper.map(
        fftBins: fftBins,
        waveform: waveform,
        track: track,
        position: _safePosition(handle),
      );
    } on Exception catch (error) {
      _log('SoLoud 频谱读取失败: $error');
      return null;
    }
  }

  /// 释放播放资源。
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _ticker?.cancel();
    await _disposeCurrentSource();
    _audioData?.dispose();
    _spectrumSampler.dispose();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _completedController.close();
    await _logController.close();
  }

  Future<void> _ensureInitialized() async {
    if (!_soLoud.isInitialized) {
      await _soLoud.init(bufferSize: 512, lowLatency: true);
    }
    if (!_soLoud.getVisualizationEnabled()) {
      _soLoud.setVisualizationEnabled(true);
    }
    _soLoud.setFftSmoothing(0);
    _audioData ??= AudioData(GetSamplesKind.linear);
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    if (_disposed) {
      return;
    }
    _emitPosition();
    _spectrumSampler.tick(
      elapsed: _spectrumClock.elapsed,
      playing: _state.playing,
    );
    final handle = _handle;
    if (handle == null || !_state.playing) {
      return;
    }
    if (!_soLoud.getIsValidVoiceHandle(handle)) {
      _markCompleted();
      return;
    }
    final duration = _state.duration;
    if (duration > Duration.zero &&
        _state.position + _completionTolerance >= duration) {
      _markCompleted();
    }
  }

  void _emitPosition() {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final position = _safePosition(handle);
    _state = _state.copyWith(position: position);
    _positionController.add(position);
  }

  void _bindSoundEvents(AudioSource source, SoundHandle handle) {
    unawaited(_soundEventSub?.cancel());
    _soundEventSub = source.soundEvents.listen((event) {
      if (event.handle != handle) {
        return;
      }
      if (event.event == SoundEventType.handleIsNoMoreValid) {
        _markCompleted();
      }
    });
  }

  void _markCompleted() {
    if (_completedEmitted) {
      return;
    }
    _completedEmitted = true;
    // 播放结束（或被 SoLoud 判定句柄失效）后句柄即不可再用，丢弃之；
    // 声源保留，便于重放同一地址时直接起播。
    _handle = null;
    _state = _state.copyWith(playing: false);
    _spectrumSampler.reset();
    _completedController.add(true);
  }

  Duration _safeLength(AudioSource source) {
    try {
      return _soLoud.getLength(source);
    } on Exception catch (error) {
      _log('SoLoud 获取时长失败: $error');
      return Duration.zero;
    }
  }

  Duration _safePosition(SoundHandle handle) {
    try {
      return _soLoud.getPosition(handle);
    } on Exception {
      return _state.position;
    }
  }

  Future<void> _disposeCurrentSource() async {
    await _soundEventSub?.cancel();
    _soundEventSub = null;
    final handle = _handle;
    if (handle != null) {
      try {
        await _soLoud.stop(handle);
      } on Exception catch (error) {
        _log('SoLoud 停止旧播放失败: $error');
      }
    }
    final source = _source;
    if (source != null) {
      await _disposeSourceInstance(source);
    }
    _handle = null;
    _source = null;
    _url = null;
    _state = _state.copyWith(playing: false, position: Duration.zero);
    _spectrumMapper.reset();
    _spectrumSampler.reset();
  }

  Future<void> _disposeSourceInstance(AudioSource source) async {
    try {
      await _soLoud.disposeSource(source);
    } on Exception catch (error) {
      _log('SoLoud 释放声源失败: $error');
    }
  }

  bool _hasSignal(Float32List fft, Float32List waveform) {
    var peak = 0.0;
    for (final value in fft) {
      peak = math.max(peak, value.abs());
    }
    for (final value in waveform) {
      peak = math.max(peak, value.abs());
    }
    return peak > 0.00000008;
  }

  void _log(String text, {bool playbackFailure = false}) {
    if (!_logController.isClosed) {
      _logController.add(MusicAudioLog(text, playbackFailure: playbackFailure));
    }
    if (kDebugMode) {
      devLog('[MusicAudio] $text');
    }
  }
}

/// 由播放器时钟驱动的稳定频谱采样器。
class MusicSpectrumSampler extends ChangeNotifier
    implements ValueListenable<MusicSpectrumFrame> {
  MusicSpectrumSampler({
    required MusicSpectrumFrame? Function({required MusicTrack track})
    readFrame,
  }) : _readFrame = readFrame,
       _value = MusicSpectrumFrame.silent();

  static const Duration _staleGrace = Duration(milliseconds: 80);
  static const double _silenceReleaseSeconds = 0.24;

  final MusicSpectrumFrame? Function({required MusicTrack track}) _readFrame;
  MusicSpectrumFrame _value;
  MusicTrack? _track;
  Duration? _lastTickElapsed;
  Duration? _lastNativeElapsed;

  @override
  MusicSpectrumFrame get value => _value;

  /// 更新采样目标，切换曲目时清理上一首歌的包络状态。
  void setTrack(MusicTrack? track) {
    if (_track?.id == track?.id) {
      _track = track;
      return;
    }
    _track = track;
    reset();
  }

  /// 使用播放器的连续时钟采集一帧频谱。
  void tick({required Duration elapsed, required bool playing}) {
    final track = _track;
    if (!playing || track == null) {
      return;
    }
    final previousElapsed = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    final deltaSeconds =
        previousElapsed == null
            ? 1 / 60
            : ((elapsed - previousElapsed).inMicroseconds /
                    Duration.microsecondsPerSecond)
                .clamp(0.001, 0.050)
                .toDouble();
    final nativeFrame = _readFrame(track: track);
    if (nativeFrame != null && nativeFrame.active) {
      _lastNativeElapsed = elapsed;
      _publish(nativeFrame);
      return;
    }
    final lastNativeElapsed = _lastNativeElapsed;
    if (lastNativeElapsed == null ||
        elapsed - lastNativeElapsed < _staleGrace ||
        !_value.active) {
      return;
    }
    final amount = 1 - math.exp(-deltaSeconds / _silenceReleaseSeconds);
    _publish(_value.decay(amount));
  }

  /// 清理当前频谱帧和采样时间。
  void reset() {
    _lastTickElapsed = null;
    _lastNativeElapsed = null;
    if (_value.active || _value.bands.any((value) => value != 0)) {
      _publish(MusicSpectrumFrame.silent());
    }
  }

  void _publish(MusicSpectrumFrame frame) {
    _value = frame;
    notifyListeners();
  }
}

/// 打开音乐播放源。
Future<void> openMusicAudio(
  MusicAudioPlayback player,
  String url, {
  required bool play,
}) {
  return player.openUrl(url, play: play);
}

/// 判断音乐原生日志是否属于可忽略提示。
bool isIgnorableMusicPlayerLog(String text) {
  final normalized = text.toLowerCase();
  return normalized.contains('property not found _setproperty') ||
      normalized.contains('failed to create file cache');
}

/// 判断播放器日志是否需要转为用户可见的播放失败状态。
bool isMusicPlaybackFailureLog(MusicAudioLog log) {
  return log.playbackFailure && !isIgnorableMusicPlayerLog(log.text);
}
