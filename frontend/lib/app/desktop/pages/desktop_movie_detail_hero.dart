part of 'desktop_movie_detail_page.dart';

/// 样例 `.fd-hero`：内容区内的圆角剧照卡 + 底部左右分置的文案与海报。
///
/// 与旧的满铺英雄区不同，卡片本身有 26px 圆角、1px 描边与投影；文案块按
/// `.fd-copy` 绝对定位在左下，海报按 `.fd-poster` 绝对定位在右下并默认
/// 倾斜 2°，悬停整卡时抬平上移 4px。
class _Hero extends StatefulWidget {
  const _Hero({
    required this.item,
    required this.history,
    required this.favorite,
    required this.watched,
    required this.watchlisted,
    required this.saving,
    required this.engaging,
    required this.onBack,
    required this.onPlay,
    required this.onFromStart,
    required this.onToggleFavorite,
    required this.onToggleWatched,
    required this.onToggleWatchlist,
  });

  final MovieVideoItem item;
  final MovieWatchHistory? history;
  final bool favorite;
  final bool watched;
  final bool watchlisted;
  final bool saving;
  final bool engaging;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onFromStart;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleWatched;
  final VoidCallback onToggleWatchlist;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final item = widget.item;
    final progress = widget.watched ? 0.0 : _progress(widget.history);
    final resumeLabel =
        progress > 0.02 && progress < 0.98
            ? l10n.videoHeroResume
            : l10n.videoPlay;
    final viewport = MediaQuery.sizeOf(context);
    final heroHeight = (viewport.height * 0.48).clamp(360.0, 500.0);
    final leftInset = (viewport.width * 0.034).clamp(28.0, 56.0);
    final rightInset = (viewport.width * 0.04).clamp(28.0, 72.0);
    final bottomInset = (viewport.height * 0.04).clamp(26.0, 44.0);
    final posterWidth = (viewport.width * 0.15).clamp(150.0, 214.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: skin.line2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 40,
              offset: Offset(0, 18),
              spreadRadius: -12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            height: heroHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 1180;
                final copyMaxWidth =
                    narrow
                        ? 680.0
                        : math
                            .min(680.0, constraints.maxWidth - 300)
                            .clamp(280.0, 680.0)
                            .toDouble();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: DesktopImage(
                        url: item.backdropUrl ?? item.posterUrl,
                      ),
                    ),
                    // `.cin-shade`：横向从 85% 黑退到透明，再叠一层底部暗场。
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              Color(0x00040709),
                              Color(0x59040709),
                              Color(0xD9040709),
                            ],
                            stops: [0, 0.45, 1],
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00040709), Color(0xB3040709)],
                            stops: [0.55, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      top: 22,
                      child: DesktopButton(
                        label: l10n.desktopNavMovies,
                        icon: DesktopIcons.left,
                        variant: DesktopButtonVariant.glass,
                        onPressed: widget.onBack,
                      ),
                    ),
                    Positioned(
                      left: leftInset,
                      bottom: bottomInset,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: copyMaxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (item.resolutionHeight != null)
                                  DesktopChip(
                                    _qualityLabel(item, l10n),
                                    solid: true,
                                  ),
                                DesktopChip(_kindLabel(item, l10n)),
                                if ((item.contentRating ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  DesktopChip(item.contentRating!.trim()),
                                if (widget.watched)
                                  DesktopChip(
                                    l10n.videoWatched,
                                    icon: DesktopIcons.check,
                                  ),
                                if (_notScraped(item))
                                  DesktopChip(
                                    l10n.desktopMoviesNotScraped,
                                    tone: skin.warn,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.displayXl(
                                Colors.white,
                                viewport.width,
                              ),
                            ),
                            if ((item.tagline ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                item.tagline!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.quote(
                                  Colors.white.withValues(alpha: 0.82),
                                ).copyWith(
                                  fontSize: DesktopType.sizePanelTitle,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (item.releaseDate != null)
                                  '${item.releaseDate!.year}',
                                _formatRuntime(item.runtimeSeconds),
                                if (item.genres.isNotEmpty)
                                  item.genres.take(2).join(' · '),
                              ].where((part) => part.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.body(
                                Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                            if (progress > 0.02) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                width: 360,
                                child: DesktopProgress(
                                  fraction: progress,
                                  large: true,
                                  label:
                                      '${(progress * 100).round()}% · ${l10n.videoHeroMinutesLeft(_remainingMinutes(item, progress))}',
                                  color: Colors.white,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                DesktopButton(
                                  label: resumeLabel,
                                  icon: DesktopIcons.play,
                                  variant: DesktopButtonVariant.primary,
                                  large: true,
                                  onPressed: widget.onPlay,
                                ),
                                if (progress > 0.02) ...[
                                  DesktopButton(
                                    label: l10n.desktopMoviesFromStart,
                                    variant: DesktopButtonVariant.glass,
                                    large: true,
                                    onPressed: widget.onFromStart,
                                  ),
                                ],
                                DesktopButton.iconOnly(
                                  icon:
                                      widget.favorite
                                          ? DesktopIcons.heartFilled
                                          : DesktopIcons.heart,
                                  variant: DesktopButtonVariant.glass,
                                  large: true,
                                  foregroundOverride:
                                      widget.favorite
                                          ? skin.liked
                                          : DesktopSkin.of(context).onStage,
                                  tooltip: l10n.videoFavorite,
                                  onPressed:
                                      widget.saving
                                          ? null
                                          : widget.onToggleFavorite,
                                ),
                                DesktopButton.iconOnly(
                                  icon: DesktopIcons.check,
                                  variant: DesktopButtonVariant.glass,
                                  large: true,
                                  active: widget.watched,
                                  tooltip:
                                      widget.watched
                                          ? l10n.desktopMoviesMarkUnwatched
                                          : l10n.desktopMoviesMarkWatched,
                                  onPressed:
                                      widget.engaging
                                          ? null
                                          : widget.onToggleWatched,
                                ),
                                DesktopButton.iconOnly(
                                  icon:
                                      widget.watchlisted
                                          ? DesktopIcons.check
                                          : DesktopIcons.plus,
                                  variant: DesktopButtonVariant.glass,
                                  large: true,
                                  active: widget.watchlisted,
                                  tooltip:
                                      widget.watchlisted
                                          ? l10n.desktopMoviesRemoveWatchlist
                                          : l10n.desktopMoviesAddWatchlist,
                                  onPressed:
                                      widget.engaging
                                          ? null
                                          : widget.onToggleWatchlist,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!narrow)
                      Positioned(
                        right: rightInset,
                        bottom: bottomInset,
                        child: AnimatedContainer(
                          duration: DesktopMotion.imageFade,
                          curve: DesktopMotion.spring,
                          transform:
                              _hovered
                                  ? Matrix4.translationValues(0, -4, 0)
                                  : Matrix4.rotationZ(2 * math.pi / 180),
                          child: SizedBox(
                            width: posterWidth,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xBF000000),
                                      blurRadius: 60,
                                      offset: const Offset(0, 30),
                                      spreadRadius: -16,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      DesktopImage(url: item.posterUrl),
                                      if (item.rating != null)
                                        Align(
                                          alignment: Alignment.topLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: _PosterRating(
                                              rating: item.rating!,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterRating extends StatelessWidget {
  const _PosterRating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return DesktopChip('★ ${rating.toStringAsFixed(1)}');
  }
}

String _qualityLabel(MovieVideoItem item, AppLocalizations l10n) {
  final height = item.resolutionHeight;
  if (height == null || height <= 0) return l10n.desktopMoviesQuality;
  final resolution =
      height >= 2160
          ? '4K'
          : height >= 1080
          ? '1080p'
          : '${height}p';
  final hdr = item.metadata['hdr']?.toString().toUpperCase() ?? '';
  if (hdr.contains('HDR10')) return '$resolution · HDR10';
  if (hdr.contains('HDR')) return '$resolution · HDR';
  return resolution;
}

String _kindLabel(MovieVideoItem item, AppLocalizations l10n) {
  return switch (item.mediaType.toUpperCase()) {
    'MOVIE' => l10n.videoLibraryTypeMovie,
    'ANIME' => l10n.videoLibraryTypeAnime,
    'SERIES' => l10n.videoLibraryTypeTvSeries,
    _ => l10n.videoSectionMovies,
  };
}

int _remainingMinutes(MovieVideoItem item, double progress) {
  final seconds = item.runtimeSeconds ?? 0;
  return ((1 - progress) * seconds / 60).round();
}

double _progress(MovieWatchHistory? history) {
  if (history == null || history.durationSeconds <= 0) {
    return 0;
  }
  return (history.positionSeconds / history.durationSeconds).clamp(0.0, 1.0);
}

String _formatRuntime(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '—';
  }
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

/// 样例 `scraped=false` 的徽章口径：只有已匹配或手动维护过的条目算已完成刮削。
bool _notScraped(MovieVideoItem item) {
  final status = item.metadataStatus.toUpperCase();
  return status.isEmpty || status == 'PENDING' || status == 'FAILED';
}
