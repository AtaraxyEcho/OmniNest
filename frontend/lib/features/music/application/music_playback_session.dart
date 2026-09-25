import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:dio/dio.dart';
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
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/music/domain/music_cover_paths.dart';
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

/// 切歌加载中记下的一次跳转目标。
typedef _PendingSeek = ({String playableKey, Duration position});

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
  bool _completedForLoadedItem = false;
  _PendingSeek? _pendingSeek;
  Future<void>? _persistFuture;
  AppLifecycleListener? _lifecycleListener;
  int _lastSavedSecond = -1;
  MusicMediaSessionHandler? _mediaHandler;
  WebMediaSessionBinder? _webMediaBinder;
  StreamSubscription<Duration>? _mediaPositionSub;
  DateTime _lastMediaSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 音频焦点 duck 前的音量（0-100）；null 表示当前未压低。
  double? _volumeBeforeDuck;

  @override
  MusicPlaybackSession build() {
    _player = ref.watch(musicAudioPlaybackProvider);
    _progressRepository = ref.read(globalMusicProgressRepositoryProvider);
    // 重建（登出/换号 invalidate）时丢弃上一会话的加载状态，避免旧播放计划签名 URL 残留。
    _loadedUrl = null;
    _loadedItem = null;
    _lastSavedSecond = -1;
    _volumeBeforeDuck = null;
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
    unawaited(
      _restorePlaybackSpeed().catchError((Object error) {
        if (kDebugMode) {
          devLog('[_restorePlaybackSpeed] $error');
        }
      }),
    );
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
            await seekTo(position);
          }),
      onAudioDuck: (ducked) async {
        if (ducked) {
          _volumeBeforeDuck ??= _player.state.volume;
          _player.setVolume((_volumeBeforeDuck! * 0.3).clamp(0, 100));
        } else {
          final restore = _volumeBeforeDuck;
          _volumeBeforeDuck = null;
          if (restore != null) {
            _player.setVolume(restore);
          }
        }
      },
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
      ensureMusicMediaSession(commands)
          .then((handler) {
            // 会话可能在等待平台通道期间被销毁（登出/换号 invalidate）：此时
            // 继续用 ref 读中心状态会命中 Riverpod 的失效 Ref 断言。
            if (!ref.mounted) {
              return;
            }
            _mediaHandler = handler;
            _syncSystemMediaState();
          })
          .catchError((Object error) {
            if (kDebugMode) {
              devLog('[MusicMediaSession] 初始化失败: $error');
            }
            return null;
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
    try {
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
        final coverUrl = track.listCoverUrl;
        binder.updateMetadata(
          title: track.title,
          artistName: track.artistName,
          albumTitle: track.albumTitle,
          coverUrl: coverUrl,
          // 本地封面是需鉴权的稳定 API 路径：浏览器直连拿不到字节，改由共享 Dio 取。
          coverLoader:
              coverUrl != null && isMusicCoverApiPath(coverUrl)
                  ? _loadCoverBytes
                  : null,
        );
      }
      binder?.updatePlaybackState(
        playing: playing,
        position: position,
        duration: duration,
      );
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('[_syncSystemMediaState] $error');
      }
    }
  }

  Future<Uint8List?> _loadCoverBytes(String url) async {
    final dio = ref.read(apiClientProvider).dio;
    try {
      final response = await dio.get<List<int>>(
        resolveApiAbsoluteUrl(dio, url),
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      return bytes == null ? null : Uint8List.fromList(bytes);
    } on Object catch (error) {
      // 封面取不到只影响系统面板的图，不得冒泡进播放状态同步。
      devLog('媒体会话封面字节加载失败: ${error.runtimeType}');
      return null;
    }
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

  /// 受控跳转：所有用户发起的进度跳转都走这里，而不是直接操作播放器。
  ///
  /// 切歌时 `_openItem` 会把新音源定位到 0；若此刻用户点了歌词行或拖了进度条，
  /// 直接 `player.seek()` 会被那次归零覆盖（表现为跳转后仍从头播放）。因此目标
  /// 位置先记下来，加载完成后对同一曲目生效；曲目已加载时立即跳转。
  Future<void> seekTo(Duration position) async {
    final item =
        ref.read(musicCenterControllerProvider).asData?.value.currentItem;
    if (item == null) {
      return;
    }
    _pendingSeek = (playableKey: item.playableKey, position: position);
    if (_loadedItem?.playableKey == item.playableKey) {
      _pendingSeek = null;
      await _player.seek(position);
      return;
    }
    await syncFromCenterState();
  }

  /// 取出并清除指定曲目的待生效跳转。
  Duration? _takePendingSeek(String playableKey) {
    final pending = _pendingSeek;
    if (pending == null) {
      return null;
    }
    _pendingSeek = null;
    return pending.playableKey == playableKey ? pending.position : null;
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
      if (_completedForLoadedItem) {
        // 单曲循环原地重播：地址与曲目都没变，只调 play() 无法从头起播
        // （原生适配器在播完时已丢弃句柄），改走同一地址的 openUrl 重放分支。
        await openMusicAudio(_player, plan.url, play: true);
        _completedForLoadedItem = false;
      } else {
        await _player.play();
      }
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
      await _player.seek(_takePendingSeek(item.playableKey) ?? Duration.zero);
      _loadedUrl = url;
      _loadedItem = item;
      _completedForLoadedItem = false;
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
    // 单曲循环会重播同一地址：先记录播完事实，同步链路据此走重放而不是空 play()。
    _completedForLoadedItem = true;
    await _persistCurrent(completed: true);
    // 自动推进：顺序与随机档首尾循环，手动下一首才总是前进一格。
    await ref
        .read(musicCenterControllerProvider.notifier)
        .nextTrack(autoAdvance: true);
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
