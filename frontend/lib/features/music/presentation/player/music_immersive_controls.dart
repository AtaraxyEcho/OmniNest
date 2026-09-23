part of 'music_immersive_player.dart';

/// 底部 Dock 玻璃配色：按宿主深浅色主题解析，使半透明磨砂胶囊在两种主题下
/// 都能读出曲目文字与图标状态，不再固定使用近不透明暗底。
@immutable
class _DockGlassChrome {
  const _DockGlassChrome({
    required this.fill,
    required this.border,
    required this.topHighlight,
    required this.shadow,
    required this.blurSigma,
    required this.title,
    required this.subtitle,
    required this.iconIdle,
    required this.iconStrong,
    required this.artworkFill,
    required this.playBackground,
    required this.playAccent,
    required this.playForeground,
    required this.progressActive,
    required this.progressInactive,
    required this.progressThumb,
    required this.volumePanelBackground,
    required this.volumePanelText,
  });

  factory _DockGlassChrome.resolve(BuildContext context) {
    final colors = context.musicColors;
    final scheme = Theme.of(context).colorScheme;
    final blur = switch (Theme.of(context).brightness) {
      Brightness.light => 26.0,
      Brightness.dark => 30.0,
    };
    if (Theme.of(context).brightness == Brightness.light) {
      return _DockGlassChrome(
        fill: Color.lerp(
          colors.surfaceContainerHigh,
          Colors.white,
          0.45,
        )!.withValues(alpha: 0.60),
        border: Colors.white.withValues(alpha: 0.62),
        topHighlight: Colors.white.withValues(alpha: 0.85),
        shadow: Colors.black.withValues(alpha: 0.18),
        blurSigma: blur,
        title: colors.onSurface,
        subtitle: colors.onSurfaceVariant,
        iconIdle: colors.onSurfaceVariant,
        iconStrong: colors.primary,
        artworkFill: colors.surfaceContainerHigh,
        playBackground: scheme.onSurface,
        playAccent: colors.primary,
        playForeground: colors.surface,
        progressActive: colors.primary,
        progressInactive: colors.onSurface.withValues(alpha: 0.12),
        progressThumb: colors.primary,
        volumePanelBackground: Color.lerp(
          colors.surfaceContainerHigh,
          Colors.white,
          0.60,
        )!.withValues(alpha: 0.96),
        volumePanelText: colors.onSurface,
      );
    }
    return _DockGlassChrome(
      fill: kMusicDeckCardSurfaceColor.withValues(alpha: 0.48),
      border: Colors.white.withValues(alpha: 0.16),
      topHighlight: Colors.white.withValues(alpha: 0.20),
      shadow: Colors.black.withValues(alpha: 0.45),
      blurSigma: blur,
      title: Colors.white,
      subtitle: kMusicLyricTranslationColor,
      iconIdle: kMusicLyricTranslationColor.withValues(alpha: 0.9),
      iconStrong: Colors.white,
      artworkFill: kMusicSampleSurfaceContainerHighest.withValues(alpha: 0.8),
      playBackground: Colors.white,
      playAccent: Colors.white,
      playForeground: kMusicDeckCardOverlayColor,
      progressActive: Colors.white,
      progressInactive: Colors.white.withValues(alpha: 0.16),
      progressThumb: Colors.white,
      volumePanelBackground: const Color(0xF00E151B),
      volumePanelText: Colors.white,
    );
  }

  final Color fill;
  final Color border;
  final Color topHighlight;
  final Color shadow;
  final double blurSigma;
  final Color title;
  final Color subtitle;

  /// 常态图标色与悬停/激活图标色：模式状态只由着色与图标表达，不铺底色。
  final Color iconIdle;
  final Color iconStrong;
  final Color artworkFill;
  final Color playBackground;
  final Color playAccent;
  final Color playForeground;
  final Color progressActive;
  final Color progressInactive;
  final Color progressThumb;
  final Color volumePanelBackground;
  final Color volumePanelText;
}

/// 底部浮动的播放条：透明玻璃胶囊 Dock，配色随宿主深浅色主题解析。
class _DigitalImmersiveGlassPlayerControls extends ConsumerWidget {
  const _DigitalImmersiveGlassPlayerControls({
    required this.player,
    required this.track,
    required this.isPlaying,
    required this.settings,
    required this.scale,
    required this.width,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.onSeek,
  });

  /// 胶囊纵向内边距 `py-3`，与中段两行（传输 40 + 间距 6 + 进度 16）合成的总高
  static const double paddingX = 24;
  static const double paddingY = 12;
  static const double sectionGap = 24;
  static const double sideSectionMinWidth = 210;
  static const double centerMaxWidth = 512;
  static const double rowGap = 6;
  static const double transportGap = 20;
  static const double transportRowHeight = 40;
  static const double progressRowHeight = 16;
  static const double thumbSize = 44;

  /// 低于该宽度时收起播放模式与左段曲目信息。
  static const double compactBreakpoint = 660;

  /// 胶囊可用宽度，由舞台按 `max-w-5xl / max-w-6xl` 计算后传入。
  final double width;

  final MusicAudioPlayback player;
  final MusicTrack? track;
  final bool isPlaying;
  final PortalGlassPlayerSettings settings;
  final double scale;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;

  /// 受控跳转（进度条与 ±10 秒）：必须经播放会话，直接 seek 会被切歌加载
  /// 完成时的归零覆盖。
  final Future<void> Function(Duration position) onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final playMode = center?.playMode ?? MusicPlayMode.sequential;
    final chrome = _DockGlassChrome.resolve(context);
    // 收藏入口只在当前播放项为本地曲目时出现：收藏命令仅覆盖本地曲库，
    // 与曲库列表和移动端播放页的门控一致。
    final currentItem = center?.currentItem;
    final canFavorite =
        track != null &&
        currentItem != null &&
        currentItem.track.id == track!.id &&
        currentItem.ref is LocalMusicRef;
    final pill = BorderRadius.circular(999);
    return DecoratedBox(
      decoration: BoxDecoration(
        // 半透明填充叠 backdrop 模糊：胶囊透出壁纸，不再是接近不透明的暗块。
        color: chrome.fill,
        borderRadius: pill,
        boxShadow: <BoxShadow>[
          // 样例 `.specular-border` 的投影：`0 20px 50px -10px`，按主题取强度。
          BoxShadow(
            color: chrome.shadow,
            blurRadius: 50 * scale,
            spreadRadius: -10 * scale,
            offset: Offset(0, 20 * scale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: pill,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: chrome.blurSigma,
            sigmaY: chrome.blurSigma,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 样例 `.specular-border` 的均匀 1px 描边必须画在模糊之后：
              // 挂在 BackdropFilter 之下时描边会被一起采进模糊背景，1px 白线
              // 被 sigma 30 抹平，暗背景下只剩顶部内高光可见。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: pill,
                      border: Border.all(
                        color: chrome.border,
                        width: 1 * scale,
                      ),
                    ),
                  ),
                ),
              ),
              // 样例 `.specular-border` 的顶部 1px 内高光。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1 * scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: chrome.topHighlight),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: paddingX * scale,
                  vertical: paddingY * scale,
                ),
                // 紧凑判定由舞台按可用宽度算好传入：这里不放 LayoutBuilder，
                // 否则悬停回调触发的重排会在 MouseTracker 更新期间再入布局。
                child: Builder(
                  builder: (context) {
                    final compact = width < (compactBreakpoint * scale);
                    return Row(
                      children: [
                        if (!compact)
                          _buildTrackSection(
                            l10n,
                            ref,
                            chrome,
                            canFavorite: canFavorite,
                          ),
                        SizedBox(width: sectionGap * scale),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: centerMaxWidth * scale,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTransportRow(
                                  ref,
                                  l10n,
                                  chrome,
                                  playMode: playMode,
                                  compact: compact,
                                ),
                                SizedBox(height: rowGap * scale),
                                if (settings.progressEnabled)
                                  _GlassMusicProgress(
                                    chrome: chrome,
                                    player: player,
                                    onSeek: onSeek,
                                    scale: scale,
                                    enabled: track != null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: sectionGap * scale),
                        _buildActionSection(context, ref, l10n, chrome),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左段：缩略图 + 曲名 + 艺术家 + 收藏（样例 `min-w-[210px]`）。
  ///
  /// 定宽而非 minWidth：这是主 Row 的非 flex 子级，minWidth 会给它无上界的宽度，
  /// 内部再放 Expanded 就会报「非零 flex 但宽度无界」。
  Widget _buildTrackSection(
    AppLocalizations l10n,
    WidgetRef ref,
    _DockGlassChrome chrome, {
    required bool canFavorite,
  }) {
    final size = thumbSize * scale;
    final track = this.track;
    return SizedBox(
      width: sideSectionMinWidth * scale,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8 * scale),
            child: _MusicImmersiveArtwork(
              imageUrl: track?.coverUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 180,
              cacheHeight: 180,
              fallback: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                color: chrome.artworkFill,
                child: Icon(
                  Icons.music_note_rounded,
                  size: size * 0.42,
                  color: chrome.iconIdle,
                ),
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? l10n.musicNotPlaying,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: chrome.title,
                    fontSize: kMusicFooterTitleFontSize * scale,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  track == null ? l10n.portalDockMusic : track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: chrome.subtitle,
                    fontSize: kMusicFooterArtistFontSize * scale,
                    height: 18 / 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // 收藏切换（样例三布局的 Dock 都带心形入口）：本地曲目可用。
          if (canFavorite && track != null) ...[
            SizedBox(width: 6 * scale),
            _DockFavoriteButton(
              scale: scale,
              favorited: track.favorite,
              chrome: chrome,
              tooltip:
                  track.favorite ? l10n.musicUnfavorite : l10n.musicFavorite,
              onTap: () => _toggleFavorite(ref, track),
            ),
          ],
        ],
      ),
    );
  }

  /// 中段第一行：播放模式 / 后退 10 秒 / 上一首 / 播放 / 下一首 / 前进 10 秒
  /// （样例居中与居右布局的传输行序，`gap-5`）。
  Widget _buildTransportRow(
    WidgetRef ref,
    AppLocalizations l10n,
    _DockGlassChrome chrome, {
    required MusicPlayMode playMode,
    required bool compact,
  }) {
    return SizedBox(
      // 中段两行总高 62（40 + 6 + 16）恰好等于胶囊内高，避免列溢出。
      height: transportRowHeight * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!compact)
            MusicPlayModeButton(
              playMode: playMode,
              iconSize: 16 * scale,
              padding: 4 * scale,
              idleColor: chrome.iconIdle,
              activeColor: chrome.iconStrong,
              onTap:
                  () =>
                      ref
                          .read(musicCenterControllerProvider.notifier)
                          .cyclePlayMode(),
            ),
          if (!compact) ...[
            SizedBox(width: transportGap * scale),
            // 后退/前进 10 秒：样例居中与居右布局的 `replay_10 / forward_10`。
            _DockIconButton(
              scale: scale,
              chrome: chrome,
              tooltip: l10n.musicSeekBack10,
              icon: Icons.replay_10_rounded,
              iconSize: 19,
              onTap: () => _seekDockBy(player, onSeek, -10),
            ),
          ],
          SizedBox(width: transportGap * scale),
          _DockIconButton(
            scale: scale,
            chrome: chrome,
            tooltip: l10n.musicDeckPrevious,
            icon: Icons.skip_previous_rounded,
            iconSize: 18,
            onTap: onPrevious,
          ),
          SizedBox(width: transportGap * scale),
          // 样例的大圆播放键：`w-10 h-10 rounded-full bg-primary text-background`。
          // 按钮是固定 40px 的实物尺寸而行高按缩放取值，用 FittedBox 收缩，
          // 避免小数缩放下固定尺寸撑破传输行。
          SizedBox.square(
            dimension: transportRowHeight * scale,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: MusicPlaybackButton(
                tooltip: isPlaying ? l10n.musicPause : l10n.musicPlay,
                isPlaying: isPlaying,
                onPressed: onTogglePlayback,
                buttonSize: MusicPlaybackButtonSize.regular,
                backgroundColor: chrome.playBackground,
                accentColor: chrome.playAccent,
                foregroundColor: chrome.playForeground,
              ),
            ),
          ),
          SizedBox(width: transportGap * scale),
          _DockIconButton(
            scale: scale,
            chrome: chrome,
            tooltip: l10n.musicDeckNext,
            icon: Icons.skip_next_rounded,
            iconSize: 18,
            onTap: onNext,
          ),
          if (!compact) ...[
            SizedBox(width: transportGap * scale),
            _DockIconButton(
              scale: scale,
              chrome: chrome,
              tooltip: l10n.musicSeekForward10,
              icon: Icons.forward_10_rounded,
              iconSize: 19,
              onTap: () => _seekDockBy(player, onSeek, 10),
            ),
          ],
        ],
      ),
    );
  }

  /// 右段：音量 + 播放设置 + 播放队列（样例 `min-w-[210px] justify-end`）。
  ///
  /// 同左段：必须定宽，右段的音量按钮内部含 Expanded。
  Widget _buildActionSection(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    _DockGlassChrome chrome,
  ) {
    return SizedBox(
      width: sideSectionMinWidth * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (settings.volumeEnabled)
            MusicVolumeButton(
              player: player,
              tooltip: l10n.portalMusicVisualizerVolume,
              style: MusicVolumeButtonStyle.glass,
              iconColor: chrome.subtitle,
              mutedIconColor: chrome.iconIdle.withValues(alpha: 0.48),
              activeColor: chrome.iconStrong,
              panelTextColor: chrome.volumePanelText,
              panelBackground: chrome.volumePanelBackground,
              iconSize: 16 * scale,
            ),
          SizedBox(width: 16 * scale),
          // 播放设置：图标改为齿轮，避免与样例用于「氛围设置」的 tune 语义混淆。
          _DockIconButton(
            scale: scale,
            chrome: chrome,
            tooltip: l10n.musicPlaybackSettings,
            icon: Icons.settings_rounded,
            iconSize: 16,
            onTap: () => showMusicPlaybackSettingsDialog(context, ref),
          ),
          SizedBox(width: 16 * scale),
          _DockIconButton(
            scale: scale,
            chrome: chrome,
            tooltip: l10n.musicQueueTitle,
            icon: Icons.queue_music_rounded,
            iconSize: 16,
            onTap: () => showMusicDeckQueue(context),
          ),
        ],
      ),
    );
  }
}

/// Dock 快进/快退：按当前进度相对跳转并夹在时长范围内。
void _seekDockBy(
  MusicAudioPlayback player,
  Future<void> Function(Duration position) seek,
  int seconds,
) {
  final totalMs = player.state.duration.inMilliseconds;
  if (totalMs <= 0) {
    return;
  }
  final targetMs =
      (player.state.position.inMilliseconds + seconds * 1000)
          .clamp(0, totalMs)
          .toInt();
  unawaited(seek(Duration(milliseconds: targetMs)));
}

/// Dock 收藏切换：命令内部已容错，这里只兜住异常避免未处理异步错误。
void _toggleFavorite(WidgetRef ref, MusicTrack track) {
  unawaited(() async {
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .toggleFavorite(track);
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('Music 沉浸页收藏切换失败: ${describeUserFacingError(error).message}');
      }
    }
  }());
}

/// Dock 图标按钮：悬停与按下只改图标着色和缩放，不留水波、高亮与焦点底色。
class _DockIconButton extends StatefulWidget {
  const _DockIconButton({
    required this.scale,
    required this.chrome,
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.onTap,
  });

  final double scale;
  final _DockGlassChrome chrome;
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;

  @override
  State<_DockIconButton> createState() => _DockIconButtonState();
}

class _DockIconButtonState extends State<_DockIconButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTap,
        onHighlightChanged: (highlighted) {
          if (highlighted != _pressed) {
            setState(() => _pressed = highlighted);
          }
        },
        onHover: (hovered) {
          if (hovered != _hovered) {
            setState(() => _hovered = hovered);
          }
        },
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: AnimatedScale(
          // 按下缩放反馈：与样例播放键的 active:scale-95 观感一致。
          scale: _pressed ? 0.88 : 1,
          duration: MusicImmersiveMotion.duration(
            context,
            const Duration(milliseconds: 120),
          ),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: EdgeInsets.all(4 * widget.scale),
            child: Icon(
              widget.icon,
              color: _hovered || _pressed ? chrome.iconStrong : chrome.iconIdle,
              size: widget.iconSize * widget.scale,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dock 收藏按钮：未收藏为描边灰心，收藏后为实心强调色。
class _DockFavoriteButton extends StatelessWidget {
  const _DockFavoriteButton({
    required this.scale,
    required this.chrome,
    required this.favorited,
    required this.tooltip,
    required this.onTap,
  });

  final double scale;
  final _DockGlassChrome chrome;
  final bool favorited;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(5 * scale),
          child: AnimatedSwitcher(
            duration: MusicImmersiveMotion.duration(
              context,
              const Duration(milliseconds: 180),
            ),
            child: Icon(
              favorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              key: ValueKey<bool>(favorited),
              color: favorited ? chrome.iconStrong : chrome.iconIdle,
              size: 15 * scale,
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部/浮层用的玻璃图标按钮（编辑视觉入口等）。
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final MusicImmersivePalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            child: Icon(icon, color: palette.text, size: 21),
          ),
        ),
      ),
    );
  }
}

/// 进度行：`w-9` 等宽时间 + `h-1.5` 轨 + 总时长（样例 `gap-3`）。
class _GlassMusicProgress extends StatelessWidget {
  const _GlassMusicProgress({
    required this.chrome,
    required this.player,
    required this.onSeek,
    required this.scale,
    required this.enabled,
  });

  final _DockGlassChrome chrome;
  final MusicAudioPlayback player;
  final Future<void> Function(Duration position) onSeek;
  final double scale;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final totalMs = duration.inMilliseconds;
            final value =
                totalMs <= 0
                    ? 0.0
                    : (position.inMilliseconds / totalMs)
                        .clamp(0.0, 1.0)
                        .toDouble();
            return SizedBox(
              height:
                  _DigitalImmersiveGlassPlayerControls.progressRowHeight *
                  scale,
              child: Row(
                children: [
                  SizedBox(
                    width: 36 * scale,
                    child: Text(
                      _formatDuration(position),
                      textAlign: TextAlign.right,
                      style: _timeStyle(0.9),
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: MusicPlaybackProgressBar(
                      value: value,
                      semanticLabel: l10n.portalMusicVisualizerSeek,
                      activeColor: chrome.progressActive,
                      inactiveColor: chrome.progressInactive,
                      thumbColor: chrome.progressThumb,
                      onChanged:
                          enabled && totalMs > 0
                              ? (next) => unawaited(
                                onSeek(
                                  Duration(
                                    milliseconds: (totalMs * next).round(),
                                  ),
                                ),
                              )
                              : null,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  SizedBox(
                    width: 36 * scale,
                    child: Text(
                      _formatDuration(duration),
                      style: _timeStyle(0.7),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  TextStyle _timeStyle(double alpha) {
    return TextStyle(
      color: chrome.subtitle.withValues(alpha: alpha),
      fontSize: kMusicFooterTimeFontSize * scale,
      height: 1.0,
      fontWeight: FontWeight.w400,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
