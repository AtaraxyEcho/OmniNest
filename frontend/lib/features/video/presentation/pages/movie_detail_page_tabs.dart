part of 'movie_detail_page.dart';

/// 影片详情页页签：tab 栏、简介、版本列表。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.active, required this.onSelect});

  final _DetailTab active;
  final ValueChanged<_DetailTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = {
      _DetailTab.overview: l10n.videoDetailTabOverview,
      _DetailTab.versions: l10n.videoDetailTabVersions,
      _DetailTab.subtitles: l10n.videoDetailTabSubtitles,
    };
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MovieDetailTheme.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in tabs.entries)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color:
                            active == entry.key
                                ? MovieDetailTheme.accent
                                : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: MovieDetailTheme.mono(
                      12,
                      color:
                          active == entry.key
                              ? MovieDetailTheme.foreground
                              : MovieDetailTheme.mutedText,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.item,
    required this.editMode,
    required this.overviewController,
  });

  final MovieVideoItem item;
  final bool editMode;
  final TextEditingController overviewController;

  @override
  Widget build(BuildContext context) {
    final overview = item.overview ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (editMode)
          TextField(
            controller: overviewController,
            maxLines: 5,
            cursorColor: MovieDetailTheme.accent,
            style: MovieDetailTheme.body(
              14,
              color: MovieDetailTheme.secondaryText,
              height: 1.6,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: MovieDetailTheme.surface,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: MovieDetailTheme.accent.withValues(alpha: 0.30),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: MovieDetailTheme.accent.withValues(alpha: 0.30),
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          )
        else if (overview.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Text(
              overview,
              style: MovieDetailTheme.body(
                14,
                color: MovieDetailTheme.secondaryText,
                height: 1.6,
              ),
            ),
          ),
        if (item.castMembers.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            AppLocalizations.of(context).videoDetailCast,
            style: MovieDetailTheme.mono(
              AppTypography.bodySmall,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 800 ? 3 : 2;
              const gap = 12.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final member in item.castMembers)
                    SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              width: 2,
                              color: MovieDetailTheme.border,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _CastAvatar(
                              name: member.name,
                              profileUrl: member.profilePath,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MovieDetailTheme.body(
                                      14,
                                      color: MovieDetailTheme.foreground,
                                    ),
                                  ),
                                  if (member.character != null &&
                                      member.character!.isNotEmpty)
                                    Text(
                                      member.character!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MovieDetailTheme.mono(
                                        AppTypography.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _VersionsTab extends ConsumerWidget {
  const _VersionsTab({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final versionsAsync = ref.watch(movieVersionsProvider(item.id));
    return versionsAsync.when(
      loading:
          () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error:
          (error, _) => Text(
            movieErrorMessage(error),
            style: MovieDetailTheme.mono(AppTypography.bodySmall),
          ),
      data: (versions) {
        if (versions.isEmpty) {
          return Text(
            l10n.videoDetailNoVersions,
            style: MovieDetailTheme.mono(AppTypography.bodySmall),
          );
        }
        final activeId = item.id;
        return Column(
          children: [
            for (final version in versions)
              _VersionRow(
                version: version,
                isActive: version.id == activeId,
                onPlay: () => context.push('/video/${version.id}/play'),
              ),
          ],
        );
      },
    );
  }
}

/// 可点击播放的版本行；高亮当前条目对应版本。
class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.isActive,
    required this.onPlay,
  });

  final MovieVideoItem version;
  final bool isActive;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = version.versionLabel ?? l10n.videoRedesignOriginalVersion;
    final meta = [
      if (version.videoCodec != null && version.videoCodec!.trim().isNotEmpty)
        version.videoCodec!.trim().toUpperCase(),
      if (version.containerFormat != null &&
          version.containerFormat!.trim().isNotEmpty)
        version.containerFormat!.trim().toLowerCase(),
    ].join(' · ');
    final resolution =
        version.resolutionHeight != null && version.resolutionHeight! > 0
            ? '${version.resolutionHeight}p'
            : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color:
                isActive
                    ? MovieDetailTheme.accent.withValues(alpha: 0.08)
                    : null,
            border: Border.all(
              color:
                  isActive
                      ? MovieDetailTheme.accent.withValues(alpha: 0.55)
                      : MovieDetailTheme.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: MovieDetailTheme.body(
                        14,
                        color: MovieDetailTheme.foreground,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: MovieDetailTheme.mono(AppTypography.bodySmall),
                      ),
                    ],
                  ],
                ),
              ),
              if (resolution != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    resolution,
                    style: MovieDetailTheme.mono(
                      12,
                      color: MovieDetailTheme.accent,
                    ),
                  ),
                ),
              Tooltip(
                message: l10n.videoDetailPlay,
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color:
                      isActive
                          ? MovieDetailTheme.accent
                          : MovieDetailTheme.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
