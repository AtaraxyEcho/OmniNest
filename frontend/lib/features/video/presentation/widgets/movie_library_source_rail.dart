part of 'movie_management.dart';

class _MediaLibrarySourceNavigator extends StatelessWidget {
  const _MediaLibrarySourceNavigator({
    required this.sources,
    required this.selectedSourceId,
    required this.bounded,
    required this.onSelected,
  });

  final List<VideoLibrarySource> sources;
  final String selectedSourceId;
  final bool bounded;
  final ValueChanged<VideoLibrarySource> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = ListView.separated(
      key: const Key('mediaLibrarySourceNavigator'),
      shrinkWrap: !bounded,
      physics: bounded ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final source = sources[index];
        return _MediaLibrarySourceItem(
          source: source,
          selected: source.id == selectedSourceId,
          onTap: () => onSelected(source),
        );
      },
    );
    return Container(
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.videoLibrarySourcesTitle,
                    style: TextStyle(
                      color: context.videoColors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  l10n.videoLibrarySourceCount(sources.length),
                  style: TextStyle(
                    color: context.videoColors.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (bounded) Expanded(child: list) else list,
        ],
      ),
    );
  }
}

class _MediaLibrarySourceItem extends StatelessWidget {
  const _MediaLibrarySourceItem({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final VideoLibrarySource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final offline = !source.enabled || source.healthStatus == 'OFFLINE';
    final failed = source.scanStatus == 'FAILED';
    final issue = failed || source.lastMissingCount > 0;
    final scanning =
        !offline &&
        const {'QUEUED', 'DISCOVERING', 'APPLYING'}.contains(source.scanStatus);
    final statusColor =
        offline || issue ? colorScheme.error : context.videoColors.primary;
    return Material(
      color:
          selected ? context.videoColors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: Key('mediaLibrarySource-${source.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      offline
                          ? Icons.folder_off_outlined
                          : _libraryTypeIcon(source.libraryType),
                      size: 19,
                      color: statusColor,
                    ),
                  ),
                  if (scanning)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: context.videoColors.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 8),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  selected
                                      ? context.videoColors.onPrimaryContainer
                                      : context.videoColors.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _SourceStatusBadge(source: source, dense: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _libraryTypeLabel(l10n, source.libraryType),
                      style: TextStyle(
                        color:
                            selected
                                ? context.videoColors.onPrimaryContainer
                                    .withValues(alpha: 0.78)
                                : context.videoColors.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _visibilityLabel(l10n, source.visibility),
                      style: TextStyle(
                        color:
                            selected
                                ? context.videoColors.onPrimaryContainer
                                    .withValues(alpha: 0.78)
                                : context.videoColors.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.videoSourceScanSummary(
                        source.lastScannedCount,
                        source.lastCandidateCount,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            selected
                                ? context.videoColors.onPrimaryContainer
                                    .withValues(alpha: 0.72)
                                : context.videoColors.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color:
                    selected
                        ? context.videoColors.onPrimaryContainer
                        : context.videoColors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceStatusBadge extends StatelessWidget {
  const _SourceStatusBadge({required this.source, this.dense = false});

  final VideoLibrarySource source;

  /// 紧凑形态：仅状态色点，用于来源列表行。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final offline = !source.enabled || source.healthStatus == 'OFFLINE';
    final failed = source.scanStatus == 'FAILED';
    final foreground =
        offline || failed
            ? colorScheme.onErrorContainer
            : source.scanStatus == 'READY'
            ? colorScheme.onTertiaryContainer
            : colorScheme.onPrimaryContainer;
    final background =
        offline || failed
            ? colorScheme.errorContainer
            : source.scanStatus == 'READY'
            ? colorScheme.tertiaryContainer
            : colorScheme.primaryContainer;
    final label =
        offline
            ? source.enabled
                ? l10n.videoSourceOffline
                : l10n.videoSourceDisabled
            : _sourceStatusLabel(l10n, source.scanStatus);
    if (dense) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: StatusDot(color: background),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
