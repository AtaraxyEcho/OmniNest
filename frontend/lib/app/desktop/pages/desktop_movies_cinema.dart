part of 'desktop_movies_page.dart';

class _CinemaSkeleton extends StatelessWidget {
  const _CinemaSkeleton();

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.52).clamp(
      380.0,
      560.0,
    );
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 30),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
      ),
      child: DesktopSkeletonBox(
        height: height,
        radius: DesktopMetrics.radiusHero,
      ),
    );
  }
}

/// 空片库仍保留影院横幅的版位，避免加载完成后标题与内容整体上移。
class _CinemaPlaceholder extends StatelessWidget {
  const _CinemaPlaceholder();

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.52).clamp(
      380.0,
      560.0,
    );
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        border: Border.all(color: skin.line),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.56),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: (MediaQuery.sizeOf(context).width * 0.04).clamp(28.0, 64.0),
            bottom: (MediaQuery.sizeOf(context).height * 0.06).clamp(
              34.0,
              66.0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(DesktopIcons.film, size: 24, color: skin.text3),
                  const SizedBox(height: 16),
                  Text(
                    l10n.videoSeriesFeatured.toUpperCase(),
                    style: DesktopType.eyebrow(skin.text3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.desktopMoviesEmptyLibraryTitle,
                    style: DesktopType.display(skin.text),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.desktopMoviesEmptyLibraryBody,
                    style: DesktopType.body(skin.text2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cinema extends StatefulWidget {
  const _Cinema({required this.items, required this.continueWatching});

  final List<MovieVideoItem> items;
  final List<MovieContinueWatching> continueWatching;

  @override
  State<_Cinema> createState() => _CinemaState();
}

class _CinemaState extends State<_Cinema> {
  int _index = 0;
  bool _paused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(_Cinema oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _index = 0;
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (widget.items.length < 2) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _paused) {
        return;
      }
      setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.52).clamp(
      380.0,
      560.0,
    );
    final active = widget.items[_index];
    return MouseRegion(
      onEnter: (_) => _paused = true,
      onExit: (_) => _paused = false,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 30),
        decoration: BoxDecoration(
          color: DesktopPalette.stageBlack,
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
            for (var i = 0; i < widget.items.length; i++)
              AnimatedOpacity(
                duration: DesktopMotion.of(
                  context,
                  const Duration(milliseconds: 1200),
                ),
                opacity: i == _index ? 1 : 0,
                child:
                    i == _index
                        ? _KenBurns(
                          child: DesktopCover(
                            url:
                                widget.items[i].backdropUrl ??
                                widget.items[i].posterUrl,
                            kind: DesktopCoverKind.network,
                            fallbackIcon: DesktopIcons.film,
                            cacheKey: 'desktop-cinema-${widget.items[i].id}',
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            const _CinemaShade(),
            Positioned(
              left: (MediaQuery.sizeOf(context).width * 0.04).clamp(28.0, 64.0),
              bottom: (MediaQuery.sizeOf(context).height * 0.06).clamp(
                34.0,
                66.0,
              ),
              child: _CinemaCopy(
                key: ValueKey(active.id),
                item: active,
                progress: _progressFor(active),
              ),
            ),
            if (widget.items.length > 1)
              Positioned(
                right: 28,
                bottom: 28,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _index = i),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: AnimatedContainer(
                            duration: DesktopMotion.of(
                              context,
                              const Duration(milliseconds: 500),
                            ),
                            curve: DesktopMotion.ease,
                            width: i == _index ? 40 : 22,
                            height: 3,
                            decoration: BoxDecoration(
                              color:
                                  i == _index
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  MovieContinueWatching? _progressFor(MovieVideoItem item) {
    for (final entry in widget.continueWatching) {
      if (entry.id == item.id) {
        return entry;
      }
    }
    return null;
  }
}

class _CinemaShade extends StatelessWidget {
  const _CinemaShade();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.35),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.70), Colors.transparent],
            stops: const [0.0, 0.45],
          ),
        ),
      ),
    );
  }
}

class _CinemaCopy extends StatelessWidget {
  const _CinemaCopy({required this.item, this.progress, super.key});

  final MovieVideoItem item;
  final MovieContinueWatching? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final meta = _metaLine(item);
    final progressItem = progress;
    final progressLabel =
        progressItem == null
            ? l10n.videoSeriesFeatured.toUpperCase()
            : '${l10n.videoSectionContinueWatching.toUpperCase()} · '
                '${progressItem.progressPercent.round()}% · '
                '${l10n.videoHeroMinutesLeft(((progressItem.durationSeconds - progressItem.positionSeconds).clamp(0, progressItem.durationSeconds) / 60).round())}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DesktopRise(
            duration: DesktopMotion.slow,
            child: Row(
              children: [
                DesktopChip(
                  _resolutionLabel(item),
                  solid: true,
                  tone: DesktopSkin.of(context).accent,
                ),
                const SizedBox(width: 8),
                DesktopChip(
                  item.mediaType == 'EPISODE'
                      ? l10n.videoSectionSeries
                      : l10n.videoHeroMovie,
                  tone: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DesktopRise(
            delay: const Duration(milliseconds: 100),
            duration: DesktopMotion.slow,
            child: Text(
              progressLabel,
              style: DesktopType.eyebrow(Colors.white.withValues(alpha: 0.70)),
            ),
          ),
          const SizedBox(height: 6),
          DesktopRise(
            delay: const Duration(milliseconds: 200),
            duration: DesktopMotion.slow,
            child: Text(
              item.title,
              style: DesktopType.displayXl(
                Colors.white,
                MediaQuery.sizeOf(context).width,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 10),
            DesktopRise(
              delay: const Duration(milliseconds: 300),
              duration: DesktopMotion.slow,
              child: Text(
                meta,
                style: DesktopType.dense(Colors.white.withValues(alpha: 0.80)),
              ),
            ),
          ],
          if ((item.overview ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            DesktopRise(
              delay: const Duration(milliseconds: 400),
              duration: DesktopMotion.slow,
              child: Text(
                item.overview!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.buttonLarge(
                  Colors.white.withValues(alpha: 0.72),
                ).copyWith(height: 1.6),
              ),
            ),
          ],
          const SizedBox(height: 24),
          DesktopRise(
            delay: const Duration(milliseconds: 500),
            duration: DesktopMotion.slow,
            child: Row(
              children: [
                DesktopButton(
                  label:
                      progressItem == null
                          ? l10n.videoPlay
                          : l10n.videoHeroResume,
                  icon: DesktopIcons.play,
                  variant: DesktopButtonVariant.primary,
                  large: true,
                  onPressed:
                      () => desktopPush(
                        context,
                        DesktopRoutes.moviePlay(item.id),
                      ),
                ),
                const SizedBox(width: 10),
                DesktopButton(
                  label: l10n.desktopOpenDetails,
                  icon: DesktopIcons.info,
                  variant: DesktopButtonVariant.glass,
                  large: true,
                  onPressed:
                      () => desktopPush(
                        context,
                        DesktopRoutes.movieDetail(item.id),
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

String _metaLine(MovieVideoItem item) {
  final parts = <String>[];
  if (item.rating != null) {
    parts.add('★ ${item.rating!.toStringAsFixed(1)}');
  }
  if (item.releaseDate != null) {
    parts.add('${item.releaseDate!.year}');
  }
  if (item.runtimeSeconds != null) {
    parts.add(_runtime(item.runtimeSeconds!));
  }
  parts.addAll(item.genres.take(2));
  return parts.join(' · ');
}

DateTime _updatedAt(MovieVideoItem item) {
  return item.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String _runtime(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours <= 0) {
    return '${minutes}m';
  }
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

String _resolutionLabel(MovieVideoItem item) {
  final width = item.resolutionWidth ?? 0;
  if (width >= 3800) {
    return '4K · HDR';
  }
  if (width >= 1900) {
    return '1080p';
  }
  return item.videoCodec?.toUpperCase() ?? 'HD';
}

/// ken-burns：从 1.02 缓推到 1.14，14s 停住（样例 `.cin-slide.on .kb`）。
class _KenBurns extends StatefulWidget {
  const _KenBurns({required this.child});

  final Widget child;

  @override
  State<_KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<_KenBurns>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.kenBurns,
  );

  bool _started = false;

  // MediaQuery 在 initState 里还不可依赖，动画起点放到 didChangeDependencies。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = DesktopMotion.easeOut.transform(_controller.value);
        return Transform.scale(scale: 1.02 + 0.12 * t, child: child);
      },
      child: widget.child,
    );
  }
}
