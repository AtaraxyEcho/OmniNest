part of 'desktop_movies_page.dart';

class _WideGrid extends StatelessWidget {
  const _WideGrid({required this.items});

  final List<MovieContinueWatching> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 22,
      runSpacing: 22,
      children: [
        for (var i = 0; i < items.length; i++)
          SizedBox(
            width: 340,
            child: DesktopStagger(index: i, child: _WideCard(item: items[i])),
          ),
      ],
    );
  }
}

/// History 沿用影片浏览的海报网格，观看进度压在海报底缘。
class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.entries, required this.onClear});

  final List<MovieWatchHistory> entries;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopSection(
      title: l10n.videoSectionHistory,
      actionLabel: entries.isEmpty ? null : l10n.videoClearHistory,
      onAction: entries.isEmpty ? null : onClear,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0) {
            return const SizedBox.shrink();
          }
          final columns = _posterGridColumns(context, constraints.maxWidth);
          const gap = 22.0;
          final width = math.max(
            0.0,
            (constraints.maxWidth - gap * (columns - 1)) / columns,
          );
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var index = 0; index < entries.length; index++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: index,
                    child: _HistoryPoster(entry: entries[index]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryPoster extends StatefulWidget {
  const _HistoryPoster({required this.entry});

  final MovieWatchHistory entry;

  @override
  State<_HistoryPoster> createState() => _HistoryPosterState();
}

class _HistoryPosterState extends State<_HistoryPoster> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final progress = _historyProgress(entry);
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DesktopTilt(
        onTap:
            entry.videoItemId.isEmpty
                ? null
                : () => desktopPush(
                  context,
                  DesktopRoutes.movieDetail(entry.videoItemId),
                ),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DesktopCover(
                  url: entry.posterUrl,
                  kind: DesktopCoverKind.network,
                  fallbackIcon: DesktopIcons.film,
                  cacheKey: 'desktop-history-${entry.id}',
                ),
                const _PosterShade(),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.rowTitle(Colors.white),
                      ),
                      if (entry.playedAt != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          l10n.videoLastPlayed(_shortDateTime(entry.playedAt!)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.caption(
                            Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_hovered && entry.videoItemId.isNotEmpty)
                  Center(
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: DesktopMotion.fast,
                      alwaysIncludeSemantics: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: skin.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            DesktopIcons.play,
                            size: 18,
                            color: skin.accentInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    color: skin.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _historyProgress(MovieWatchHistory entry) {
  if (entry.durationSeconds <= 0) {
    return 0;
  }
  return (entry.positionSeconds / entry.durationSeconds).clamp(0.0, 1.0);
}

String _shortDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
