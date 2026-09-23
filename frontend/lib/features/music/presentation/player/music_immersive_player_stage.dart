part of 'music_immersive_player.dart';

/// 舞台分区的错峰进场揭示：整层的淡入+推近由宿主（Portal overlay 或甲板
/// 覆盖层）负责，这里只让封面与歌词依次落位，形成层次而不是整体闪一下。
///
/// 不透明度起点故意不为 0：`RenderOpacity` 在 alpha == 0 时不参与命中测试，
/// 揭示期间会让悬停与点击同时落空；同理不做位移，避免扰动以几何为准的断言。
class _StageReveal extends StatefulWidget {
  const _StageReveal({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_StageReveal> createState() => _StageRevealState();
}

class _StageRevealState extends State<_StageReveal>
    with SingleTickerProviderStateMixin {
  static const double _startOpacity = 0.35;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  Timer? _startTimer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    // 减少动效偏好只能在依赖就绪后读取：initState 里取 MediaQuery 会抛
    // dependOnInheritedWidgetOfExactType 断言。
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _controller.value = _startOpacity;
    // 计时器必须可取消：否则用例结束时仍挂着 pending timer，flutter_test 报错。
    _startTimer = Timer(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.value >= 1) {
      return widget.child;
    }
    return FadeTransition(
      opacity: Tween<double>(begin: _startOpacity, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      ),
      child: widget.child,
    );
  }
}

class _MusicImmersivePlayerStage extends ConsumerStatefulWidget {
  const _MusicImmersivePlayerStage({
    required this.palette,
    required this.reservedTopInset,
  });

  final MusicImmersivePalette palette;
  final double reservedTopInset;

  @override
  ConsumerState<_MusicImmersivePlayerStage> createState() =>
      _MusicImmersivePlayerStageState();
}

class _MusicImmersivePlayerStageState
    extends ConsumerState<_MusicImmersivePlayerStage> {
  int _deckIndex = 0;

  /// `_deckIndex` 属于哪首曲目：换曲时在 build 期直接重算，避免先画
  /// 第 0 张卡再 post-frame 纠正造成的跳卡。
  String? _deckIndexTrackId;
  bool _syncScheduled = false;
  bool _deckExpanded = false;
  bool _visualEditorOpen = false;
  PortalMusicVisualizerSettings? _previewVisual;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _schedulePlaybackSync();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(musicCenterControllerProvider, (previous, next) {
      _schedulePlaybackSync();
    });
    final center = ref.watch(musicCenterControllerProvider);
    final session = ref.watch(musicPlaybackSessionProvider);
    final preferences =
        ref.watch(musicVisualizerPreferencesProvider).asData?.value ??
        const PortalMusicVisualizerPreferences();
    final savedVisual = preferences.visual;
    // 桌面歌词形态由布局唯一决定：两侧布局恒为滚动歌词，居中布局为
    // 固定多行窗口；滚动/多行偏好只在移动端暴露。
    const lyricScrollMode = true;
    final visual = _previewVisual ?? savedVisual;
    final state = center.asData?.value;
    final track = state?.currentTrack ?? state?.activeTrack;
    // 曲目级歌词延迟覆盖（设备本地）：仅在解析完成后生效，未设置时退回全局校准。
    final trackOffsetMs =
        track == null
            ? null
            : ref.watch(musicTrackLyricOffsetProvider(track.id)).asData?.value;
    final lyrics = track?.lyricLines ?? const <MusicLyricLine>[];
    final isPlaying = state?.isPlaying == true && track != null;
    final deckTracks = _resolveDeckTracks(state, track);
    // 换曲时在同一帧内把卡组对齐到当前曲：留到 post-frame 会让首帧画成
    // 队列首张卡，随即触发整组重排与位移动画。
    if (_deckIndexTrackId != track?.id) {
      _deckIndexTrackId = track?.id;
      _deckIndex = _resolveDeckIndex(track, deckTracks) ?? _deckIndex;
    }
    final requestedLayout = visual.lyrics.layout;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTap: () => setState(() => _deckExpanded = !_deckExpanded),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (!width.isFinite ||
              !height.isFinite ||
              width <= 0 ||
              height <= 0) {
            return const SizedBox.shrink();
          }
          final size = Size(width, height);
          final scale = musicLayoutScale(size);
          // 样例构图不随窗口变形：窗口装不下两侧双列时降级为纵向串联构图。
          final layout = resolveMusicComposition(size, requestedLayout);
          final isCenter = layout == PortalMusicLayout.center;
          // 宿主自绘的顶部安全区（沉浸全屏时由外层传入）优先于样例页边距。
          final topPadding =
              math
                  .max(
                    kMusicLayoutPagePadding * scale,
                    widget.reservedTopInset + 12 * scale,
                  )
                  .toDouble();
          // 顶栏块：样例顶栏 + `my-2`，且不低于两行文字的实际排版高度与物理下限。
          final headerBlockHeight = musicHeaderBlockHeight(scale);
          final sideFrame = MusicSideLayoutFrame.resolve(
            size,
            topPadding: topPadding,
            headerHeight: headerBlockHeight,
          );
          final lyricSpec = resolveMusicLyricSpec(
            layout,
            scale,
            activeFontSizePx: visual.lyrics.activeFontSizePx,
            inactiveFontSizePx: visual.lyrics.inactiveFontSizePx,
            inactiveOpacity: visual.lyrics.inactiveOpacity,
            lineSpacing: visual.lyrics.lineSpacing,
            timeTagEnabled: visual.lyrics.timeTagEnabled,
            deckEnabled: visual.deckEnabled,
          );
          final centerFrame = MusicCenterLayoutFrame.resolve(
            size,
            topPadding: topPadding,
            headerHeight: headerBlockHeight,
            deckEnabled: visual.deckEnabled,
            // 居中布局同样在歌词窗口上方预留元信息带（三布局统一的头部）。
            lyricHeaderHeight:
                visual.lyrics.enabled ? kMusicLyricMetaRowHeight * scale : 0,
            lyricSlotHeight: lyricSpec.slotHeight(),
            lyricWindowLines: lyricSpec.fixedWindowLines,
          );
          final headerTop =
              isCenter ? centerFrame.headerTop : sideFrame.headerTop;
          final headerHeight =
              isCenter ? centerFrame.headerHeight : sideFrame.headerHeight;
          // 卡组与歌词列都用样例的列宽、容器上限与内边距精确推导。
          final deckRect =
              isCenter
                  ? centerFrame.deck.rect
                  : MusicDeckStageGeometry.resolveSide(
                    layout: layout,
                    sectionRect: sideFrame.deckSection(layout),
                    scale: scale,
                    // 卡组列纵向居中「舞台 + 音频参数胶囊」整组。
                    trailingHeight:
                        (musicDeckSpecGap(layout) + kMusicDeckSpecHeight) *
                        scale,
                  ).rect;
          final lyricSection = isCenter ? null : sideFrame.lyricSection(layout);
          final lyricRect =
              isCenter
                  ? centerFrame.lyricRect
                  : sideFrame.lyricViewport(layout);
          // 歌词列头部带矩形：三个布局统一（居右为样例原生，居左与居中
          // 为补齐的同一控件样式）。
          final lyricHeaderRect =
              isCenter
                  ? Rect.fromLTWH(
                    lyricRect.left,
                    lyricRect.top - kMusicLyricMetaRowHeight * scale,
                    lyricRect.width,
                    kMusicLyricMetaRowHeight * scale,
                  )
                  : lyricSection!.top >= 0
                  ? Rect.fromLTWH(
                    lyricSection.left,
                    lyricSection.top,
                    lyricSection.width,
                    kMusicLyricMetaRowHeight * scale,
                  )
                  : null;
          // 播放胶囊：样例 `max-w-5xl`（右侧布局 `max-w-6xl`）居中，
          final controlsHeight = kMusicFooterHeight * scale;
          final controlsBottom =
              kMusicLayoutPagePadding * scale +
              kMusicFooterBottomMargin * scale;
          final controlsAvailable =
              math.max(240.0, width - sideFrame.pagePadding * 2).toDouble();
          final controlsWidth =
              math
                  .min(controlsAvailable, musicFooterMaxWidth(layout) * scale)
                  .toDouble();
          final controlsLeft = (width - controlsWidth) / 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (visual.lyrics.enabled)
                Positioned.fromRect(
                  rect: lyricRect,
                  child: _StageReveal(
                    delay: const Duration(milliseconds: 110),
                    child: _ImmersiveLyrics(
                      palette: widget.palette,
                      player: session.player,
                      track: track,
                      lyrics: lyrics,
                      scale: scale,
                      lyricSettings: visual.lyrics,
                      lyricSpec: lyricSpec,
                      trackOffsetMs: trackOffsetMs,
                      onAdjustLyricOffset: _adjustTrackLyricOffset,
                      blockAnchor: lyricSpec.blockAnchor,
                      textAlign: lyricSpec.textAlign,
                      // 居中布局仅在堆叠卡片可见时用固定三行窗口，其余形态
                      // （两侧布局、居中关卡组）恒为滚动歌词；形态由 lyric
                      // 规格的 fixedWindowLines 决定，桌面不再手动切换。
                      lyricScrollMode: lyricSpec.fixedWindowLines == 0,
                      onPrevious: () {},
                      onTogglePlayback:
                          () => _runPlaybackCommand(
                            () =>
                                ref
                                    .read(
                                      musicCenterControllerProvider.notifier,
                                    )
                                    .togglePlayback(),
                          ),
                      onNext: () {},
                      onSeek:
                          (position) => ref
                              .read(musicPlaybackSessionProvider.notifier)
                              .seekTo(position),
                    ),
                  ),
                ),
              if (visual.player.enabled)
                Positioned(
                  left: controlsLeft,
                  width: controlsWidth,
                  bottom: controlsBottom,
                  height: controlsHeight,
                  child: _DigitalImmersiveGlassPlayerControls(
                    player: session.player,
                    track: track,
                    isPlaying: isPlaying,
                    settings: visual.player,
                    scale: scale,
                    width: controlsWidth,
                    onPrevious:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .previousTrack(),
                        ),
                    onTogglePlayback:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .togglePlayback(),
                        ),
                    onNext:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .nextTrack(),
                        ),
                    onSeek:
                        (position) => ref
                            .read(musicPlaybackSessionProvider.notifier)
                            .seekTo(position),
                  ),
                ),
              Positioned(
                top: headerTop,
                left: sideFrame.pagePadding,
                right: sideFrame.pagePadding,
                // 文字行盒会在物理像素上取整，小数缩放下两行文字可能比推导
                // 高度高出约 1px：放宽渲染盒而不是收紧文字，避免 RenderFlex 溢出。
                height: math.max(
                  headerHeight,
                  musicHeaderContentHeight(scale) + 1,
                ),
                child: _DigitalImmersiveTrackHeader(
                  palette: widget.palette,
                  track: track,
                  scale: scale,
                ),
              ),
              if (!_visualEditorOpen)
                Positioned(
                  top: headerTop + 8,
                  right: sideFrame.pagePadding,
                  child: _GlassIconButton(
                    palette: widget.palette,
                    tooltip:
                        AppLocalizations.of(context).portalMusicVisualizerEdit,
                    icon: Icons.tune_rounded,
                    onTap: _openVisualEditor,
                  ),
                ),
              // 堆叠卡片可开关：关闭时卡组与其下方音频参数胶囊一并隐藏，
              // 歌词与底部播放器不受影响。
              if (visual.deckEnabled)
                Positioned.fromRect(
                  rect: deckRect,
                  child: _StageReveal(
                    delay: Duration.zero,
                    child: MusicImmersiveCoverDeck(
                      palette: widget.palette,
                      tracks: deckTracks,
                      selectedIndex: _deckIndex,
                      currentTrack: track,
                      expanded: _deckExpanded,
                      scale: scale,
                      layout: layout,
                      isPlaying: isPlaying,
                      stageSize: deckRect.size,
                      nowPlayingLabel:
                          AppLocalizations.of(context).musicDeckNowPlaying,
                      onSelected:
                          (index) => _selectDeckTrack(deckTracks, index),
                      onStep: (delta) => _stepDeck(deckTracks, delta),
                    ),
                  ),
                ),
              // 两侧布局卡组列底部的音频参数胶囊（样例 `Spec Data & DAC Output Indicator`）。
              // 不固定高度：两行文字行盒在物理像素上取整，固定 46*scale 会
              // 在小数缩放下溢出约 1px，改为按内容自适应。
              if (!isCenter && visual.deckEnabled)
                Positioned(
                  left: deckRect.left,
                  width: deckRect.width,
                  top: deckRect.bottom + musicDeckSpecGap(layout) * scale,
                  child: Builder(
                    builder: (context) {
                      final servedQuality = state?.playbackPlan?.quality;
                      return _DigitalDeckSpecCapsule(
                        track: track,
                        scale: scale,
                        servedQualityLabel:
                            servedQuality == null ||
                                    servedQuality.trim().isEmpty
                                ? null
                                : musicQualityLabel(
                                  AppLocalizations.of(context),
                                  servedQuality,
                                ),
                      );
                    },
                  ),
                ),
              // 歌词列顶部元信息行：三个布局统一渲染（居右为样例原生，
              // 居左/居中补齐同一控件），含同步歌词标签、格式徽标与 ±0.2s
              // 偏移微调；左侧布局的样例原本没有，但统一后交互一致。
              if (visual.lyrics.enabled && lyricHeaderRect != null)
                Positioned(
                  left: lyricHeaderRect.left,
                  width: lyricHeaderRect.width,
                  top: lyricHeaderRect.top,
                  height: lyricHeaderRect.height,
                  child: _DigitalLyricColumnHeader(
                    track: track,
                    scale: scale,
                    trackOffsetMs: trackOffsetMs,
                    onAdjustLyricOffset: _adjustTrackLyricOffset,
                    onResetLyricOffset:
                        trackOffsetMs == null || trackOffsetMs == 0
                            ? null
                            : () => _resetTrackLyricOffset(),
                  ),
                ),
              if (_visualEditorOpen)
                Positioned(
                  key: const ValueKey('music-visual-editor-positioned'),
                  top: headerTop,
                  right: sideFrame.pagePadding,
                  bottom: controlsBottom,
                  width:
                      math
                          .min(
                            width - sideFrame.pagePadding * 2,
                            (width * 0.34).clamp(360.0, 520.0),
                          )
                          .toDouble(),
                  child: MusicVisualEditorPanel(
                    key: const ValueKey('music-visual-editor'),
                    palette: widget.palette,
                    source: savedVisual,
                    lyricScrollMode: lyricScrollMode,
                    onChanged: _previewVisualizerSettings,
                    onSave: _saveVisualizerSettings,
                    onClose: _closeVisualizerEditor,
                    // 桌面沉浸页只显示桌面组：移动端专属参数在本页无效。
                    sections: const <MusicVisualEditorSection>{
                      MusicVisualEditorSection.desktop,
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openVisualEditor() {
    setState(() {
      _previewVisual = null;
      _visualEditorOpen = true;
    });
  }

  /// 调整当前曲目的歌词延迟（行菜单触发）：写入曲目级设备本地覆盖。
  void _adjustTrackLyricOffset(int deltaMs) {
    if (!mounted) {
      return;
    }
    final track =
        ref.read(musicCenterControllerProvider).asData?.value.currentTrack;
    if (track == null) {
      return;
    }
    unawaited(
      ref
          .read(musicTrackLyricOffsetProvider(track.id).notifier)
          .adjust(deltaMs),
    );
  }

  /// 清零当前曲目的歌词延迟（设备本地覆盖）。
  void _resetTrackLyricOffset() {
    if (!mounted) {
      return;
    }
    final track =
        ref.read(musicCenterControllerProvider).asData?.value.currentTrack;
    if (track == null) {
      return;
    }
    unawaited(
      ref.read(musicTrackLyricOffsetProvider(track.id).notifier).resetToZero(),
    );
  }

  void _previewVisualizerSettings(PortalMusicVisualizerSettings visual) {
    setState(() => _previewVisual = visual);
  }

  Future<void> _saveVisualizerSettings(
    PortalMusicVisualizerSettings visual,
  ) async {
    await ref
        .read(musicVisualizerPreferencesProvider.notifier)
        .saveVisual(visual);
    if (!mounted) {
      return;
    }
    setState(() {
      _previewVisual = null;
      _visualEditorOpen = false;
    });
  }

  void _closeVisualizerEditor() {
    setState(() {
      _previewVisual = null;
      _visualEditorOpen = false;
    });
  }

  void _schedulePlaybackSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(musicPlaybackSessionProvider.notifier).syncFromCenterState(),
      );
    });
  }

  void _runPlaybackCommand(Future<void> Function() command) {
    unawaited(() async {
      try {
        await command();
        _schedulePlaybackSync();
      } on Exception catch (error) {
        if (kDebugMode) {
          final message = describeUserFacingError(error).message;
          devLog('Music 沉浸播放命令失败: $message');
        }
      }
    }());
  }

  List<MusicTrack> _resolveDeckTracks(
    MusicCenterState? state,
    MusicTrack? track,
  ) {
    final source =
        state?.playbackQueue.isNotEmpty == true
            ? state!.playbackQueue
            : state?.tracks ?? const <MusicTrack>[];
    if (track == null) {
      return List<MusicTrack>.unmodifiable(source);
    }
    final seen = <String>{};
    final tracks = <MusicTrack>[];
    for (final item in source) {
      if (seen.add(item.id)) {
        tracks.add(item.id == track.id ? track : item);
      }
    }
    if (seen.add(track.id)) {
      tracks.add(track);
    }
    return List<MusicTrack>.unmodifiable(tracks);
  }

  /// 当前曲在卡组里的档位；不在卡组时返回 null（保持调用方现值）。
  int? _resolveDeckIndex(MusicTrack? track, List<MusicTrack> tracks) {
    final trackId = track?.id;
    if (trackId == null) {
      return null;
    }
    final index = tracks.indexWhere((item) => item.id == trackId);
    return index < 0 ? null : index;
  }

  /// 卡组滚轮步进：语义是「下一首/上一首」，必须经播放模式解析目标，
  /// 不能按展示顺序加减索引（随机档会退回顺序，单曲循环档会原地不动）。
  void _stepDeck(List<MusicTrack> tracks, int delta) {
    if (tracks.isEmpty || tracks.length == 1) {
      return;
    }
    _runPlaybackCommand(() async {
      final controller = ref.read(musicCenterControllerProvider.notifier);
      if (delta > 0) {
        await controller.nextTrack();
      } else {
        await controller.previousTrack();
      }
    });
  }

  void _selectDeckTrack(List<MusicTrack> tracks, int index) {
    if (index < 0 || index >= tracks.length) {
      return;
    }
    setState(() => _deckIndex = index);
    _runPlaybackCommand(() async {
      final controller = ref.read(musicCenterControllerProvider.notifier);
      final state = ref.read(musicCenterControllerProvider).asData?.value;
      final queue = state?.playbackItems ?? const [];
      final trackId = tracks[index].id;
      final queueIndex = queue.indexWhere(
        (candidate) => candidate.track.id == trackId,
      );
      // 队列非空时按队列内跳播，保持"播放自"上下文不被曲库覆盖。
      if (queue.isNotEmpty && queueIndex >= 0) {
        await controller.playQueueIndex(queueIndex);
      } else {
        await controller.playTrack(tracks[index]);
      }
    });
  }
}

/// 居右布局歌词列顶部的元信息行（样例 `Synchronized Master Lyrics` 标签 +
/// 格式徽标 + 歌词偏移 ±0.2s 微调 + 底部 1px 分隔线）。
class _DigitalLyricColumnHeader extends StatelessWidget {
  const _DigitalLyricColumnHeader({
    required this.track,
    required this.scale,
    required this.onAdjustLyricOffset,
    this.trackOffsetMs,
    this.onResetLyricOffset,
  });

  final MusicTrack? track;
  final double scale;

  /// 偏移微调回调：与歌词行长按菜单共用曲目级设备本地覆盖。
  final void Function(int deltaMs)? onAdjustLyricOffset;

  /// 当前曲目级偏移（毫秒）：非零时在按钮旁展示数值并提供重置，
  /// 让 ±0.2s 微调的效果可感知、可撤销。
  final int? trackOffsetMs;
  final VoidCallback? onResetLyricOffset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = track?.format.trim().toUpperCase() ?? '';
    final offsetSeconds = (trackOffsetMs ?? 0) / 1000;
    final offsetLabel =
        offsetSeconds == 0
            ? null
            : offsetSeconds > 0
            ? l10n.musicLyricOffsetDelayed(offsetSeconds.toStringAsFixed(1))
            : l10n.musicLyricOffsetAdvanced(
              (-offsetSeconds).toStringAsFixed(1),
            );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(
                Icons.translate_rounded,
                size: 14 * scale,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              SizedBox(width: 6 * scale),
              Text(
                l10n.musicLyricSyncBadge.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kMusicLyricTranslationColor,
                  fontSize: kMusicDeckSpecChipFontSize * scale,
                  height: 14 / 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.06 * 11 * scale,
                ),
              ),
              if (format.isNotEmpty) ...[
                SizedBox(width: 10 * scale),
                _DigitalLyricFormatChip(label: format, scale: scale),
              ],
              const Spacer(),
              if (offsetLabel != null) ...[
                Text(
                  offsetLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: kMusicFooterTimeFontSize * scale,
                    height: 14 / 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                SizedBox(width: 6 * scale),
                _DigitalLyricOffsetButton(
                  icon: Icons.restart_alt_rounded,
                  tooltip: l10n.musicLyricOffsetReset,
                  scale: scale,
                  onTap: onResetLyricOffset ?? () {},
                ),
                SizedBox(width: 8 * scale),
              ],
              _DigitalLyricOffsetButton(
                label: '-0.2s',
                tooltip: l10n.musicLyricOffsetEarlier,
                scale: scale,
                onTap: () => onAdjustLyricOffset?.call(-200),
              ),
              SizedBox(width: 8 * scale),
              _DigitalLyricOffsetButton(
                label: '+0.2s',
                tooltip: l10n.musicLyricOffsetLater,
                scale: scale,
                onTap: () => onAdjustLyricOffset?.call(200),
              ),
            ],
          ),
        ),
        // 样例 `pb-3` 后的 1px 底边分隔线（`border-b border-white/10`）。
        Container(
          height: 1 * scale,
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ],
    );
  }
}

/// 歌词列的格式徽标：样例 `bg-surface-container-high/60 border-white/15`。
class _DigitalLyricFormatChip extends StatelessWidget {
  const _DigitalLyricFormatChip({required this.label, required this.scale});

  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMusicSampleSurfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4 * scale),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: kMusicDeckCardBorderWidth * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * scale,
          vertical: 2 * scale,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: kMusicDeckSpecChipFontSize * scale,
            height: 14 / 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.04 * 10 * scale,
          ),
        ),
      ),
    );
  }
}

/// 歌词偏移微调按钮：样例 `timer -0.2s / +0.2s` 小胶囊；也可纯图标（重置）。
class _DigitalLyricOffsetButton extends StatelessWidget {
  const _DigitalLyricOffsetButton({
    this.label,
    this.icon,
    required this.tooltip,
    required this.scale,
    required this.onTap,
  }) : assert(label != null || icon != null, 'label 与 icon 至少提供一个');

  final String? label;
  final IconData? icon;
  final String tooltip;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6 * scale),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 5 * scale : 9 * scale,
            vertical: 4 * scale,
          ),
          decoration: BoxDecoration(
            color: kMusicDeckCardSurfaceColor.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6 * scale),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: kMusicDeckCardBorderWidth * scale,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 12 * scale,
                  color: kMusicLyricTranslationColor,
                ),
                if (label != null) SizedBox(width: 4 * scale),
              ],
              if (label != null)
                Text(
                  label!,
                  style: TextStyle(
                    color: kMusicLyricTranslationColor,
                    fontSize: kMusicFooterTimeFontSize * scale,
                    height: 14 / 11,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
