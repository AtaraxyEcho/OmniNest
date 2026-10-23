part of 'music_mobile_now_playing.dart';

/// 封面页固定开销：控制行（64 主播放盘 + 上间距 16 + 下间距 14）与底部工具行
/// （40 + 安全内边距下限 14）。样例把控制行用 `margin-top: auto` 沉到内容流
/// 末端，因此这两段不参与封面缩放，只从可用高度里预先扣掉。
const double _kCoverPageChromeHeight = 150;

/// 封面页文本段高度：眉标 + 衬线曲名 + 艺人行 + 进度轨与双端时间
/// （样例 `track-meta` 的 25/12 外边距与 `scrubber` 的行间隙）。
const double _kCoverPageMetaHeight = 138;

/// 封面边长上下限（样例 `min(74vw, 350px)`，下限保证极矮视口仍是一张可认封面，
/// 超出可用高度时由内容区整体滚动承接）。
const double _kCoverPageMaxSide = 340;
const double _kCoverPageMinSide = 132;

/// 播放页第一页（样例 `cover-page`）：封面、曲名、进度自上而下流动，
/// 五控制行与底部工具行沉在页尾。歌词预览块与封面投影已按原型删除。
class _MobileCoverPage extends StatelessWidget {
  const _MobileCoverPage({
    required this.item,
    required this.track,
    required this.lyrics,
    required this.player,
    required this.enabled,
    required this.isPlaying,
    required this.playMode,
    required this.onShowLyrics,
    required this.onToggleFavorite,
    required this.onRequestPlayMode,
    required this.onSeek,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayback,
    required this.onOpenSettings,
    required this.onOpenQueue,
  });

  final MusicPlayableItem? item;
  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final MusicAudioPlayback player;
  final bool enabled;
  final bool isPlaying;
  final MusicPlayMode playMode;
  final VoidCallback onShowLyrics;
  final VoidCallback? onToggleFavorite;
  final void Function(MusicPlayMode mode) onRequestPlayMode;

  /// 进度跳转经播放会话，避免与切歌加载竞争。
  final Future<void> Function(Duration position) onSeek;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayback;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 封面按整页可用高度取方：先扣除沉底的两段控件与文本段，
        // 剩余空间再与视口宽度取小，短横屏时内容整体可滚而不挤压控件。
        final available =
            constraints.maxHeight -
            _kCoverPageChromeHeight -
            _kCoverPageMetaHeight;
        final side = math.min(
          math.max(1, constraints.maxWidth - 32),
          math.max(1, available),
        );
        final coverSize =
            side.clamp(_kCoverPageMinSide, _kCoverPageMaxSide).toDouble();
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _MobileArtwork(
                      track: track,
                      coverSize: coverSize,
                      onShowLyrics: onShowLyrics,
                    ),
                    _MobileTrackHeader(
                      item: item,
                      track: track,
                      onToggleFavorite: onToggleFavorite,
                    ),
                    _MobileProgress(
                      player: player,
                      enabled: enabled,
                      onSeek: onSeek,
                    ),
                  ],
                ),
              ),
            ),
            _MobileTransportRow(
              enabled: enabled,
              isPlaying: isPlaying,
              playMode: playMode,
              onRequestPlayMode: onRequestPlayMode,
              onPrevious: onPrevious,
              onNext: onNext,
              onTogglePlayback: onTogglePlayback,
            ),
            _MobileUtilityRow(
              onOpenSettings: onOpenSettings,
              onOpenQueue: onOpenQueue,
            ),
          ],
        );
      },
    );
  }
}

/// 播放页第二页（样例 `lyrics-page`）：LIVE LYRICS 眉标 + 曲名艺人 +
/// 整屏歌词（居中、在读行放大读色、上下渐隐）。
class _MobileLyricsPage extends StatelessWidget {
  const _MobileLyricsPage({
    required this.player,
    required this.track,
    required this.lyrics,
    required this.lyricsLoadFailed,
    required this.lyricSettings,
    required this.scrollMode,
    required this.trackOffsetMs,
    required this.onAdjustLyricOffset,
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
  });

  final MusicAudioPlayback player;
  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final bool lyricsLoadFailed;
  final PortalLyricVisualSettings lyricSettings;
  final bool scrollMode;
  final int? trackOffsetMs;
  final void Function(int deltaMs)? onAdjustLyricOffset;
  final VoidCallback onTogglePlayback;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Future<void> Function(Duration position) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final track = this.track;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Column(
        children: [
          Text(
            l10n.musicLiveLyrics.toUpperCase(),
            textAlign: TextAlign.center,
            // ignore: font_size_whitelist
            style: TextStyle(
              color: context.env.inkFaint,
              // ignore: font_size_whitelist
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          if (track != null)
            Text(
              '${track.title} · ${track.artistName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.env.white52,
                // ignore: font_size_whitelist
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: MusicImmersiveLyrics(
              palette: MusicImmersivePalette.digital,
              player: player,
              track: track,
              lyrics: lyrics,
              lyricsLoadFailed: lyricsLoadFailed,
              scale: MediaQuery.sizeOf(context).width < 390 ? 0.86 : 0.94,
              // 移动端整屏歌词居中排布：窄屏长句折行后居中才贴近样例排版。
              textAlign: TextAlign.center,
              blockAnchor: Alignment.center,
              lyricSettings: lyricSettings,
              scrollMode: scrollMode,
              // 样例歌词页是衬线体，与封面页的衬线曲名同一身份。
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              trackOffsetMs: trackOffsetMs,
              onAdjustLyricOffset: onAdjustLyricOffset,
              onTogglePlayback: onTogglePlayback,
              onPrevious: onPrevious,
              onNext: onNext,
              onSeek: onSeek,
            ),
          ),
        ],
      ),
    );
  }
}

/// 用户未改色时的在读行取色：样例当前句是酸绿，纯白视为"未设置"。
///
/// 与歌词渲染层同一判据（默认双色即用户未改色），避免把用户显式配色覆盖掉。
PortalLyricVisualSettings _mobileLyricSettings(
  PortalLyricVisualSettings settings,
  MobileEnvPalette env,
) {
  final fallback = PortalLyricVisualSettings.defaults.currentPaint;
  final current = settings.currentPaint;
  final untouched =
      current.mode == fallback.mode &&
      current.primary == fallback.primary &&
      current.secondary == fallback.secondary;
  if (!untouched) {
    return settings;
  }
  return settings.copyWith(
    currentPaint: LyricPaint.solid(env.accentInk.toARGB32()),
  );
}

/// 封面卡（样例 `player-art`）：圆角方形封面 + LOSSLESS 徽标。
///
/// 原型已删除封面重投影（暗背景下的 `0 25px 65px` 会糊成一条黑带）与
/// 频谱条，只保留徽标；点封面即跳到整屏歌词页，横滑仍可翻页。
class _MobileArtwork extends StatelessWidget {
  const _MobileArtwork({
    required this.track,
    required this.coverSize,
    required this.onShowLyrics,
  });

  final MusicTrack? track;
  final double coverSize;
  final VoidCallback onShowLyrics;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: AppLocalizations.of(context).musicNowPlayingLyrics,
        child: GestureDetector(
          onTap: onShowLyrics,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            // 退场子树排除语义，避免与入场子树同批更新触发桥失败。
            layoutBuilder: excludeExitingSemanticsStack,
            child: SizedBox.square(
              key: ValueKey<String?>('mobile-cover-${track?.id}'),
              dimension: coverSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MusicDeckArtwork(
                    title: track?.title ?? '',
                    imageUrl: track?.coverUrl,
                    borderRadius: 26,
                  ),
                  if (_isLossless(track?.format))
                    const Positioned(
                      top: 13,
                      right: 13,
                      child: _LosslessBadge(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 曲目信息行（样例 `track-meta`）：酸绿眉标 + 衬线曲名 + 艺人 · 专辑 + 收藏。
class _MobileTrackHeader extends StatelessWidget {
  const _MobileTrackHeader({
    required this.item,
    required this.track,
    required this.onToggleFavorite,
  });

  final MusicPlayableItem? item;
  final MusicTrack? track;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 25, 2, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.musicNowPlayingEyebrow.toUpperCase(),
                  style: TextStyle(
                    color: context.env.accentInk,
                    // ignore: font_size_whitelist
                    fontSize: 8,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  track?.title ?? l10n.musicNotPlaying,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.env.ink,
                    fontFamily: AppTypography.serifFamily,
                    fontFamilyFallback: AppTypography.serifFamilyFallback,
                    // ignore: font_size_whitelist
                    fontSize: 35,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track == null
                      ? l10n.musicDeckSelectTrack
                      : '${track!.artistName} · ${track!.albumTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // ignore: font_size_whitelist
                  style: TextStyle(
                    color: context.env.inkMuted,
                    // ignore: font_size_whitelist
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (item?.ref is LocalMusicRef)
            IconButton(
              tooltip:
                  track?.favorite == true
                      ? l10n.musicUnfavorite
                      : l10n.musicFavorite,
              onPressed: onToggleFavorite,
              icon: OmniIcon(
                icon: OmniIcons.heart,
                size: 22,
                color:
                    track?.favorite == true
                        ? context.env.accentInk
                        : context.env.white78,
              ),
            ),
        ],
      ),
    );
  }
}

/// 进度行（样例 `scrubber`）：进度轨 + 双端时间。
class _MobileProgress extends StatelessWidget {
  const _MobileProgress({
    required this.player,
    required this.enabled,
    required this.onSeek,
  });

  final MusicAudioPlayback player;
  final bool enabled;

  /// 进度跳转经播放会话，避免与切歌加载竞争。
  final Future<void> Function(Duration position) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final totalMs = duration.inMilliseconds;
        return MusicThrottledPositionBuilder(
          player: player,
          builder: (context, position) {
            final progress =
                totalMs <= 0
                    ? 0.0
                    : (position.inMilliseconds / totalMs)
                        .clamp(0.0, 1.0)
                        .toDouble();
            return Column(
              children: [
                MusicPlaybackProgressBar(
                  value: progress,
                  semanticLabel: l10n.portalMusicVisualizerSeek,
                  // 样例进度是近白（`--ink`），酸绿只留给强调文本与选中态。
                  activeColor: context.env.ink,
                  inactiveColor: context.env.line15,
                  thumbColor: context.env.ink,
                  onChanged:
                      enabled && totalMs > 0
                          ? (value) => unawaited(
                            onSeek(
                              Duration(milliseconds: (totalMs * value).round()),
                            ),
                          )
                          : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(position),
                        style: _timeStyle(context.env),
                      ),
                      const Spacer(),
                      Text(
                        _formatDuration(duration),
                        style: _timeStyle(context.env),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  TextStyle _timeStyle(MobileEnvPalette env) => TextStyle(
    color: env.inkFaint,
    fontSize: AppTypography.labelSmall,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 五控制行（样例 `player-controls`）：随机 / 上一首 / 播放 / 下一首 / 循环。
///
/// 三态播放模式在控制器里是互斥单值，因此随机与循环各自是"点亮即进入、
/// 再点回顺序档"的开关钮，不再共用桌面 Dock 的轮换单钮。
class _MobileTransportRow extends StatelessWidget {
  const _MobileTransportRow({
    required this.enabled,
    required this.isPlaying,
    required this.playMode,
    required this.onRequestPlayMode,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayback,
  });

  final bool enabled;
  final bool isPlaying;
  final MusicPlayMode playMode;
  final void Function(MusicPlayMode mode) onRequestPlayMode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shuffling = playMode == MusicPlayMode.shuffle;
    final repeating = playMode == MusicPlayMode.repeatOne;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _MobileModeButton(
            tooltip: l10n.musicShuffle,
            vector: OmniIcons.shuffle,
            active: shuffling,
            onPressed:
                enabled
                    ? () => onRequestPlayMode(
                      shuffling
                          ? MusicPlayMode.sequential
                          : MusicPlayMode.shuffle,
                    )
                    : null,
          ),
          IconButton(
            tooltip: l10n.musicDeckPrevious,
            onPressed: enabled ? onPrevious : null,
            style: IconButton.styleFrom(
              foregroundColor: context.env.ink,
              minimumSize: const Size.square(48),
            ),
            icon: const OmniIcon(icon: OmniIcons.previous, size: 30),
          ),
          MusicPlaybackButton(
            isPlaying: isPlaying,
            tooltip: isPlaying ? l10n.musicPause : l10n.musicPlay,
            onPressed: enabled ? onTogglePlayback : null,
            buttonSize: MusicPlaybackButtonSize.primary,
            // 样例主播放钮是近白实盘配深色符号，不带渐变与青绿。
            backgroundColor: context.env.ink,
            accentColor: context.env.ink,
            foregroundColor: context.env.posterPlayFg,
            iconSize: 30,
          ),
          IconButton(
            tooltip: l10n.musicDeckNext,
            onPressed: enabled ? onNext : null,
            style: IconButton.styleFrom(
              foregroundColor: context.env.ink,
              minimumSize: const Size.square(48),
            ),
            icon: const OmniIcon(icon: OmniIcons.next, size: 30),
          ),
          _MobileModeButton(
            tooltip: l10n.musicRepeatOne,
            // 样例只画了一枚 repeat 图元；单循环与顺序循环靠强调色与
            // tooltip 区分，不再另找 Material 变体字形。
            vector: OmniIcons.repeat,
            active: repeating,
            onPressed:
                enabled
                    ? () => onRequestPlayMode(
                      repeating
                          ? MusicPlayMode.sequential
                          : MusicPlayMode.repeatOne,
                    )
                    : null,
          ),
        ],
      ),
    );
  }
}

/// 随机 / 循环开关钮：48 命中、图标 20，未点亮用次级白、点亮用酸绿。
class _MobileModeButton extends StatelessWidget {
  const _MobileModeButton({
    required this.tooltip,
    required this.vector,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final OmniIconsData vector;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active ? true : null,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: active ? context.env.accent : context.env.inkMuted,
          minimumSize: const Size.square(48),
        ),
        icon: OmniIcon(icon: vector, size: 22),
      ),
    );
  }
}

/// 底部工具行（样例 `player-utility`）：左=投放位（当前实现为播放设置），
/// 右=队列。头部不再有队列与歌词钮。
class _MobileUtilityRow extends StatelessWidget {
  const _MobileUtilityRow({
    required this.onOpenSettings,
    required this.onOpenQueue,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 4,
        right: 4,
        bottom: math.max(14, MediaQuery.paddingOf(context).bottom),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: l10n.musicPlaybackSettings,
            onPressed: onOpenSettings,
            icon: const OmniIcon(icon: OmniIcons.settings, size: 19),
            style: IconButton.styleFrom(
              foregroundColor: context.env.white46,
              minimumSize: const Size(44, 40),
            ),
          ),
          IconButton(
            tooltip: l10n.musicQueueTitle,
            onPressed: onOpenQueue,
            icon: const OmniIcon(icon: OmniIcons.queue, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: context.env.white46,
              minimumSize: const Size(44, 40),
            ),
          ),
        ],
      ),
    );
  }
}

/// 头部玻璃圆钮（样例 `.icon-button` 48×48）：返回与 ⋯ 同一档位。
///
/// 图标恒用样例同源矢量：稿子里这两枚都是 `arrow` / `more` 描边图元，
/// 不留 Material 字形。
class _MobileHeaderButton extends StatelessWidget {
  const _MobileHeaderButton({
    required this.tooltip,
    required this.vector,
    required this.onPressed,
  });

  final String tooltip;
  final OmniIconsData vector;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: context.env.ink,
        backgroundColor: context.env.iconButtonGlass,
        side: BorderSide(color: context.env.line10),
        minimumSize: const Size(48, 48),
        maximumSize: const Size(48, 48),
      ),
      icon: OmniIcon(icon: vector, size: 22, color: context.env.ink),
    );
  }
}

/// 无损格式判定（大小写不敏感的常见无损容器）。
bool _isLossless(String? format) {
  if (format == null || format.isEmpty) {
    return false;
  }
  const lossless = {'FLAC', 'ALAC', 'WAV', 'APE', 'WV', 'DSF', 'AIFF'};
  return lossless.contains(format.toUpperCase());
}

/// LOSSLESS 徽标（原型 player-art > b：玻璃底白字 7px）。
class _LosslessBadge extends StatelessWidget {
  const _LosslessBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      // 徽标压在封面图上，见下方 polarity-stable 标注。
      decoration: BoxDecoration(
        color: MusicChromeColors.onArtworkBadgeFill,
        borderRadius: BorderRadius.circular(7),
        // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
        border: Border.all(color: MusicChromeColors.onArtworkHairline),
      ),
      child: const Text(
        'LOSSLESS',
        style: TextStyle(
          // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
          color: Colors.white,
          // ignore: font_size_whitelist
          fontSize: 7,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
