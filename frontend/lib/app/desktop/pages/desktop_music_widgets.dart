part of 'desktop_music_page.dart';

/// 当前播放主视觉（样例 `.focus`）：模糊封面打底、唱片随播放转、右侧频谱。
class _FocusHero extends StatelessWidget {
  const _FocusHero({required this.state, required this.onTogglePlayback});

  final MusicCenterState? state;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final item = state?.currentItem;
    final track = item?.track;
    final playing = state?.isPlaying ?? false;
    // Hero 使用列表封面地址优先：本地封面会走鉴权缩略图，平台封面会走平台
    // 提供的方形缩放图。这样大图不会在固定唱片容器里被按矩形拉伸。
    final cover = _firstMusicCover(track?.listCoverUrl, track?.coverUrl);
    // 样例 `.focus::before` 的 `color-mix(--hue 30%, rgba(5,8,10,.55))`：
    // 曲目色相混进深色底，切曲时按 1s 补间，不是硬切。
    final tint =
        Color.lerp(
          desktopTrackHue(track?.hue, skin.accent),
          const Color(0xFF05080A),
          0.70,
        )!;

    return Container(
      // 样例 min-height 340；内容实际高 = 封面 280 + 上下 34 = 348。
      height: 348,
      margin: const EdgeInsets.only(bottom: 40),
      // 样例 `.focus` 是 `border-radius:26 + overflow:hidden + border + shadow`。
      // 边框必须走 foregroundDecoration：写在 decoration 里会被紧随其后的
      // 模糊封面层整片盖住，圆角处只剩抗锯齿的半像素，看起来像缺了一圈。
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        boxShadow: skin.shadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        border: Border.all(color: skin.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            RepaintBoundary(
              child: ImageFiltered(
                imageFilter: desktopGlassFilter(
                  blur: 30,
                  saturation: 1.35,
                  brightness: 0.7,
                ),
                child: Transform.scale(
                  // BoxFit.cover 已经铺满舞台，只保留极小安全边避免模糊采样露边。
                  scale: 1.04,
                  child: DesktopCover(
                    url: cover,
                    kind: DesktopCoverKind.music,
                    cacheKey:
                        'desktop-music-focus-background-${track?.id ?? 'empty'}',
                    fallback: const SizedBox.shrink(),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: DesktopMotion.colorFade,
              curve: DesktopMotion.ease,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    tint.withValues(alpha: 0.55),
                    skin.bg.withValues(alpha: 0.42),
                    skin.bg.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          // 样例 `.f-viz`：贴底通栏 90px、白色 56 柱、整体 55% 不透明度，
          // 只作氛围，不接指针。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: DesktopVisualizer(
                  playing: playing,
                  color: Colors.white,
                  bars: 56,
                  seed: 3,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 34, 40, 34),
            child: Row(
              children: [
                if (cover != null)
                  _SpinningCover(
                    url: cover,
                    playing: playing,
                    size: 280,
                    cacheKey: 'desktop-music-focus-${track?.id ?? cover}',
                    onTap: () => desktopPush(context, DesktopRoutes.nowPlaying),
                  ),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _heroEyebrow(l10n, playing, track),
                        style: DesktopType.eyebrow(
                          Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track?.title ?? l10n.desktopNothingPlaying,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.displayXl(
                          Colors.white,
                          MediaQuery.sizeOf(context).width,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track == null
                            ? l10n.desktopNothingPlayingHint
                            : '${track.artistName} · ${track.albumTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.dense(
                          Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          DesktopButton(
                            label:
                                playing ? l10n.desktopPause : l10n.desktopPlay,
                            icon:
                                playing
                                    ? DesktopIcons.pause
                                    : DesktopIcons.play,
                            variant: DesktopButtonVariant.primary,
                            large: true,
                            onPressed: track == null ? null : onTogglePlayback,
                          ),
                          const SizedBox(width: 10),
                          DesktopButton(
                            label: l10n.desktopOpenNowPlaying,
                            icon: DesktopIcons.expand,
                            variant: DesktopButtonVariant.glass,
                            large: true,
                            onPressed:
                                () => desktopPush(
                                  context,
                                  DesktopRoutes.nowPlaying,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面字段在在线曲目里可能以空字符串表示缺失，不能只用 `??` 判断。
/// Hero 与唱片封面必须共享同一回退顺序，避免背景有图而前景落占位图。
String? _firstMusicCover(String? primary, String? fallback) {
  final primaryValue = primary?.trim() ?? '';
  if (primaryValue.isNotEmpty) {
    return primaryValue;
  }
  final fallbackValue = fallback?.trim() ?? '';
  return fallbackValue.isEmpty ? null : fallbackValue;
}

/// 样例 `.f-copy .eyebrow`：Playing from {album} / Paused · {album}。
String _heroEyebrow(AppLocalizations l10n, bool playing, MusicTrack? track) {
  final label =
      playing ? l10n.desktopMusicPlayingFrom : l10n.desktopMusicPaused;
  final album = track?.albumTitle.trim() ?? '';
  if (album.isEmpty) {
    return label.toUpperCase();
  }
  return (playing ? '$label $album' : '$label · $album').toUpperCase();
}

class _SpinningCover extends StatefulWidget {
  const _SpinningCover({
    required this.url,
    required this.playing,
    required this.onTap,
    required this.cacheKey,
    this.size = 280,
  });

  final String url;
  final bool playing;
  final VoidCallback onTap;
  final String cacheKey;
  final double size;

  @override
  State<_SpinningCover> createState() => _SpinningCoverState();
}

class _SpinningCoverState extends State<_SpinningCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: DesktopMotion.vinylSpinFull,
  );

  bool _started = false;

  // MediaQuery 在 initState 阶段还不可依赖。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _sync();
  }

  @override
  void didUpdateWidget(_SpinningCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.playing &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate) {
      if (!_spin.isAnimating) {
        _spin.repeat();
      }
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // 样例 `.f-art`：暂停时是 18 圆角封面，播放时收成圆形唱片并加中心轴孔。
    final radius =
        widget.playing ? widget.size / 2 : DesktopMetrics.radiusLarge;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.soft),
        curve: DesktopMotion.ease,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RotationTransition(
              turns: _spin,
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: DesktopCover(
                    url: widget.url,
                    kind: DesktopCoverKind.music,
                    fallbackIcon: DesktopIcons.music,
                    cacheKey: widget.cacheKey,
                    fit: BoxFit.cover,
                    cacheWidth: (widget.size * 2).round(),
                    cacheHeight: (widget.size * 2).round(),
                    iconSize: 32,
                  ),
                ),
              ),
            ),
            if (widget.playing)
              Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: skin.bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
