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
import 'package:omninest/features/music/application/music_sleep_timer_controller.dart';
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/music/domain/music_cover_paths.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/core/log/dev_log.dart';

part 'music_playback_session_model.dart';

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
  static const Duration _planRenewalLead = Duration(minutes: 2);
  static const Duration _planRenewalCooldown = Duration(seconds: 30);

  /// 会话可能被 invalidate 后在同一 notifier 实例上重建，字段不能声明为 late final。
  late MusicAudioPlayback _player;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<MusicAudioLog>? _logSub;
  StreamSubscription<Duration>? _positionSub;
  String? _listeningPlayableKey;
  String? _listeningHistoryId;
  Duration? _lastListeningPosition;
  final Stopwatch _listeningClock = Stopwatch();
  int _listenedMilliseconds = 0;
  int _reportedListeningSeconds = 0;
  Future<void>? _listeningWriteFuture;
  late MusicProgressRepository _progressRepository;
  String? _loadedUrl;
  MusicPlayableItem? _loadedItem;
  bool _syncing = false;
  bool _syncRequested = false;
  bool _persistRequested = false;
  bool _pendingCompleted = false;
  bool _completedForLoadedItem = false;
  bool _renewingPlan = false;
  String? _lastRenewedPlanUrl;
  DateTime? _lastPlanRenewalAttemptAt;
  _PendingSeek? _pendingSeek;
  Future<void>? _persistFuture;
  AppLifecycleListener? _lifecycleListener;
  int _lastSavedSecond = -1;
  MusicMediaSessionHandler? _mediaHandler;
  WebMediaSessionBinder? _webMediaBinder;
  MusicMediaCommandCallbacks? _mediaCommands;
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
    _renewingPlan = false;
    _lastRenewedPlanUrl = null;
    _lastPlanRenewalAttemptAt = null;
    _listeningPlayableKey = null;
    _listeningHistoryId = null;
    _listenedMilliseconds = 0;
    _reportedListeningSeconds = 0;
    _resetListeningBaseline(null, playing: false);
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
      _syncListeningState(next);
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
      // 媒体会话的命令闭包与封面 object URL 是进程级单例，必须显式解绑，
      // 否则会话重建后系统媒体键仍指向已销毁的第一代 Notifier。
      _webMediaBinder?.dispose();
      _webMediaBinder = null;
      final commands = _mediaCommands;
      if (commands != null) {
        MusicMediaKeyBridge.unregister(commands);
        _mediaCommands = null;
      }
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
    _mediaCommands = commands;
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
        options: Options(
          responseType: ResponseType.bytes,
          // bytes 响应没有信封：共享 Dio 的 validateStatus 放到 <500，
          // 非 2xx 时错误 JSON 会被当成图片字节交给系统面板。
          validateStatus:
              (status) => status != null && status >= 200 && status < 300,
        ),
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
    _resetListeningBaseline(null, playing: false);
    unawaited(_reportListeningDuration());
    unawaited(
      ref.read(musicCenterControllerProvider.notifier).flushPlaybackQueue(),
    );
  }

  Future<AppExitResponse> _flushPlaybackQueueBeforeExit() async {
    _resetListeningBaseline(null, playing: false);
    try {
      await Future.wait<void>([
        _reportListeningDuration(),
        ref.read(musicCenterControllerProvider.notifier).flushPlaybackQueue(),
      ]).timeout(
        const Duration(milliseconds: 300),
        onTimeout: () => const <void>[],
      );
    } on Object catch (error) {
      devLog('退出前刷新播放队列失败（忽略继续退出）: $error');
    }
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

  /// 冷启动或计划过期后继续播放：把已保存的曲内位置交给下一次开流。
  ///
  /// 只在“没有播放计划却按下播放键”这一恢复手势里调用；点歌走 playTrack，
  /// 不经过这里，用户明确选一首歌时仍从头播。进度仓库本身带本地优先与远端补齐，
  /// 因此跨设备继续听也能取到另一台设备写入的位置。
  Future<void> primeResumePosition(String? playableKey) async {
    if (playableKey == null ||
        _loadedItem?.playableKey == playableKey ||
        _pendingSeek != null) {
      return;
    }
    final MusicPlaybackProgress? progress;
    try {
      progress = await _progressRepository.loadForRestore(playableKey);
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('[MusicPlaybackProgress] 读取恢复进度失败: $error');
      }
      return;
    }
    if (progress == null || progress.completed) {
      return;
    }
    final target = Duration(seconds: progress.positionSeconds);
    final duration = Duration(seconds: progress.durationSeconds);
    // 存到距结尾 5 秒以内按“已听完”处理：重开这段录音时从头放，
    // 而不是停在最后一帧让用户以为还在播。
    if (target <= Duration.zero ||
        (progress.durationSeconds > 0 &&
            target >= duration - const Duration(seconds: 5))) {
      return;
    }
    if (_loadedItem?.playableKey == playableKey || _pendingSeek != null) {
      return;
    }
    _pendingSeek = (playableKey: playableKey, position: target);
  }

  /// 受控跳转：所有用户发起的进度跳转都走这里，而不是直接操作播放器。
  ///
  /// 切歌时 `_openItem` 会消费待生效跳转；若此刻用户点了歌词行或拖了进度条，
  /// 目标位置先记下来，加载完成后对同一曲目生效；曲目已加载时立即跳转。
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
    // 竞态兜底：open 路径在“消费 pending”与“标记已加载”之间留有窗口，
    // seekTo 恰好落在窗口内时 pending 无人消费，这里直接补一次跳转。
    final pending = _pendingSeek;
    if (pending != null && _loadedItem?.playableKey == pending.playableKey) {
      _pendingSeek = null;
      await _player.seek(pending.position);
    }
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

  Future<void> _renewPlaybackPlan(
    MusicCenterState current,
    MusicPlayableItem item,
    MusicPlaybackPlan plan,
    Duration resumePosition,
  ) async {
    if (_renewingPlan) {
      return;
    }
    final now = DateTime.now();
    if (_lastRenewedPlanUrl == plan.url &&
        _lastPlanRenewalAttemptAt != null &&
        now.difference(_lastPlanRenewalAttemptAt!) < _planRenewalCooldown) {
      return;
    }
    _renewingPlan = true;
    _lastRenewedPlanUrl = plan.url;
    _lastPlanRenewalAttemptAt = now;
    final wasPlaying = current.isPlaying;
    try {
      if (resumePosition > Duration.zero) {
        _pendingSeek = (
          playableKey: item.playableKey,
          position: resumePosition,
        );
      }
      await _persistCurrent();
      final controller = ref.read(musicCenterControllerProvider.notifier);
      if (current.playbackIndex >= 0 &&
          current.playbackIndex < current.playbackItems.length &&
          current.playbackItems[current.playbackIndex].playableKey ==
              item.playableKey) {
        await controller.playQueueIndex(current.playbackIndex);
      } else {
        await controller.playActiveTrack();
      }
      if (!ref.mounted) {
        return;
      }
      if (!wasPlaying) {
        await controller.setPlaying(false);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('[_renewPlaybackPlan] 续签播放计划失败: $error');
      }
    } finally {
      _renewingPlan = false;
    }
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
    final expiresAt = plan.expiresAt;
    if (expiresAt != null) {
      final now = DateTime.now();
      final isExpired = now.isAfter(expiresAt);
      final isNearExpiry = now.isAfter(expiresAt.subtract(_planRenewalLead));
      if (isNearExpiry &&
          (_loadedItem?.playableKey == item.playableKey || current.isPlaying)) {
        // 令牌临近或已过期：记录当前进度并静默触发重拉播放计划续播，
        // 不再清空 _loadedUrl/_loadedItem，避免收藏或刷新时从 00:00 重头播放。
        final resumePosition =
            _loadedItem?.playableKey == item.playableKey
                ? _player.state.position
                : Duration.zero;
        unawaited(_renewPlaybackPlan(current, item, plan, resumePosition));
        if (isExpired) {
          return;
        }
      } else if (isExpired) {
        return;
      }
    }
    if (_loadedUrl != plan.url ||
        _loadedItem?.playableKey != item.playableKey) {
      await _openItem(item, plan.url, play: current.isPlaying);
      return;
    }
    final pendingSeek = _takePendingSeek(item.playableKey);
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
    if (pendingSeek != null) {
      await _player.seek(pendingSeek);
    }
  }

  Future<void> _openItem(
    MusicPlayableItem item,
    String url, {
    required bool play,
  }) async {
    try {
      final sameLoadedItem =
          _loadedItem?.playableKey == item.playableKey &&
          !_completedForLoadedItem;
      final livePosition =
          sameLoadedItem && _player.state.position > Duration.zero
              ? _player.state.position
              : null;
      if (_loadedItem != null && _player.state.playing) {
        await _player.pause();
      }
      await _persistCurrent();
      final pendingSeek = _takePendingSeek(item.playableKey) ?? livePosition;
      final shouldSeek = pendingSeek != null && pendingSeek > Duration.zero;
      await openMusicAudio(_player, url, play: play && !shouldSeek);
      if (shouldSeek) {
        await _player.seek(pendingSeek);
      }
      _loadedUrl = url;
      _loadedItem = item;
      _completedForLoadedItem = false;
      _lastSavedSecond = shouldSeek ? pendingSeek.inSeconds : 0;
      final latestItem =
          ref.read(musicCenterControllerProvider).asData?.value.currentItem;
      if (latestItem?.playableKey != item.playableKey) {
        if (play && !shouldSeek) {
          await _player.pause();
        }
        return;
      }
      if (play && shouldSeek) {
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
    _recordListeningPosition(position);
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

  Future<void> attachListeningHistory(
    String historyId,
    String playableKey,
  ) async {
    if (!ref.mounted || _listeningPlayableKey != playableKey) {
      return;
    }
    _listeningHistoryId = historyId;
    _listenedMilliseconds = 0;
    _reportedListeningSeconds = 0;
    final center = ref.read(musicCenterControllerProvider).asData?.value;
    final playing = center?.isPlaying == true && _player.state.playing;
    _resetListeningBaseline(
      playing ? _player.state.position : null,
      playing: playing,
    );
    await _reportListeningDuration();
  }

  void _syncListeningState(AsyncValue<MusicCenterState> next) {
    final center = next.asData?.value;
    if (center == null) {
      return;
    }
    final key = center.currentItem?.playableKey;
    if (key != _listeningPlayableKey) {
      unawaited(_reportListeningDuration());
      _listeningPlayableKey = key;
      _listeningHistoryId = null;
      _listenedMilliseconds = 0;
      _reportedListeningSeconds = 0;
    }
    final playing = key != null && center.isPlaying && _player.state.playing;
    _resetListeningBaseline(
      playing ? _player.state.position : null,
      playing: playing,
    );
    if (!playing) {
      unawaited(_reportListeningDuration());
    }
  }

  void _recordListeningPosition(Duration position) {
    if (!ref.mounted) {
      return;
    }
    final center = ref.read(musicCenterControllerProvider).asData?.value;
    final key = center?.currentItem?.playableKey;
    final playing =
        center?.isPlaying == true &&
        _player.state.playing &&
        key != null &&
        key == _listeningPlayableKey &&
        key == _loadedItem?.playableKey;
    if (!playing) {
      _resetListeningBaseline(null, playing: false);
      return;
    }
    final previousPosition = _lastListeningPosition;
    final elapsedMilliseconds = _listeningClock.elapsedMilliseconds;
    if (previousPosition != null &&
        elapsedMilliseconds > 0 &&
        elapsedMilliseconds <= 5000) {
      final positionDelta =
          position.inMilliseconds - previousPosition.inMilliseconds;
      final expectedMaximum =
          (elapsedMilliseconds * _player.state.speed + 1000).round();
      if (positionDelta > 0 && positionDelta <= expectedMaximum) {
        _listenedMilliseconds += elapsedMilliseconds;
      }
    }
    _resetListeningBaseline(position, playing: true);
    final listenedSeconds = _listenedMilliseconds ~/ 1000;
    if (_listeningHistoryId != null &&
        listenedSeconds - _reportedListeningSeconds >= 15) {
      unawaited(_reportListeningDuration());
    }
  }

  void _resetListeningBaseline(Duration? position, {required bool playing}) {
    _listeningClock.stop();
    _listeningClock.reset();
    _lastListeningPosition = position;
    if (playing) {
      _listeningClock.start();
    }
  }

  Future<void> _reportListeningDuration() {
    final activeWrite = _listeningWriteFuture;
    if (activeWrite != null) {
      return activeWrite;
    }
    final historyId = _listeningHistoryId;
    final playableKey = _listeningPlayableKey;
    final listenedSeconds = _listenedMilliseconds ~/ 1000;
    if (historyId == null ||
        playableKey == null ||
        listenedSeconds <= _reportedListeningSeconds) {
      return Future<void>.value();
    }
    final previousReportedSeconds = _reportedListeningSeconds;
    final future = _writeListeningDuration(
      historyId,
      playableKey,
      listenedSeconds,
      previousReportedSeconds,
    );
    _listeningWriteFuture = future;
    return future;
  }

  Future<void> _writeListeningDuration(
    String historyId,
    String playableKey,
    int listenedSeconds,
    int previousReportedSeconds,
  ) async {
    var saved = false;
    try {
      final storedSeconds = await ref
          .read(musicApiProvider)
          .updateListeningDuration(historyId, listenedSeconds);
      if (!ref.mounted) {
        return;
      }
      final addedSeconds = storedSeconds - previousReportedSeconds;
      if (addedSeconds > 0) {
        ref
            .read(musicCenterControllerProvider.notifier)
            .addWeekListeningSeconds(addedSeconds);
      }
      if (_listeningHistoryId == historyId &&
          _listeningPlayableKey == playableKey) {
        _reportedListeningSeconds = storedSeconds;
      }
      saved = true;
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('[MusicListening] 时长上报失败: ${error.runtimeType}');
      }
    } finally {
      _listeningWriteFuture = null;
      if (saved &&
          _listeningHistoryId == historyId &&
          _listeningPlayableKey == playableKey &&
          _listenedMilliseconds ~/ 1000 - _reportedListeningSeconds >= 15) {
        unawaited(_reportListeningDuration());
      }
    }
  }

  Future<void> _handleCompleted() async {
    // 单曲循环会重播同一地址：先记录播完事实，同步链路据此走重放而不是空 play()。
    _completedForLoadedItem = true;
    await _persistCurrent(completed: true);
    // 睡眠定时器选了「播完当前曲目停止」时不再自动切下一首。
    final stoppedBySleepTimer =
        await ref
            .read(musicSleepTimerControllerProvider.notifier)
            .onTrackCompleted();
    if (stoppedBySleepTimer) {
      return;
    }
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
