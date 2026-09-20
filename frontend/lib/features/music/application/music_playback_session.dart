import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/media/web_media_session.dart';
import 'package:omninest/features/music/application/create_music_audio_player.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_media_session.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 音乐播放会话。
class MusicPlaybackSession {
  const MusicPlaybackSession({required this.player, required this.lastError});

  final MusicAudioPlayback player;
  final String? lastError;

  MusicPlaybackSession copyWith({
    MusicAudioPlayback? player,
    Object? lastError = _noChange,
  }) {
    return MusicPlaybackSession(
      player: player ?? this.player,
      lastError:
          identical(lastError, _noChange)
              ? this.lastError
              : lastError as String?,
    );
  }
}

const Object _noChange = Object();

/// 当前平台使用的音乐播放适配器。
final musicAudioPlaybackProvider = Provider.autoDispose<MusicAudioPlayback>((
  ref,
) {
  final player = createMusicAudioPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

final musicPlaybackSessionProvider =
    NotifierProvider<MusicPlaybackSessionController, MusicPlaybackSession>(
      MusicPlaybackSessionController.new,
    );

/// 全局音乐播放会话控制器。
class MusicPlaybackSessionController extends Notifier<MusicPlaybackSession> {
  /// 会话可能被 invalidate 后在同一 notifier 实例上重建，字段不能声明为 late final。
  late MusicAudioPlayback _player;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<MusicAudioLog>? _logSub;
  StreamSubscription<Duration>? _positionSub;
  late MusicProgressRepository _progressRepository;
  String? _loadedUrl;
  MusicPlayableItem? _loadedItem;
  bool _syncing = false;
  bool _syncRequested = false;
  bool _persistRequested = false;
  bool _pendingCompleted = false;
  Future<void>? _persistFuture;
  AppLifecycleListener? _lifecycleListener;
  int _lastSavedSecond = -1;
  MusicMediaSessionHandler? _mediaHandler;
  WebMediaSessionBinder? _webMediaBinder;
  StreamSubscription<Duration>? _mediaPositionSub;
  DateTime _lastMediaSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  MusicPlaybackSession build() {
    _player = ref.watch(musicAudioPlaybackProvider);
    _progressRepository = ref.read(globalMusicProgressRepositoryProvider);
    // 重建（登出/换号 invalidate）时丢弃上一会话的加载状态，避免旧播放计划签名 URL 残留。
    _loadedUrl = null;
    _loadedItem = null;
    _lastSavedSecond = -1;
    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed) {
        return;
      }
      unawaited(_handleCompleted());
    });
    _logSub = _player.stream.log.listen(_handleLog);
    _positionSub = _player.stream.position.listen(_handlePosition);
    _lifecycleListener = AppLifecycleListener(
      onPause: _flushPlaybackQueue,
      onDetach: _flushPlaybackQueue,
      onExitRequested: _flushPlaybackQueueBeforeExit,
    );
    _registerSystemMediaSession();
    ref.listen(musicCenterControllerProvider, (previous, next) {
      _syncSystemMediaState(force: true);
    });
    unawaited(_restorePlaybackSpeed());
    ref.onDispose(() {
      _lifecycleListener?.dispose();
      _lifecycleListener = null;
      unawaited(_mediaPositionSub?.cancel());
      unawaited(_persistCurrent());
      unawaited(_completedSub?.cancel());
      unawaited(_logSub?.cancel());
      unawaited(_positionSub?.cancel());
    });
    return MusicPlaybackSession(player: _player, lastError: null);
  }

  Future<void> _restorePlaybackSpeed() async {
    try {
      final speed =
          await ref
              .read(musicLocalPreferencesControllerProvider.notifier)
              .loadPlaybackSpeed();
      if (!ref.mounted) {
        return;
      }
      _player.setRelativePlaySpeed(speed);
    } on Object {
      return;
    }
  }

  /// 注册系统媒体会话：Android/iOS 通知栏与音频焦点、Web 媒体控件。
  void _registerSystemMediaSession() {
    final commands = MusicMediaCommandCallbacks(
      onPlay:
          () => _runMediaCommand(
            () => ref
                .read(musicCenterControllerProvider.notifier)
                .setPlaying(true),
          ),
      onPause:
          () => _runMediaCommand(
            () => ref
                .read(musicCenterControllerProvider.notifier)
                .setPlaying(false),
          ),
      onNext:
          () => _runMediaCommand(
            () => ref.read(musicCenterControllerProvider.notifier).nextTrack(),
          ),
      onPrevious:
          () => _runMediaCommand(
            () =>
                ref
                    .read(musicCenterControllerProvider.notifier)
                    .previousTrack(),
          ),
      onPlayPauseToggle:
          () => _runMediaCommand(
            () =>
                ref
                    .read(musicCenterControllerProvider.notifier)
                    .togglePlayback(),
          ),
      onSeek:
          (position) => _runMediaCommand(() async {
            await _player.seek(position);
          }),
    );
    if (kIsWeb) {
      _webMediaBinder = WebMediaSessionBinder.register(
        onPlay: commands.onPlay,
        onPause: commands.onPause,
        onNext: commands.onNext,
        onPrevious: commands.onPrevious,
      );
      _mediaPositionSub = _player.stream.position.listen((_) {
        _syncSystemMediaState();
      });
      return;
    }
    // 桌面媒体键：命令经 MusicMediaKeyBridge 转接。
    MusicMediaKeyBridge.register(commands);
    if (!musicMediaSessionSupported) {
      return;
    }
    unawaited(
      ensureMusicMediaSession(commands).then((handler) {
        _mediaHandler = handler;
        _syncSystemMediaState();
      }),
    );
    _mediaPositionSub = _player.stream.position.listen((_) {
      _syncSystemMediaState();
    });
  }

  Future<void> _runMediaCommand(Future<void> Function() command) async {
    await command();
    await syncFromCenterState();
  }

  /// 把当前曲目与播放状态同步给系统媒体控件（通知栏/锁屏/浏览器面板）。
  ///
  /// [force] 为 true 时跳过节流（切歌/暂停等关键状态变化），进度流按 1s 节流。
  void _syncSystemMediaState({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastMediaSyncAt) < const Duration(seconds: 1)) {
      return;
    }
    _lastMediaSyncAt = now;
    final center = ref.read(musicCenterControllerProvider).asData?.value;
    final track = center?.currentItem?.track;
    final playing = _player.state.playing && (center?.isPlaying ?? false);
    final position = _player.state.position;
    final duration = _player.state.duration;
    _mediaHandler?.updateNowPlaying(
      track: track,
      playing: playing,
      position: position,
      duration: duration,
    );
    final binder = _webMediaBinder;
    if (binder != null && track != null) {
      binder.updateMetadata(
        title: track.title,
        artistName: track.artistName,
        albumTitle: track.albumTitle,
        coverUrl: track.coverUrl,
      );
    }
    binder?.updatePlaybackState(
      playing: playing,
      position: position,
      duration: duration,
    );
  }

  void _flushPlaybackQueue() {
    unawaited(
      ref.read(musicCenterControllerProvider.notifier).flushPlaybackQueue(),
    );
  }

  Future<AppExitResponse> _flushPlaybackQueueBeforeExit() async {
    await ref.read(musicCenterControllerProvider.notifier).flushPlaybackQueue();
    return AppExitResponse.exit;
  }

  /// 同步播放计划和播放状态。
  Future<void> syncFromCenterState() async {
    _syncRequested = true;
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      while (_syncRequested) {
        _syncRequested = false;
        await _syncOnce();
      }
    } finally {
      _syncing = false;
    }
  }

  /// 清理当前错误。
  void clearError() {
    state = state.copyWith(lastError: null);
  }

  Future<void> _syncOnce() async {
    final current = ref.read(musicCenterControllerProvider).asData?.value;
    if (current == null) {
      return;
    }
    final plan = current.playbackPlan;
    final item = current.currentItem;
    _player.setSpectrumTrack(item?.track);
    if (item != null &&
        _loadedItem != null &&
        _loadedItem!.playableKey != item.playableKey &&
        (plan == null || plan.url.isEmpty)) {
      if (_player.state.playing) {
        await _player.pause();
      }
      await _persistCurrent();
      await _player.seek(Duration.zero);
      _loadedUrl = null;
      _loadedItem = null;
      _lastSavedSecond = 0;
      return;
    }
    if (plan == null || plan.url.isEmpty || item == null) {
      if (_player.state.playing) {
        await _player.pause();
        await _persistCurrent();
      }
      return;
    }
    if (plan.expiresAt != null && DateTime.now().isAfter(plan.expiresAt!)) {
      // 播放计划已过期：静默停止并置空，避免 invalidate 自触发重建循环。
      if (_player.state.playing) {
        await _player.pause();
        await _persistCurrent();
      }
      _loadedUrl = null;
      _loadedItem = null;
      _lastSavedSecond = 0;
      return;
    }
    if (_loadedUrl != plan.url ||
        _loadedItem?.playableKey != item.playableKey) {
      await _openItem(item, plan.url, play: current.isPlaying);
      return;
    }
    if (current.isPlaying && !_player.state.playing) {
      await _player.play();
    } else if (!current.isPlaying && _player.state.playing) {
      await _player.pause();
      await _persistCurrent();
    }
  }

  Future<void> _openItem(
    MusicPlayableItem item,
    String url, {
    required bool play,
  }) async {
    try {
      if (_loadedItem != null && _player.state.playing) {
        await _player.pause();
      }
      await _persistCurrent();
      await openMusicAudio(_player, url, play: false);
      await _player.seek(Duration.zero);
      _loadedUrl = url;
      _loadedItem = item;
      _lastSavedSecond = 0;
      final latestItem =
          ref.read(musicCenterControllerProvider).asData?.value.currentItem;
      if (latestItem?.playableKey != item.playableKey) {
        return;
      }
      if (play) {
        await _player.play();
      }
      state = state.copyWith(lastError: null);
    } catch (error) {
      _loadedUrl = null;
      _loadedItem = null;
      if (kDebugMode) {
        devLog('[_syncPlayback] 音频打开失败: $error');
      }
      state = state.copyWith(lastError: error.toString());
    }
  }

  void _handlePosition(Duration position) {
    if (!_player.state.playing || _loadedItem == null) {
      return;
    }
    final second = position.inSeconds;
    if (second <= 0 || second - _lastSavedSecond < 10) {
      return;
    }
    _lastSavedSecond = second;
    unawaited(_persistCurrent());
  }

  Future<void> _handleCompleted() async {
    await _persistCurrent(completed: true);
    await ref.read(musicCenterControllerProvider.notifier).nextTrack();
  }

  Future<void> _persistCurrent({bool completed = false}) {
    _persistRequested = true;
    _pendingCompleted = _pendingCompleted || completed;
    final active = _persistFuture;
    if (active != null) {
      return active;
    }
    final completer = Completer<void>();
    _persistFuture = completer.future;
    unawaited(_drainPersistRequests(completer));
    return completer.future;
  }

  Future<void> _drainPersistRequests(Completer<void> completer) async {
    try {
      while (_persistRequested) {
        _persistRequested = false;
        final shouldComplete = _pendingCompleted;
        _pendingCompleted = false;
        final item = _loadedItem;
        final position = _player.state.position;
        if (item == null ||
            (!shouldComplete && position < const Duration(seconds: 1))) {
          continue;
        }
        await _progressRepository.saveLocal(
          playableKey: item.playableKey,
          position: position,
          duration: _player.state.duration,
          completed: shouldComplete,
        );
      }
      completer.complete();
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('[MusicPlaybackProgress] 本地进度保存失败: $error');
      }
      completer.complete();
    } finally {
      _persistFuture = null;
      if (_persistRequested) {
        unawaited(_persistCurrent());
      }
    }
  }

  void _handleLog(MusicAudioLog log) {
    if (!isMusicPlaybackFailureLog(log)) {
      return;
    }
    if (kDebugMode) {
      devLog('[_logSub] 音频播放错误: ${log.text}');
    }
    state = state.copyWith(lastError: log.text);
  }
}
