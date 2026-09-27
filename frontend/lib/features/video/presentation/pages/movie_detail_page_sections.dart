part of 'movie_detail_page.dart';

/// 影片详情页头部区块：背景、海报信息与播放按钮。
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.backdropUrl,
    required this.favorited,
    required this.canEdit,
    required this.editMode,
    required this.backdropCacheKey,
    required this.saving,
    required this.onBack,
    required this.onToggleEdit,
    this.onToggleFavorite,
  });

  final String? backdropUrl;
  final String? backdropCacheKey;
  final bool favorited;
  final bool canEdit;
  final bool editMode;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onToggleEdit;

  /// null 时隐藏收藏按钮（无 activity:write 的角色）。
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 256,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropUrl != null && backdropUrl!.isNotEmpty)
            MoviePosterImage(
              imageUrl: backdropUrl,
              cacheKey: backdropCacheKey,
              cacheWidth: MoviePosterImage.decodeWidth(
                context,
                MediaQuery.sizeOf(context).width,
                cap: 1600,
              ),
              alignment: Alignment.topCenter,
              fallback: const ColoredBox(color: MovieDetailTheme.surface),
            )
          else
            const ColoredBox(color: MovieDetailTheme.surface),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.5, 1],
                colors: [
                  Colors.black26,
                  Colors.black54,
                  MovieDetailTheme.background,
                ],
              ),
            ),
          ),
          Positioned(
            top: 16 + MediaQuery.paddingOf(context).top,
            left: 20,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('←', style: MovieDetailBackTextStyle()),
                      const SizedBox(width: 8),
                      Text(
                        l10n.videoDetailBack,
                        style: MovieDetailTheme.mono(
                          AppTypography.bodySmall,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16 + MediaQuery.paddingOf(context).top,
            right: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canEdit)
                  Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: MovieRedesignPalette.borderRadius,
                    child: InkWell(
                      onTap: onToggleEdit,
                      borderRadius: MovieRedesignPalette.borderRadius,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: MovieRedesignPalette.borderRadius,
                          border: Border.all(
                            width: 1.2,
                            color:
                                editMode
                                    ? MovieDetailTheme.accent
                                    : Colors.white24,
                          ),
                        ),
                        child: Text(
                          saving
                              ? '…'
                              : editMode
                              ? l10n.videoDetailSave
                              : l10n.videoDetailEdit,
                          style: MovieDetailTheme.mono(
                            12,
                            color:
                                editMode
                                    ? MovieDetailTheme.accent
                                    : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                if (onToggleFavorite != null)
                  Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onToggleFavorite,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          favorited
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 22,
                          color:
                              favorited
                                  ? MovieDetailTheme.accent
                                  : Colors.white,
                        ),
                      ),
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

/// 深链返回箭头的等宽文字样式。
class MovieDetailBackTextStyle extends TextStyle {
  const MovieDetailBackTextStyle()
    : super(
        inherit: true,
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['NotoSansSC'],
        fontSize: AppTypography.bodySmall,
        color: MovieDetailTheme.secondaryText,
      );
}

class _PosterMetaRow extends StatelessWidget {
  const _PosterMetaRow({
    required this.item,
    required this.editMode,
    required this.titleController,
  });

  final MovieVideoItem item;
  final bool editMode;
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    final director =
        item.crewMembers
            .where((member) => member.job?.toLowerCase() == 'director')
            .map((member) => member.name)
            .firstOrNull;
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 112,
          height: 160,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: MovieDetailTheme.border),
          ),
          child: _CoverImage(
            url: item.posterImageUrl,
            cacheKey: 'movie-poster:${item.id}',
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (editMode)
                  TextField(
                    controller: titleController,
                    style: MovieDetailTheme.serif(
                      30,
                      color: MovieDetailTheme.foreground,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: MovieDetailTheme.accent),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: MovieDetailTheme.accent),
                      ),
                    ),
                  )
                else
                  Text(
                    item.title,
                    style: MovieDetailTheme.serif(
                      AppTypography.headlineLarge,
                      height: 1.15,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.rating != null)
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: MovieDetailTheme.mono(
                          12,
                          color: MovieDetailTheme.accent,
                        ),
                      ),
                    Text(
                      item.year,
                      style: MovieDetailTheme.mono(AppTypography.bodySmall),
                    ),
                    if (item.runtimeSeconds != null && item.runtimeSeconds! > 0)
                      Text(
                        item.runtimeText,
                        style: MovieDetailTheme.mono(AppTypography.bodySmall),
                      ),
                    for (final genre in item.genres.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: MovieDetailTheme.border),
                        ),
                        child: Text(
                          genre,
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                      ),
                    _StatusChip(status: item.metadataStatus),
                  ],
                ),
                const SizedBox(height: 8),
                if (director != null && director.isNotEmpty)
                  Text(
                    '${l10n.videoDetailDirector} ${director.toUpperCase()}',
                    style: MovieDetailTheme.mono(AppTypography.bodySmall),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url, this.cacheKey});

  final String? url;
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    final resolved = url;
    if (resolved == null || resolved.isEmpty) {
      return const ColoredBox(color: MovieDetailTheme.surface);
    }
    return MoviePosterImage(
      imageUrl: resolved,
      cacheKey: cacheKey,
      cacheWidth: MoviePosterImage.decodeWidth(context, 160, cap: 480),
      alignment: Alignment.topCenter,
      fallback: const ColoredBox(color: MovieDetailTheme.surface),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final normalized = status.toUpperCase();
    final (color, hasBackground, label) = switch (normalized) {
      'MATCHED' => (
        MovieDetailTheme.mutedText,
        false,
        l10n.videoMetadataStatusComplete,
      ),
      'PENDING' => (
        MovieDetailTheme.statusPending,
        true,
        l10n.videoMetadataStatusNeedsWork,
      ),
      _ => (MovieDetailTheme.statusFailed, true, l10n.videoMetadataStatusIssue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            hasBackground ? color.withValues(alpha: 0.10) : Colors.transparent,
      ),
      child: Text(
        label,
        style: MovieDetailTheme.mono(AppTypography.bodySmall, color: color),
      ),
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(movieItemHistoryProvider(item.id));
    final progress = history.asData?.value?.progressPercent ?? 0;
    final showProgress = progress > 0 && progress < 100;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: MovieDetailTheme.foreground,
        child: InkWell(
          onTap: () => context.push('/video/${item.id}/play'),
          hoverColor: MovieDetailTheme.accent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(size: const Size(10, 12), painter: _PlayGlyph()),
                const SizedBox(width: 12),
                Text(
                  l10n.videoDetailPlay,
                  style: MovieDetailTheme.mono(
                    14,
                    color: MovieDetailTheme.background,
                    letterSpacing: 2,
                  ),
                ),
                if (showProgress)
                  Text(
                    ' (${progress.round()}%)',
                    style: MovieDetailTheme.mono(
                      12,
                      color: MovieDetailTheme.background,
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

class _PlayGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = MovieDetailTheme.background);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
