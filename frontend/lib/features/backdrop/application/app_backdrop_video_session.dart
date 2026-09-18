import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/core/log/dev_log.dart';

final appBackdropVideoSessionProvider = Provider<AppBackdropVideoSession>((
  ref,
) {
  final session = AppBackdropVideoSession._();
  ref.onDispose(session.dispose);
  return session;
});

/// 应用动态背景视频播放会话。
class AppBackdropVideoSession extends ChangeNotifier {
  AppBackdropVideoSession._();

  static const int _maxOpenAttempts = 3;
  static const Duration _openTimeout = Duration(seconds: 12);
  static const Duration _stopTimeout = Duration(seconds: 3);
  static const Duration _disposeTimeout = Duration(seconds: 5);
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 700),
    Duration(milliseconds: 1400),
  ];

  static Future<void> _nativeVideoGate = Future<void>.value();
  static final Map<String, AppBackdropVideoSession> _sessionsByPath =
      <String, AppBackdropVideoSession>{};

  Player? _player;
  VideoController? _controller;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _retryTimer;
  Timer? _resumeRecoveryTimer;
  Timer? _resumeGraceTimer;
  String _path = '';
  String? _activePath;
  Object? _openError;
  Duration? _resumeBaselinePosition;
  bool _muted = true;
  bool _layoutUsable = false;
  bool _sceneActive = false;
  bool _appVisible = true;
  bool _opening = false;
  bool _ready = false;
  bool _renderable = true;
  bool _disposed = false;
  bool _openScheduled = false;
  int _generation = 0;
  int? _openingGeneration;
  int _openAttempts = 0;
  int _successfulOpenCount = 0;
  int _retryCount = 0;

  /// 当前可用于渲染的 video controller。
  VideoController? get controller => _controller;

  /// 当前视频是否已完成打开并可渲染。
  bool get ready => _ready && _controller != null;

  /// 视频纹理是否持有有效帧。
  ///
  /// 后台期间 Android 会回收纹理内容，恢复后直接渲染会得到覆盖海报的
  /// 黑纹理；置为 false 后视图回落到静态海报，等首个解码帧（position
  /// 流推进）到达再恢复视频渲染。
  bool get renderable => _renderable;

  /// 最近一次打开失败的错误。
  Object? get openError => _openError;

  /// 当前是否正在打开视频。
  bool get opening => _opening;

  /// 当前会话代数:仅资源身份变化或打开失败重开时递增,供测试断言。
  int get generation => _generation;

  /// 当前源稳定身份。
  String get sourceIdentity => sourceIdentityOf(_path);

  /// 返回当前会话的调试诊断信息。
  AppBackdropVideoDiagnostics get diagnostics => AppBackdropVideoDiagnostics(
    activePath: _activePath,
    successfulOpenCount: _successfulOpenCount,
    retryCount: _retryCount,
    textureCount: _controller == null ? 0 : 1,
    active: _sceneActive && _layoutUsable && _appVisible,
  );

  /// 按本机路径或签名 URL(忽略查询串)重试当前正在使用的播放会话。
  static void retryPath(String path) {
    final identity = sourceIdentityOf(path);
    for (final entry in _sessionsByPath.entries) {
      if (entry.key == path || sourceIdentityOf(entry.key) == identity) {
        entry.value.retry();
        return;
      }
    }
  }

  /// 视频源稳定身份:签名 URL 轮换查询参数时视为同一资源。
  static String sourceIdentityOf(String path) {
    final trimmed = path.trim();
    final queryIndex = trimmed.indexOf('?');
    return queryIndex < 0 ? trimmed : trimmed.substring(0, queryIndex);
  }

  /// 同步视频路径和静音设置。
  void configure({
    required String? path,
    required bool muted,
    required bool active,
  }) {
    if (_disposed) {
      return;
    }
    final normalizedPath = path?.trim() ?? '';
    final oldPath = _path;
    final identityChanged =
        sourceIdentityOf(_path) != sourceIdentityOf(normalizedPath);
    final mutedChanged = _muted != muted;
    final activeChanged = _sceneActive != active;
    final queryRotated =
        !identityChanged && oldPath.isNotEmpty && oldPath != normalizedPath;
    if (identityChanged || queryRotated || activeChanged) {}
    // 仅签名参数变化时更新引用,不销毁正在播放的会话。
    _path = normalizedPath;
    _muted = muted;
    _sceneActive = active;
    if (identityChanged) {
      _unregisterPath(oldPath);
      _registerPath(normalizedPath);
      _generation++;
      _cancelRetry();
      _openAttempts = 0;
      _openError = null;
      _activePath = null;
      unawaited(_disposeCurrentSession());
    } else if (oldPath != normalizedPath) {
      _unregisterPath(oldPath);
      _registerPath(normalizedPath);
      // 仅签名轮换:正在打开或已就绪时保持会话,避免 list 刷新打断播放;
      // 仅当上次打开失败时才用新 URL 重开。
      if (_openError != null) {
        _generation++;
        _cancelRetry();
        _openAttempts = 0;
        _openError = null;
        _activePath = null;
        unawaited(_disposeCurrentSession());
      }
    }
    if (mutedChanged) {
      final player = _player;
      if (player != null) {
        unawaited(player.setVolume(_muted ? 0 : 100));
      }
    }
    if (activeChanged) {
      if (_sceneActive) {
        _resumeCurrentPlayerIfNeeded();
      } else {
        _cancelRetry();
        _pauseCurrentPlayer();
      }
    }
    if (identityChanged) {
      _notifySafely();
    }
    if (_path.isNotEmpty && _sceneActive) {
      _scheduleOpenIfNeeded();
    }
  }

  /// 同步当前窗口是否有可用的渲染尺寸。
  void setLayoutUsable(bool usable) {
    if (_disposed || _layoutUsable == usable) {
      return;
    }
    _layoutUsable = usable;
    if (!usable || !_sceneActive) {
      _cancelRetry();
      _pauseCurrentPlayer();
      return;
    }
    _resumeCurrentPlayerIfNeeded();
    if (_openError != null && _openAttempts < _maxOpenAttempts) {
      _scheduleRetry(_generation);
    }
    _scheduleOpenIfNeeded();
  }

  /// 同步 Flutter 应用生命周期。
  void updateLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }
    final visible = state == AppLifecycleState.resumed;
    if (_appVisible == visible) {
      return;
    }
    _appVisible = visible;
    if (visible) {
      _resumeBaselinePosition = _player?.state.position;
      // Keep the current texture through a short grace period on resume;
      // fall back to the poster only if position never advances.
      _resumeCurrentPlayerIfNeeded();
      _scheduleResumeGrace();
      _scheduleResumeRecovery();
    } else {
      _cancelResumeGrace();
      _resumeRecoveryTimer?.cancel();
      _resumeRecoveryTimer = null;
      _resumeBaselinePosition = null;
      // Not visible while backgrounded; keep renderable and probe on resume.
      _pauseCurrentPlayer();
    }
  }

  /// Resume grace: keep texture or fall back to poster based on position.
  void _scheduleResumeGrace() {
    _resumeGraceTimer?.cancel();
    _resumeGraceTimer = Timer(const Duration(milliseconds: 320), () {
      if (_disposed || !_appVisible) {
        return;
      }
      if (!_layoutUsable || !_sceneActive) {
        // No scene/layout: guarantee poster when there is no live player.
        if (_player == null && _renderable) {
          _renderable = false;
          _notifySafely();
        }
        return;
      }
      final baseline = _resumeBaselinePosition;
      final current = _player?.state.position;
      // No player or baseline: leave state to the position stream or reopen.
      final advanced =
          baseline != null &&
          current != null &&
          current > baseline + const Duration(milliseconds: 50);
      if (advanced) {
        _resumeBaselinePosition = null;
        if (!_renderable) {
          _renderable = true;
          _notifySafely();
        }
        return;
      }
      if (_renderable) {
        _renderable = false;
        _notifySafely();
      }
    });
  }

  void _cancelResumeGrace() {
    _resumeGraceTimer?.cancel();
    _resumeGraceTimer = null;
  }

  /// 恢复后若纹理长期无可渲染帧，强制重开会话。
  ///
  /// Android 后台回收纹理后，仅 play() 有时无法恢复原生输出；海报层会
  /// 持续兜底，超时后重开播放器以重新接上有效纹理。
  void _scheduleResumeRecovery() {
    _resumeRecoveryTimer?.cancel();
    _resumeRecoveryTimer = Timer(const Duration(milliseconds: 600), () {
      if (_disposed ||
          !_appVisible ||
          !_layoutUsable ||
          !_sceneActive ||
          _renderable ||
          _path.isEmpty) {
        return;
      }
      if (_ready && _player != null && _openError == null) {
        _generation++;
        _cancelRetry();
        _openAttempts = 0;
        _openError = null;
        _activePath = null;
        _resumeBaselinePosition = null;
        unawaited(
          _disposeCurrentSession().then((_) {
            if (!_disposed) {
              _scheduleOpenIfNeeded(force: true);
              _notifySafely();
            }
          }),
        );
      }
    });
  }

  /// 手动重试当前视频。
  void retry() {
    if (_disposed) {
      return;
    }
    _cancelRetry();
    _openAttempts = 0;
    _openError = null;
    _generation++;
    _scheduleOpenIfNeeded(force: true);
    _notifySafely();
  }

  void _scheduleOpenIfNeeded({bool force = false}) {
    if (_disposed ||
        !_layoutUsable ||
        !_sceneActive ||
        _path.isEmpty ||
        _openScheduled ||
        _opening ||
        (!force && _ready && _activePath == _path && _controller != null)) {
      return;
    }
    if (!force && _openError != null) {
      return;
    }
    _openScheduled = true;
    final generation = _generation;
    scheduleMicrotask(() {
      _openScheduled = false;
      if (_disposed ||
          generation != _generation ||
          !_layoutUsable ||
          !_sceneActive) {
        return;
      }
      unawaited(_openForCurrentPath(generation));
    });
  }

  Future<void> _openForCurrentPath(int generation) async {
    if (_disposed ||
        _opening ||
        generation != _generation ||
        !_layoutUsable ||
        !_sceneActive ||
        _path.isEmpty) {
      return;
    }
    final path = _path;
    _opening = true;
    _openingGeneration = generation;
    _openError = null;
    _resumeBaselinePosition = null;
    if (_renderable) {
      _renderable = false;
    }
    _notifySafely();
    await _disposeCurrentSession();
    if (!_canUseGeneration(generation, path)) {
      _finishOpening(generation);
      return;
    }
    _openAttempts++;
    try {
      final opened = await _withNativeVideoGate(() async {
        if (!_canUseGeneration(generation, path)) {
          return null;
        }
        final player = Player();
        final controller = VideoController(player);
        try {
          await player.setVolume(_muted ? 0 : 100);
          await player.setPlaylistMode(PlaylistMode.single);
          final resource =
              path.startsWith('http') ? Uri.parse(path) : Uri.file(path);
          await player
              .open(Media(resource.toString()), play: _shouldPlay)
              .timeout(_openTimeout);
          if (!_canUseGeneration(generation, path)) {
            await _stopAndDisposePlayer(player);
            return null;
          }
          _player = player;
          _controller = controller;
          _activePath = path;
          return (player: player, controller: controller);
        } on Object {
          await _stopAndDisposePlayer(player);
          rethrow;
        }
      });
      if (opened == null) {
        _finishOpening(generation);
        return;
      }
      final player = opened.player;
      if (!_canUseGeneration(generation, path) || !identical(_player, player)) {
        _finishOpening(generation);
        return;
      }
      _completedSub = player.stream.completed.listen((completed) {
        if (!completed || _disposed || !identical(_player, player)) {
          return;
        }
        unawaited(player.seek(Duration.zero));
        if (_shouldPlay) {
          unawaited(player.play());
        }
      });
      _positionSub = player.stream.position.listen((position) {
        if (_disposed || !identical(_player, player)) {
          return;
        }
        if (!_renderable) {
          final baseline = _resumeBaselinePosition;
          // 仅当播放位置相对恢复基点推进时，才认为纹理已持有新帧；
          // 否则首帧事件可能对应仍是被回收的黑纹理。
          final advanced =
              baseline == null ||
              position > baseline + const Duration(milliseconds: 50);
          if (advanced) {
            _resumeBaselinePosition = null;
            _renderable = true;
            _notifySafely();
          }
        }
      });
      _ready = true;
      _successfulOpenCount++;
      _openError = null;
      if (!_shouldPlay) {
        _pauseCurrentPlayer();
      }
      _finishOpening(generation);
    } on Object catch (error) {
      if (_canUseGeneration(generation, path)) {
        _openError = error;
        _ready = false;
        _finishOpening(generation);
        _scheduleRetry(generation);
      } else {
        _finishOpening(generation);
      }
    }
  }

  bool _canUseGeneration(int generation, String path) {
    return !_disposed &&
        generation == _generation &&
        _path == path &&
        _layoutUsable &&
        _sceneActive;
  }

  bool get _shouldPlay => _layoutUsable && _appVisible && _sceneActive;

  void _finishOpening(int generation) {
    if (_openingGeneration == generation) {
      _opening = false;
      _openingGeneration = null;
    }
    _notifySafely();
    _scheduleOpenIfNeeded();
  }

  void _scheduleRetry(int generation) {
    if (_disposed ||
        generation != _generation ||
        !_layoutUsable ||
        !_sceneActive ||
        _retryTimer != null ||
        _openAttempts >= _maxOpenAttempts) {
      return;
    }
    final retryIndex = (_openAttempts - 1).clamp(0, _retryDelays.length - 1);
    _retryTimer = Timer(_retryDelays[retryIndex], () {
      _retryTimer = null;
      if (!_canUseGeneration(generation, _path)) {
        return;
      }
      _retryCount++;
      _openError = null;
      _scheduleOpenIfNeeded(force: true);
      _notifySafely();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _cancelResumeRecovery() {
    _resumeRecoveryTimer?.cancel();
    _resumeRecoveryTimer = null;
  }

  void _pauseCurrentPlayer() {
    final player = _player;
    if (player != null) {
      unawaited(player.pause());
    }
  }

  void _resumeCurrentPlayerIfNeeded() {
    final player = _player;
    if (_ready && player != null && _shouldPlay) {
      unawaited(player.play());
    }
  }

  Future<void> _disposeCurrentSession() async {
    final detached = _takeCurrentSession();
    if (detached == null) {
      return;
    }
    _notifySafely();
    await _disposeDetachedSession(detached);
  }

  _DetachedVideoSession? _takeCurrentSession() {
    final player = _player;
    if (player == null) {
      _controller = null;
      _completedSub = null;
      _positionSub = null;
      _ready = false;
      _activePath = null;
      return null;
    }
    final detached = _DetachedVideoSession(
      player: player,
      completedSub: _completedSub,
      positionSub: _positionSub,
    );
    _player = null;
    _controller = null;
    _completedSub = null;
    _positionSub = null;
    _ready = false;
    _activePath = null;
    return detached;
  }

  Future<void> _disposeDetachedSession(_DetachedVideoSession session) {
    return _withNativeVideoGate(() async {
      await session.completedSub?.cancel();
      await session.positionSub?.cancel();
      await _stopAndDisposePlayer(session.player);
    });
  }

  static Future<T> _withNativeVideoGate<T>(Future<T> Function() operation) {
    final previous = _nativeVideoGate;
    final completer = Completer<void>();
    _nativeVideoGate = completer.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }();
  }

  static Future<void> _stopAndDisposePlayer(Player player) async {
    try {
      await player.stop().timeout(_stopTimeout);
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('应用背景：释放前停止播放器失败：$error');
      }
    }
    try {
      await player.dispose().timeout(_disposeTimeout);
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('应用背景：释放播放器失败：$error');
      }
    }
  }

  void _registerPath(String path) {
    if (path.isEmpty) {
      return;
    }
    _sessionsByPath[path] = this;
  }

  void _unregisterPath(String path) {
    if (path.isEmpty) {
      return;
    }
    if (identical(_sessionsByPath[path], this)) {
      _sessionsByPath.remove(path);
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      super.dispose();
      return;
    }
    _disposed = true;
    _generation++;
    _cancelRetry();
    _cancelResumeGrace();
    _cancelResumeRecovery();
    _unregisterPath(_path);
    final detached = _takeCurrentSession();
    if (detached != null) {
      unawaited(_disposeDetachedSession(detached));
    }
    super.dispose();
  }
}

/// 应用背景视频会话的只读诊断快照。
class AppBackdropVideoDiagnostics {
  const AppBackdropVideoDiagnostics({
    required this.activePath,
    required this.successfulOpenCount,
    required this.retryCount,
    required this.textureCount,
    required this.active,
  });

  final String? activePath;
  final int successfulOpenCount;
  final int retryCount;
  final int textureCount;
  final bool active;
}

class _DetachedVideoSession {
  const _DetachedVideoSession({
    required this.player,
    required this.completedSub,
    this.positionSub,
  });

  final Player player;
  final StreamSubscription<bool>? completedSub;
  final StreamSubscription<Duration>? positionSub;
}
