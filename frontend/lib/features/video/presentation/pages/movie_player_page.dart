import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/platform/android/pip_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/movie_playback_service.dart';
import 'package:omninest/features/video/application/video_local_preferences_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart'
    hide SubtitleTrack;
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_behavior.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_center_controls.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_bottom_bar.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_sheets.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_status_overlay.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_stream_notice.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_subtitle_overlay.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_top_bar.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_file_decoder.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_parser.dart';

part 'movie_player_page_interactions.dart';
part 'movie_player_page_tracks.dart';

class MoviePlayerPage extends ConsumerStatefulWidget {
  const MoviePlayerPage({required this.videoItemId, super.key});

  final String videoItemId;

  @override
  ConsumerState<MoviePlayerPage> createState() => _MoviePlayerPageState();
}

class _MoviePlayerPageState extends ConsumerState<MoviePlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  String? _loadedUrl;
  Timer? _progressTimer;
  late final MoviePlaybackService _playbackService;
  late final WindowChromeController _windowChromeController;
  WindowChromeLease? _windowChromeLease;
  int _currentDurationSeconds = 0;
  int _openGeneration = 0;
  int _seekGeneration = 0;
  int _subtitleGeneration = 0;

  // 播放器状态
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _feedbackTimer;
  final MoviePlayerCommandGate _playPauseGate = MoviePlayerCommandGate();
  bool _playPausePending = false;
  bool _controlPanelOpen = false;
  _PlayerFeedback? _feedback;
  double _playbackSpeed = 1.0;
  int? _activeSubtitleId;
  List<AudioTrack> _availableAudioTracks = const [];
  List<SubtitleTrack> _availableEmbeddedSubtitles = const [];
  String? _activeAudioTrackId;
  SubtitleTrack? _importedSubtitle;
  // Web 端自定义字幕覆盖（media_kit 的 SubtitleTrack 在 MSE 模式下不生效）
  List<SubtitleCue> _subtitleCues = [];
  // 仅在活动字幕变化时触发 overlay 重建，避免每帧刷新导致视频卡顿
  final ValueNotifier<int> _activeCueIndex = ValueNotifier<int>(-1);
  StreamSubscription<Duration>? _subtitlePositionSub;
  double? _aspectRatio; // null = 原始比例
  bool _isFill = false;
  // 音频模式：'cached' = 使用缓存 AAC，'original' = 使用原始音频（实时转码）
  String _audioMode = 'cached';

  // 拖动状态 — 解决进度条跳回起点
  bool _isSeeking = false;
  // seek 后保留起始位置，防止 _openIfNeeded 重新从头打开
  int _seekStart = 0;

  // 音量状态
  double _volume = 100;
  bool _isMuted = false;
  double _volumeBeforeMute = 100;
  final ValueNotifier<double> _volumeListenable = ValueNotifier<double>(100);
  final ValueNotifier<double> _seekListenable = ValueNotifier<double>(0);

  // 缓冲状态
  bool _isBuffering = false;
  StreamSubscription<bool>? _bufferingSub;
  // 缓冲前是否正在播放（用于缓冲结束后自动恢复）
  bool _wasPlayingBeforeBuffering = false;
  double _bufferProgress = 0.0;
  Timer? _bufferPollTimer;
  // 位置轮询 — fMP4 流的 timeupdate 事件频率不足，定时器保证进度条平滑更新
  // 使用 ValueNotifier 避免 setState 重建整棵 widget 树（含 Video 组件）
  final ValueNotifier<Duration> _polledPosition = ValueNotifier<Duration>(
    Duration.zero,
  );
  Timer? _positionPollTimer;
  StreamSubscription<Tracks>? _tracksSub;

  // Web 端转码模式提示（可关闭）
  bool _showStreamNotice = true;

  // 音频缓存提示：仅显示一次（跨刷新持久化）
  bool _audioNoticeChecked = false;

  // Android PiP：播放页活跃时退后台进画中画；PiP 态仅保留画面与进度。
  VoidCallback? _pipListenerDisposer;
  bool _isInPipMode = false;

  static const _hideDelay = Duration(milliseconds: 2800);
  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  void _updateState(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _playbackService = ref.read(moviePlaybackServiceProvider);
    _windowChromeController = ref.read(windowChromeControllerProvider.notifier);
    // 显式设置音量，确保有声音
    _player.setVolume(_volume);
    _startHideTimer();
    if (isMobilePlatform) {
      // 租约会同步修改 Provider 状态，延迟到首帧后获取。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _windowChromeLease = _windowChromeController.acquireImmersive(
          owner: 'video.player.${widget.videoItemId}',
        );
      });
    }

    unawaited(PipService.instance().setVideoPlaybackActive(active: true));
    _pipListenerDisposer = PipService.instance().addListener((inPipMode) {
      if (!mounted) return;
      setState(() {
        _isInPipMode = inPipMode;
        // PiP 态固定显示精简界面（画面 + 进度），隐藏交互控制层。
        _showControls = !inPipMode;
      });
    });
  }

  @override
  void dispose() {
    _openGeneration++;
    _seekGeneration++;
    _subtitleGeneration++;
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _tracksSub?.cancel();
    _bufferingSub?.cancel();
    _bufferPollTimer?.cancel();
    _positionPollTimer?.cancel();
    _subtitlePositionSub?.cancel();
    _activeCueIndex.dispose();
    _polledPosition.dispose();
    _volumeListenable.dispose();
    _seekListenable.dispose();
    unawaited(_syncCurrentProgress());
    unawaited(PipService.instance().setVideoPlaybackActive(active: false));
    _pipListenerDisposer?.call();
    _player.dispose();
    _windowChromeLease?.release();
    super.dispose();
  }

  AsyncValue<PlaybackPlan> _readPlaybackPlan() {
    return ref.read(moviePlaybackPlanProvider(widget.videoItemId));
  }

  void _invalidatePlaybackPlan() {
    ref.invalidate(moviePlaybackPlanProvider(widget.videoItemId));
  }

  Future<void> _syncAndRefreshHistory() async {
    await _syncCurrentProgress();
    if (!mounted) {
      return;
    }
    // 原地静默刷新：保留当前视图（避免返回继续观看时整页骨架闪动），
    // 刷新失败可忽略——进度已由 _syncCurrentProgress 落库。
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .refreshForRealtime();
    } on Exception catch (error) {
      debugPrint('[_syncAndRefreshHistory] 静默刷新失败: $error');
    }
  }

  Future<void> _exitPlayer() async {
    await _syncAndRefreshHistory();
    if (!mounted) {
      return;
    }
    // 返回来源页（详情页 / 继续观看等）；深链直入播放器时兜底回影视中心。
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/video');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chromeState = ref.watch(windowChromeControllerProvider);
    final isFullscreen =
        isDesktopPlatform ? chromeState.isFullscreen : fs.isFullscreen;
    final plan = ref.watch(moviePlaybackPlanProvider(widget.videoItemId));
    final item =
        ref.watch(movieDetailProvider(widget.videoItemId)).asData?.value;
    final navigation = _watchEpisodeNavigation(item);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: plan.when(
              data: (value) {
                _openIfNeeded(value);
                return _buildPlayer(
                  value,
                  isFullscreen: isFullscreen,
                  title:
                      item?.title ?? AppLocalizations.of(context).videoUnknown,
                  subtitle: _episodeContext(item),
                  previousEpisode: navigation.previous,
                  nextEpisode: navigation.next,
                );
              },
              error: (error, stackTrace) {
                debugPrint('[_build] 播放计划加载失败: $error');
                return AppErrorView(
                  message: movieErrorMessage(
                    error,
                    AppLocalizations.of(context),
                  ),
                  onRetry: _invalidatePlaybackPlan,
                );
              },
              loading: () => const AppLoading.simple(),
            ),
          ),
          if (plan is AsyncLoading<PlaybackPlan> ||
              plan is AsyncError<PlaybackPlan>)
            MoviePlayerFallbackBackButton(
              tooltip: AppLocalizations.of(context).coreBack,
              onPressed: () => unawaited(_exitPlayer()),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayer(
    PlaybackPlan plan, {
    required bool isFullscreen,
    required String title,
    String? subtitle,
    MovieVideoItem? previousEpisode,
    MovieVideoItem? nextEpisode,
  }) {
    // 使用 Focus 替代 KeyboardListener：
    // KeyboardListener 会抢占焦点，鼠标移出播放器区域时焦点丢失导致视频暂停。
    // Focus + autofocus 确保键盘事件正常工作，同时不干扰视频播放焦点。
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        return _handleKey(
          event,
          plan,
          isFullscreen: isFullscreen,
          previousEpisode: previousEpisode,
          nextEpisode: nextEpisode,
        );
      },
      child: MouseRegion(
        onHover: (_) => _onMouseActivity(),
        child: Stack(
          children: [
            // 视频 — 默认 BoxFit.contain 填满可用空间并保持原始比例
            // 铺满模式用 BoxFit.cover，用户手动选择比例时用 AspectRatio 包裹
            Positioned.fill(
              child:
                  _isFill
                      ? Video(
                        controller: _controller,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      )
                      : _aspectRatio != null
                      ? Center(
                        child: AspectRatio(
                          aspectRatio: _aspectRatio!,
                          child: Video(
                            controller: _controller,
                            controls: NoVideoControls,
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                      : Video(
                        controller: _controller,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _handleSurfaceTap,
                onDoubleTapDown:
                    (details) => _handleSurfaceDoubleTap(
                      details,
                      MediaQuery.sizeOf(context).width,
                    ),
              ),
            ),
            // 字幕覆盖层（Web 端自定义渲染）
            if (_subtitleCues.isNotEmpty)
              SubtitleOverlay(
                cues: _subtitleCues,
                activeCueIndex: _activeCueIndex,
                controlsVisible: _showControls && !_isInPipMode,
                isMobile: isMobilePlatform,
              ),
            // Web 端转码模式提示
            if (isWebPlatform && plan.streamUrl != null && _showStreamNotice)
              StreamNotice(
                videoCodec: plan.videoCodec,
                audioCodec: plan.audioCodec,
                container: plan.container,
                onDismiss: () => setState(() => _showStreamNotice = false),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showControls || _isInPipMode,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration:
                      MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Stack(
                    children: [
                      MoviePlayerTopBar(
                        title: title,
                        subtitle: subtitle,
                        isMobile: isMobilePlatform,
                        onBack: _exitPlayer,
                        onInfoTap:
                            isMobilePlatform
                                ? () => _showSettingsPanel(plan)
                                : () => _showInfoPanel(plan),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: _seekListenable,
                        builder: (context, seekValue, _) {
                          return ValueListenableBuilder<double>(
                            valueListenable: _volumeListenable,
                            builder: (context, volume, _) {
                              return MoviePlayerBottomBar(
                                plan: plan,
                                polledPosition: _polledPosition,
                                playerDuration: _player.state.duration,
                                bufferProgress: _bufferProgress,
                                isSeeking: _isSeeking,
                                seekValue: seekValue,
                                onSeekStart: (v) {
                                  setState(() {
                                    _isSeeking = true;
                                  });
                                  _seekListenable.value = v;
                                },
                                onSeeking: (v) {
                                  _seekListenable.value = v;
                                },
                                onSeekEnd: (v) {
                                  final dur =
                                      plan.durationSeconds > 0
                                          ? Duration(
                                            seconds: plan.durationSeconds,
                                          )
                                          : _player.state.duration;
                                  final target = Duration(
                                    milliseconds:
                                        (v * dur.inMilliseconds).round(),
                                  );
                                  _seekToPosition(target).then((_) {
                                    if (mounted) {
                                      setState(() => _isSeeking = false);
                                    }
                                  });
                                },
                                onMouseActivity: _onMouseActivity,
                                volume: volume,
                                isMuted: _isMuted,
                                onToggleMute: _toggleMute,
                                onVolumeChanged: (v) {
                                  _volume = v;
                                  _isMuted = v <= 0;
                                  _volumeListenable.value = v;
                                  setState(() {});
                                },
                                setPlayerVolume: _player.setVolume,
                                playbackSpeed: _playbackSpeed,
                                activeSubtitleId: _activeSubtitleId,
                                onAudioTap:
                                    _hasAudioControls(plan)
                                        ? () => _showAudioPanel(plan)
                                        : null,
                                onSubtitleTap: () => _showSubtitlePanel(plan),
                                onSpeedTap: _showSpeedPanel,
                                onSettingsTap: () => _showSettingsPanel(plan),
                                onFullscreenTap: _toggleFullscreen,
                                isFullscreen: isFullscreen,
                                formatDuration: formatMoviePlayerDuration,
                                playing: _player.stream.playing,
                                onPlayPause:
                                    () => unawaited(_requestPlayPause()),
                                isMobile: isMobilePlatform,
                                onPreviousEpisode:
                                    previousEpisode == null
                                        ? null
                                        : () => unawaited(
                                          _playEpisode(previousEpisode),
                                        ),
                                onNextEpisode:
                                    nextEpisode == null
                                        ? null
                                        : () => unawaited(
                                          _playEpisode(nextEpisode),
                                        ),
                              );
                            },
                          );
                        },
                      ),
                      if (!_isBuffering)
                        MoviePlayerCenterControls(
                          playing: _player.stream.playing,
                          isMobile: isMobilePlatform,
                          onPlayPause: () => unawaited(_requestPlayPause()),
                          onSeekBackward: () => _seekWithFeedback(-10),
                          onSeekForward: () => _seekWithFeedback(10),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 缓冲指示器
            if (_isBuffering) const MoviePlayerBufferingIndicator(),
            if (_feedback case final feedback?)
              MoviePlayerActionFeedback(
                key: ValueKey(feedback.sequence),
                icon: feedback.icon,
                label: feedback.label,
                placement: feedback.placement,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncCurrentProgress() async {
    if (_loadedUrl == null || _isSeeking) return;
    final position = _player.state.position.inSeconds;
    final playerDur = _player.state.duration.inSeconds;
    // fMP4 流的 duration 不可靠，优先使用播放计划的时长
    final duration =
        _currentDurationSeconds > 0 ? _currentDurationSeconds : playerDur;
    if (position <= 0 && duration <= 0) return;
    try {
      await _playbackService.updateProgress(
        videoItemId: widget.videoItemId,
        positionSeconds: position,
        durationSeconds: duration,
        completed: isMoviePlaybackCompleted(position, duration),
      );
    } catch (_) {
      debugPrint('播放进度同步失败');
    }
  }

  void _startProgressSync(PlaybackPlan plan) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_isSeeking) return;
      final position = _player.state.position.inSeconds;
      final duration =
          _player.state.duration.inSeconds > 0
              ? _player.state.duration.inSeconds
              : plan.durationSeconds;
      if (position <= 0 && duration <= 0) return;
      try {
        await _playbackService.updateProgress(
          videoItemId: widget.videoItemId,
          positionSeconds: position,
          durationSeconds: duration,
          completed: isMoviePlaybackCompleted(position, duration),
        );
      } catch (_) {
        debugPrint('周期性进度同步失败');
      }
    });
  }

  void _seekRelative(int seconds) {
    final current = _player.state.position;
    final target = current + Duration(seconds: seconds);
    _seekToPosition(target);
  }

  /// Seek 策略：
  /// - 非 Web 端（Desktop/Android）：libmpv 原生 seek，直接调用
  /// - Web 端 fMP4 流：尝试原生 seek，若失败则重新打开流从目标位置开始
  Future<void> _seekToPosition(Duration target) async {
    final generation = ++_seekGeneration;
    if (!mounted || generation != _seekGeneration) return;
    if (!isWebPlatform) {
      await _player.seek(target);
      if (!mounted || generation != _seekGeneration) return;
      return;
    }
    final asyncValue = _readPlaybackPlan();
    PlaybackPlan? plan;
    if (asyncValue is AsyncData<PlaybackPlan>) {
      plan = asyncValue.value;
    }
    if (plan?.streamUrl == null || plan!.streamUrl!.isEmpty) {
      await _player.seek(target);
      if (!mounted || generation != _seekGeneration) return;
      return;
    }
    // Web 端 fMP4 流模式：尝试原生 seek，失败则重新打开流
    final targetSeconds = clampMovieSeekSeconds(target, plan.durationSeconds);
    await _player.seek(Duration(seconds: targetSeconds));
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted || generation != _seekGeneration) return;
    final posAfter = _player.state.position;
    final driftMs = (posAfter.inMilliseconds - targetSeconds * 1000).abs();
    if (driftMs < 5000) {
      _polledPosition.value = posAfter;
      setState(() {
        _isSeeking = false;
      });
      return;
    }
    // 原生 seek 未生效，重新打开流从目标位置开始
    debugPrint(
      '[_seekToPosition] 原生 seek 未生效，回退到流重开: targetSeconds=$targetSeconds',
    );
    _polledPosition.value = Duration(seconds: targetSeconds);
    setState(() {
      _seekStart = targetSeconds;
      _loadedUrl = null;
    });
  }

  void _selectSubtitle(PlaybackSubtitle sub) {
    final generation = ++_subtitleGeneration;
    setState(() => _activeSubtitleId = sub.id.hashCode);
    if (isWebPlatform) {
      // Web 端：media_kit 的 SubtitleTrack 在 MSE 模式下不生效，
      // 改用自定义 WebVTT 覆盖层。
      // 内嵌字幕已在探测时提取为 WebVTT 存储到 MinIO，url 为 presigned URL。
      if (sub.url != null && sub.url!.isNotEmpty) {
        _fetchAndDisplayWebVTT(sub.url!, generation);
      }
    } else if (sub.isEmbedded) {
      // Desktop/Android：内嵌字幕按 stream index 选择（libmpv 原生支持）
      _player.setSubtitleTrack(
        SubtitleTrack('${sub.streamIndex}', sub.label, sub.language),
      );
    } else if (sub.isExternal) {
      // Desktop/Android 外挂字幕
      _player.setSubtitleTrack(
        SubtitleTrack.uri(sub.url!, title: sub.label, language: sub.language),
      );
    } else {
      _player.setSubtitleTrack(SubtitleTrack.auto());
    }
  }

  void _selectEmbeddedSubtitle(SubtitleTrack track) {
    final generation = ++_subtitleGeneration;
    setState(() => _activeSubtitleId = track.id.hashCode);
    if (track.data) {
      final cues = parseSubtitleContent(track.id);
      if (isWebPlatform) {
        _displaySubtitleCues(cues, generation);
      } else {
        _player.setSubtitleTrack(track);
      }
      return;
    }
    if (!isWebPlatform) {
      _player.setSubtitleTrack(track);
    }
  }

  Future<void> _importSubtitle() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) {
        return;
      }
      final file = result.files.first;
      if (file.size > maxLocalSubtitleBytes) {
        showMovieFeedback(
          context,
          l10n.videoSubtitleFileTooLarge,
          isError: true,
        );
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        showMovieFeedback(
          context,
          l10n.videoSubtitleImportFailed,
          isError: true,
        );
        return;
      }
      final content = decodeSubtitleFile(bytes);
      final cues = parseSubtitleContent(content);
      if (cues.isEmpty) {
        showMovieFeedback(context, l10n.videoSubtitleNoCues, isError: true);
        return;
      }
      final track = SubtitleTrack.data(
        content,
        title: file.name,
        language: inferSubtitleLanguage(file.name),
      );
      if (!mounted) {
        return;
      }
      final generation = ++_subtitleGeneration;
      setState(() {
        _importedSubtitle = track;
        _activeSubtitleId = track.id.hashCode;
      });
      if (isWebPlatform) {
        _displaySubtitleCues(cues, generation);
      } else {
        await _player.setSubtitleTrack(track);
      }
      if (mounted) {
        showMovieFeedback(context, l10n.videoSubtitleImportSuccess);
      }
    } on Object {
      if (mounted) {
        showMovieFeedback(
          context,
          l10n.videoSubtitleImportFailed,
          isError: true,
        );
      }
    }
  }

  void _disableSubtitle() {
    _subtitleGeneration++;
    setState(() {
      _activeSubtitleId = null;
      _subtitleCues = [];
    });
    _activeCueIndex.value = -1;
    _subtitlePositionSub?.cancel();
    _subtitlePositionSub = null;
    if (!isWebPlatform) {
      _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  /// 获取 WebVTT 字幕并以自定义覆盖层显示（Web 端专用）
  Future<void> _fetchAndDisplayWebVTT(String url, int generation) async {
    try {
      final subtitleContent = await _playbackService.loadSubtitle(url);
      if (!mounted || generation != _subtitleGeneration) return;
      debugPrint('字幕内容长度: ${subtitleContent.length}');
      final cues = parseSubtitleContent(subtitleContent);
      debugPrint('字幕解析完成: ${cues.length} 条字幕');
      _displaySubtitleCues(cues, generation);
    } catch (_) {
      debugPrint('WebVTT 获取失败');
    }
  }

  void _displaySubtitleCues(List<SubtitleCue> cues, int generation) {
    if (!mounted || generation != _subtitleGeneration) return;
    _subtitlePositionSub?.cancel();
    setState(() => _subtitleCues = cues);
    _activeCueIndex.value = -1;
    var lastIndex = -1;
    _subtitlePositionSub = _player.stream.position.listen((position) {
      if (!mounted || _subtitleCues.isEmpty) return;
      final newIndex = findActiveSubtitleCueIndex(_subtitleCues, position);
      if (newIndex != lastIndex) {
        lastIndex = newIndex;
        _activeCueIndex.value = newIndex;
      }
    });
  }

  void _toggleSubtitle(PlaybackPlan plan) {
    if (_activeSubtitleId != null) {
      _disableSubtitle();
    } else if (plan.subtitles.isNotEmpty) {
      _selectSubtitle(plan.subtitles.first);
    } else if (_availableEmbeddedSubtitles.isNotEmpty) {
      _selectEmbeddedSubtitle(_availableEmbeddedSubtitles.first);
    } else if (_importedSubtitle case final imported?) {
      _selectEmbeddedSubtitle(imported);
    }
  }

  void _toggleMute() {
    setState(() {
      if (_isMuted) {
        _volume = _volumeBeforeMute > 0 ? _volumeBeforeMute : 80;
        _isMuted = false;
      } else {
        _volumeBeforeMute = _volume;
        _volume = 0;
        _isMuted = true;
      }
    });
    _player.setVolume(_volume);
  }

  void _toggleFullscreen() {
    if (isDesktopPlatform) {
      final lease = _windowChromeLease;
      if (lease == null) {
        _windowChromeLease = _windowChromeController.acquireFullscreen(
          owner: 'video.player.${widget.videoItemId}',
        );
      } else {
        lease.release();
        _windowChromeLease = null;
      }
      return;
    }
    fs.toggleFullscreen();
    // 全屏状态变化后需要重建 UI 以更新图标
    if (mounted) setState(() {});
  }

  void _cycleAspectRatio() {
    final currentIndex = AspectRatioOption.options(context).indexWhere((o) {
      if (o.isFill) return _isFill;
      if (_isFill) return false;
      if (o.ratio == null) return _aspectRatio == null;
      return _aspectRatio == o.ratio;
    });
    final nextIndex =
        (currentIndex + 1) % AspectRatioOption.options(context).length;
    final next = AspectRatioOption.options(context)[nextIndex];
    setState(() {
      _aspectRatio = next.ratio;
      _isFill = next.isFill;
    });
  }
}
