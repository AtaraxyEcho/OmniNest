import 'dart:async';

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:web/web.dart' as web;

/// Web 端音乐播放器：HTMLAudioElement 实现。
///
/// SoLoud 为 FFI 原生库，在 Web 无实现（实例化即 `_isInited` TypeError），
/// 故 Web 端走浏览器音频元素。已知行为差异：
/// - 进度粒度随 timeupdate（约 250ms），比原生 16ms ticker 粗；
/// - 频谱无来源，回退静默帧；
/// - 受浏览器自动播放策略约束：首次起播需处于用户手势上下文，
///   后续自动切歌依赖文档 sticky activation。
class WebMusicAudioPlayback implements MusicAudioPlayback {
  WebMusicAudioPlayback() {
    _bindEvents();
  }

  static const Duration _openTimeout = Duration(seconds: 12);

  final web.HTMLAudioElement _audio = web.HTMLAudioElement();

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

  Completer<void>? _openCompleter;
  Timer? _openTimeoutTimer;
  MusicAudioPlayerState _state = const MusicAudioPlayerState();
  String? _url;
  bool _disposed = false;

  @override
  MusicAudioPlayerState get state => _state;

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: _durationController.stream,
    volume: _volumeController.stream,
    completed: _completedController.stream,
    log: _logController.stream,
  );

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
    if (_url == normalized && _openCompleter == null) {
      if (play) {
        await this.play();
      } else {
        await pause();
      }
      return;
    }
    await _cancelPendingOpen();
    _openCompleter = Completer<void>();
    _openTimeoutTimer = Timer(_openTimeout, () {
      _completePendingOpen(
        StateError('音频打开超时: $normalized'),
        playbackFailure: true,
      );
    });
    _url = normalized;
    _audio.src = normalized;
    _audio.load();
    try {
      await _openCompleter!.future;
      _state = _state.copyWith(
        playing: play,
        position: Duration.zero,
        duration: _elementDuration,
      );
      _durationController.add(_state.duration);
      _positionController.add(Duration.zero);
      if (play) {
        await this.play();
      }
    } on Exception catch (error) {
      _log('Web 音频打开失败: $error', playbackFailure: true);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) {
      return;
    }
    try {
      await _audio.play().toDart;
      _updateState(playing: true);
    } on Exception catch (error) {
      _log('Web 音频播放失败: $error', playbackFailure: true);
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    _audio.pause();
    _updateState(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) {
      return;
    }
    final seconds = position.inMilliseconds / 1000;
    if (seconds.isNaN || seconds < 0) {
      return;
    }
    _audio.currentTime = seconds;
    _updateState(position: position);
    _positionController.add(position);
  }

  @override
  void setVolume(double volume) {
    if (_disposed) {
      return;
    }
    final clamped = volume.clamp(0.0, 100.0);
    _audio.volume = (clamped / 100).clamp(0.0, 1.0);
    _updateState(volume: clamped);
    _volumeController.add(clamped);
  }

  @override
  void setRelativePlaySpeed(double speed) {
    if (_disposed || speed <= 0) {
      return;
    }
    _audio.playbackRate = speed;
    _updateState(speed: speed);
  }

  @override
  void setSpectrumTrack(MusicTrack? track) {
    // Web 端无频谱来源，静默忽略。
  }

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _cancelPendingOpen();
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    _unbindEvents();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _completedController.close();
    await _logController.close();
  }

  Duration get _elementDuration {
    final raw = _audio.duration;
    if (raw.isNaN || raw.isInfinite || raw <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: (raw * 1000).round());
  }

  void _bindEvents() {
    _audio.oncanplay =
        ((web.Event _) {
          _completePendingOpen(null);
        }).toJS;
    _audio.onloadedmetadata =
        ((web.Event _) {
          final duration = _elementDuration;
          if (duration > Duration.zero) {
            _updateState(duration: duration);
            _durationController.add(duration);
          }
        }).toJS;
    _audio.ontimeupdate =
        ((web.Event _) {
          final position = Duration(
            milliseconds: (_audio.currentTime * 1000).round(),
          );
          _updateState(position: position);
          _positionController.add(position);
        }).toJS;
    _audio.onplay =
        ((web.Event _) {
          _updateState(playing: true);
        }).toJS;
    _audio.onpause =
        ((web.Event _) {
          _updateState(playing: false);
        }).toJS;
    _audio.onended =
        ((web.Event _) {
          _updateState(playing: false);
          _completedController.add(true);
        }).toJS;
    _audio.onerror =
        ((web.Event _) {
          _completePendingOpen(
            StateError('音频加载失败(${_audio.error?.code ?? 0}): $_url'),
            playbackFailure: true,
          );
        }).toJS;
  }

  void _unbindEvents() {
    _audio.oncanplay = null;
    _audio.onloadedmetadata = null;
    _audio.ontimeupdate = null;
    _audio.onplay = null;
    _audio.onpause = null;
    _audio.onended = null;
    _audio.onerror = null;
  }

  void _completePendingOpen(Object? error, {bool playbackFailure = false}) {
    final completer = _openCompleter;
    _openCompleter = null;
    _openTimeoutTimer?.cancel();
    _openTimeoutTimer = null;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (error == null) {
      completer.complete();
    } else {
      completer.completeError(error);
    }
  }

  Future<void> _cancelPendingOpen() async {
    final completer = _openCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    _completePendingOpen(StateError('音频源被替换'));
    try {
      await completer.future;
    } on Object {
      // 被替换的打开请求按取消处理。
    }
  }

  void _updateState({
    bool? playing,
    Duration? position,
    Duration? duration,
    double? volume,
    double? speed,
  }) {
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(
      playing: playing,
      position: position,
      duration: duration,
      volume: volume,
      speed: speed,
    );
  }

  void _log(String text, {bool playbackFailure = false}) {
    if (_disposed) {
      return;
    }
    _logController.add(MusicAudioLog(text, playbackFailure: playbackFailure));
  }
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();
}
