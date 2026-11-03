part of 'movie_management.dart';

/// 影视管理列表的叶子部件：行数据载体、海报缩略与各类状态徽标。

/// 它们只按入参渲染，不持有列表状态，因此从列表文件拆出，
/// 让分页、筛选与行操作的代码留在同一个文件里。
class _AdminRowEntry {
  const _AdminRowEntry({
    required this.item,
    this.episodeCount,
    this.seriesTitle,
    this.isAnime = false,
  });

  final MovieVideoItem item;
  final int? episodeCount;

  /// 多集分组行的系列名与动漫归类（单文件条目为空）。
  final String? seriesTitle;
  final bool isAnime;
}

class _PosterThumb extends StatelessWidget {
  const _PosterThumb({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: MovieRedesignPalette.borderRadius,
        color: context.movieRedesign.muted,
        border: Border.all(color: context.movieRedesign.border),
      ),
      child:
          item.posterImageUrl != null
              ? MoviePosterImage(
                imageUrl: item.posterImageUrl,
                cacheKey: 'movie-poster:${item.id}',
                cacheWidth: MoviePosterImage.decodeWidth(context, 44, cap: 176),
                fallback: Icon(
                  Icons.movie_rounded,
                  size: 18,
                  color: context.movieRedesign.mutedForeground,
                ),
              )
              : Icon(
                Icons.movie_rounded,
                size: 18,
                color: context.movieRedesign.mutedForeground,
              ),
    );
  }
}

class _MetadataStatusPill extends StatelessWidget {
  const _MetadataStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (status) {
      'MATCHED' => l10n.videoMatched,
      'PENDING' => l10n.videoPendingScrape,
      'FAILED' => l10n.videoMatchFailed,
      'MANUAL' => l10n.videoManualEdit,
      _ => status,
    };
    final color = switch (status) {
      'MATCHED' => Colors.green.shade600,
      'PENDING' => Colors.amber.shade700,
      'FAILED' => Theme.of(context).colorScheme.error,
      _ => context.videoColors.onSurfaceVariant,
    };
    return _StatusPill(label: label, color: color);
  }
}

class _NfoStatusPill extends StatelessWidget {
  const _NfoStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color =
        status.toUpperCase() == 'NONE'
            ? context.videoColors.onSurfaceVariant
            : context.videoColors.primary;
    return _StatusPill(label: 'NFO · $status', color: color);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: MovieRedesignPalette.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        // ignore: font_size_whitelist
        style: context.movieRedesignText.mono(size: 10, color: color),
      ),
    );
  }
}

/// 管理区头部单行文字动作（等宽样式，替代旧版实底按钮）。
class _AdminTextAction extends StatelessWidget {
  const _AdminTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: MovieRedesignPalette.borderRadius,
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: MovieRedesignPalette.borderRadius,
        hoverColor: palette.foreground.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: context.movieRedesignText.mono(
              size: 12,
              color: palette.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showNfoPreview(BuildContext context, MovieVideoItem item) async {
  await showWorkstationDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.videoColors.surfaceContainerHigh,
          title: Text(
            AppLocalizations.of(dialogContext).videoNfoPreviewTitle(item.title),
          ),
          content: SizedBox(
            width: 600,
            height: 500,
            // 弹窗内订阅 autoDispose 提供器：一次性 read 的快照永远停在加载态，
            // 且没有监听者时提供器会立即销毁。
            child: Consumer(
              builder: (dialogContext, dialogRef, _) {
                final nfoAsync = dialogRef.watch(
                  movieNfoPreviewProvider(item.id),
                );
                final l10n = AppLocalizations.of(dialogContext);
                return nfoAsync.when(
                  data:
                      (nfo) => SingleChildScrollView(
                        child: SelectableText(
                          nfo.content,
                          style: TextStyle(
                            fontFamily: AppTypography.monoFamily,
                            fontFamilyFallback:
                                AppTypography.monoFamilyFallback,
                            fontSize: AppTypography.bodySmall,
                            color: dialogContext.videoColors.onSurface,
                          ),
                        ),
                      ),
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (e, _) => Center(
                        child: Text(
                          l10n.videoLoadFailedWith(movieErrorMessage(e, l10n)),
                        ),
                      ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(dialogContext).videoClose),
            ),
          ],
        ),
  );
}
