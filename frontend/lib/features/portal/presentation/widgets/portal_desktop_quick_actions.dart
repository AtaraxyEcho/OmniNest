part of 'portal_desktop_visual_shells.dart';

class _PortalFocusQuickActions extends ConsumerWidget {
  const _PortalFocusQuickActions({
    required this.palette,
    required this.item,
    required this.data,
    required this.onOpenImmersivePlayback,
  });

  final PortalVisualPalette palette;
  final PortalFocusItem item;
  final _PortalDesktopData data;
  final VoidCallback onOpenImmersivePlayback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemAction = _resolveSystemAction(context);
    final immersiveAction = _resolveImmersiveAction(context);
    final musicEntries = _musicEntries();
    final maxWidth = item.module == PortalFocusModule.music ? 720.0 : 760.0;
    final preview =
        item.module == PortalFocusModule.music
            ? _PortalModulePreviewShell(
              palette: palette,
              title: item.heroEyebrow ?? item.title,
              systemAction: systemAction,
              secondaryAction: immersiveAction,
              child: _PortalMusicFocusPreview(
                palette: palette,
                entries: musicEntries,
                onOpenQueue: () => showMusicDeckQueue(context),
              ),
            )
            : _PortalFocusPreviewPanel(
              palette: palette,
              item: item,
              data: data,
              systemAction: systemAction,
            );
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: preview),
      ),
    );
  }

  List<_PortalFocusPreviewEntry> _musicEntries() {
    final snapshot = data.music.asData?.value;
    if (snapshot == null) {
      return const <_PortalFocusPreviewEntry>[];
    }
    final entries = <_PortalFocusPreviewEntry>[];
    for (final track in snapshot.queuePreview) {
      entries.add(
        _PortalFocusPreviewEntry(
          icon: Icons.music_note_rounded,
          title: track.title,
          subtitle: track.artistName,
          route: '/music',
          imageUrl: track.coverUrl,
        ),
      );
    }
    return entries;
  }

  _PortalHeroAction _resolveSystemAction(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (item.module) {
      PortalFocusModule.reader => _PortalHeroAction(
        icon: Icons.library_books_rounded,
        label: l10n.portalEnterSystem,
        route: '/reader',
      ),
      PortalFocusModule.video => _PortalHeroAction(
        icon: Icons.video_library_rounded,
        label: l10n.portalEnterSystem,
        route: '/video',
      ),
      PortalFocusModule.photos => _PortalHeroAction(
        icon: Icons.grid_view_rounded,
        label: l10n.portalEnterSystem,
        route: '/photos',
      ),
      PortalFocusModule.music => _PortalHeroAction(
        icon: Icons.queue_music_rounded,
        label: l10n.portalEnterSystem,
        route: '/music',
      ),
      PortalFocusModule.files => _PortalHeroAction(
        icon: Icons.folder_rounded,
        label: l10n.portalEnterSystem,
        route: '/files',
      ),
      PortalFocusModule.weather => _PortalHeroAction(
        icon: Icons.cloud_rounded,
        label: l10n.portalWeatherTitle,
        route: '/portal',
      ),
      PortalFocusModule.tasks || PortalFocusModule.admin => _PortalHeroAction(
        icon: Icons.admin_panel_settings_rounded,
        label: l10n.portalAdmin,
        route: '/admin',
      ),
    };
  }

  _PortalHeroAction? _resolveImmersiveAction(BuildContext context) {
    if (item.module != PortalFocusModule.music) {
      return null;
    }
    final l10n = AppLocalizations.of(context);
    return _PortalHeroAction(
      icon: Icons.graphic_eq_rounded,
      label: l10n.portalImmersivePlayback,
      onTap: onOpenImmersivePlayback,
    );
  }
}

class _PortalMusicFocusPreview extends StatelessWidget {
  const _PortalMusicFocusPreview({
    required this.palette,
    required this.entries,
    required this.onOpenQueue,
  });

  final PortalVisualPalette palette;
  final List<_PortalFocusPreviewEntry> entries;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final miniPlayer = MusicDeckMiniPlayer(
      compact: true,
      palette: MusicMiniPlayerPalette(
        text: palette.text,
        muted: palette.muted,
        accent: palette.accentAlt,
        onAccent: palette.text,
      ),
      managePlaybackSession: true,
      embedded: true,
      onOpenQueue: onOpenQueue,
    );
    if (entries.isEmpty) {
      return miniPlayer;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final waterfall = _PortalFocusPreviewWaterfall(
          palette: palette,
          entries: entries,
        );
        if (!constraints.maxHeight.isFinite) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              miniPlayer,
              const SizedBox(height: 10),
              SizedBox(height: 320, child: waterfall),
            ],
          );
        }
        return Column(
          children: [
            miniPlayer,
            const SizedBox(height: 10),
            Expanded(child: waterfall),
          ],
        );
      },
    );
  }
}

class _PortalFocusPreviewPanel extends StatelessWidget {
  const _PortalFocusPreviewPanel({
    required this.palette,
    required this.item,
    required this.data,
    required this.systemAction,
  });

  final PortalVisualPalette palette;
  final PortalFocusItem item;
  final _PortalDesktopData data;
  final _PortalHeroAction systemAction;

  @override
  Widget build(BuildContext context) {
    final entries = switch (item.module) {
      PortalFocusModule.reader => _readerEntries(context),
      PortalFocusModule.video => _videoEntries(context),
      PortalFocusModule.photos => _photoEntries(context),
      PortalFocusModule.files ||
      PortalFocusModule.weather ||
      PortalFocusModule.tasks ||
      PortalFocusModule.admin ||
      PortalFocusModule.music => const <_PortalFocusPreviewEntry>[],
    };
    if (entries.isEmpty) {
      return _PortalModulePreviewShell(
        palette: palette,
        title: item.heroEyebrow ?? item.title,
        systemAction: systemAction,
        child: _PortalFocusEmptyPreview(palette: palette, item: item),
      );
    }
    return _PortalModulePreviewShell(
      palette: palette,
      title: item.heroEyebrow ?? item.title,
      systemAction: systemAction,
      child: _PortalFocusPreviewWaterfall(palette: palette, entries: entries),
    );
  }

  List<_PortalFocusPreviewEntry> _readerEntries(BuildContext context) {
    final dashboard = data.readerDashboard.asData?.value;
    if (dashboard == null) {
      return const [];
    }
    final seen = <String>{};
    final items = <ReaderItem>[
      ...dashboard.continueReading,
      ...dashboard.recentItems,
    ].where((readerItem) => seen.add(readerItem.id)).take(6);
    return [
      for (final readerItem in items)
        _PortalFocusPreviewEntry(
          icon:
              readerItem.isComic
                  ? Icons.auto_stories_rounded
                  : Icons.menu_book_rounded,
          title: readerItem.title,
          subtitle:
              readerItem.currentChapterTitle?.isNotEmpty == true
                  ? readerItem.currentChapterTitle!
                  : readerItem.authorName ??
                      AppLocalizations.of(context).portalDockReading,
          route:
              readerItem.isComic
                  ? '/reader/comics/${readerItem.id}/read'
                  : '/reader/items/${readerItem.id}',
          imageUrl: readerItem.coverUrl,
          readerItemId: readerItem.hasCover ? readerItem.id : null,
        ),
    ];
  }

  List<_PortalFocusPreviewEntry> _videoEntries(BuildContext context) {
    final dashboard = data.movieDashboard.asData?.value;
    if (dashboard == null) {
      return const [];
    }
    final entries = <_PortalFocusPreviewEntry>[];
    final seen = <String>{};
    final recentById = {
      for (final movie in dashboard.recentlyAdded) movie.id: movie,
    };
    for (final watching in dashboard.continueWatching) {
      if (!seen.add(watching.id)) {
        continue;
      }
      final matchedMovie = recentById[watching.id];
      entries.add(
        _PortalFocusPreviewEntry(
          icon: Icons.play_circle_rounded,
          title: watching.title,
          subtitle:
              '${watching.progressPercent.clamp(0, 100).round()}% · ${AppLocalizations.of(context).portalContinueWatching}',
          route: '/video/${watching.id}/play',
          imageUrl:
              watching.posterUrl ??
              matchedMovie?.posterImageUrl ??
              matchedMovie?.backdropImageUrl,
        ),
      );
      if (entries.length >= 6) {
        return entries;
      }
    }
    for (final movie in dashboard.recentlyAdded) {
      if (!seen.add(movie.id)) {
        continue;
      }
      entries.add(
        _PortalFocusPreviewEntry(
          icon: Icons.movie_rounded,
          title: movie.title,
          subtitle: movie.year,
          route: '/video/${movie.id}',
          imageUrl: movie.posterImageUrl ?? movie.backdropImageUrl,
        ),
      );
      if (entries.length >= 6) {
        return entries;
      }
    }
    return entries;
  }

  List<_PortalFocusPreviewEntry> _photoEntries(BuildContext context) {
    final dashboard = data.photoDashboard.asData?.value;
    if (dashboard == null) {
      return const [];
    }
    return [
      for (final photo in dashboard.recentPhotos.take(6))
        _PortalFocusPreviewEntry(
          icon: Icons.photo_rounded,
          title: photo.title,
          subtitle: photo.format.toUpperCase(),
          route: '/photos/${photo.id}',
          imageUrl: photo.coverUrl,
        ),
    ];
  }
}

class _PortalFocusPreviewEntry {
  const _PortalFocusPreviewEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.imageUrl,
    this.readerItemId,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final String? imageUrl;
  final String? readerItemId;
}

class _PortalModulePreviewShell extends StatelessWidget {
  const _PortalModulePreviewShell({
    required this.palette,
    required this.title,
    required this.systemAction,
    required this.child,
    this.secondaryAction,
  });

  final PortalVisualPalette palette;
  final String title;
  final _PortalHeroAction systemAction;
  final _PortalHeroAction? secondaryAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0;
        final shell = Container(
          width: double.infinity,
          constraints:
              boundedHeight ? null : const BoxConstraints(minHeight: 360),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (secondaryAction != null) ...[
                    _PortalHeroActionButton(
                      palette: palette,
                      action: secondaryAction!,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _PortalHeroActionButton(
                    palette: palette,
                    action: systemAction,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (boundedHeight)
                Expanded(
                  child: Align(alignment: Alignment.topLeft, child: child),
                )
              else
                child,
            ],
          ),
        );
        if (!boundedHeight) {
          return shell;
        }
        return SizedBox(height: constraints.maxHeight, child: shell);
      },
    );
  }
}

class _PortalFocusPreviewWaterfall extends StatelessWidget {
  const _PortalFocusPreviewWaterfall({
    required this.palette,
    required this.entries,
  });

  final PortalVisualPalette palette;
  final List<_PortalFocusPreviewEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 560.0;
        final availableHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 360.0;
        final columns =
            width >= 620
                ? 4
                : width >= 420
                ? 3
                : width >= 280
                ? 2
                : 1;
        final viewportHeight =
            availableHeight.isFinite && availableHeight > 0
                ? availableHeight
                : 360.0;
        final spacing =
            columns == 1
                ? 0.0
                : columns >= 3
                ? 12.0
                : 10.0;
        final rawCardWidth = (width - spacing * (columns - 1)) / columns;
        final minCardWidth = math.min(112.0, width);
        final maxCardWidth = columns == 1 ? width : 176.0;
        final cardWidth =
            rawCardWidth.clamp(minCardWidth, maxCardWidth).toDouble();
        final maxCardHeight =
            availableHeight.isFinite && availableHeight > 0
                ? math.min(232.0, viewportHeight)
                : 232.0;
        final minCardHeight = math.min(150.0, maxCardHeight);
        final cardHeight =
            (cardWidth * 1.32).clamp(minCardHeight, maxCardHeight).toDouble();
        return SizedBox(
          height: viewportHeight,
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                alignment: WrapAlignment.start,
                runAlignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final entry in entries)
                    _PortalFocusPreviewCard(
                      palette: palette,
                      entry: entry,
                      width: cardWidth,
                      height: cardHeight,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PortalFocusPreviewImage extends StatelessWidget {
  const _PortalFocusPreviewImage({required this.palette, required this.entry});

  final PortalVisualPalette palette;
  final _PortalFocusPreviewEntry entry;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(entry.icon, color: palette.text, size: 22),
    );
    final readerItemId = entry.readerItemId?.trim();
    if (readerItemId != null && readerItemId.isNotEmpty) {
      return AuthCoverImage(
        itemId: readerItemId,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(7),
        fallback: fallback,
      );
    }
    return PortalMediaThumbnail(
      imageUrl: entry.imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 420,
      cacheHeight: 560,
      borderRadius: BorderRadius.circular(7),
      fallback: fallback,
    );
  }
}

class _PortalFocusPreviewCard extends StatelessWidget {
  const _PortalFocusPreviewCard({
    required this.palette,
    required this.entry,
    required this.width,
    required this.height,
  });

  final PortalVisualPalette palette;
  final _PortalFocusPreviewEntry entry;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(entry.route),
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PortalFocusPreviewImage(
                      palette: palette,
                      entry: entry,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: AppTypography.labelSmall,
                    ),
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

class _PortalFocusEmptyPreview extends StatelessWidget {
  const _PortalFocusEmptyPreview({required this.palette, required this.item});

  final PortalVisualPalette palette;
  final PortalFocusItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(item.icon.iconData, color: palette.text, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalHeroAction {
  const _PortalHeroAction({
    required this.icon,
    required this.label,
    this.route,
    this.onTap,
  }) : assert(route != null || onTap != null);

  final IconData icon;
  final String label;
  final String? route;
  final VoidCallback? onTap;
}

class _PortalHeroActionButton extends StatelessWidget {
  const _PortalHeroActionButton({
    required this.palette,
    required this.action,
    this.compact = false,
  });

  final PortalVisualPalette palette;
  final _PortalHeroAction action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: action.onTap ?? () => context.go(action.route!),
        child: Container(
          height: compact ? 32 : 36,
          constraints: BoxConstraints(maxWidth: compact ? 116 : 168),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: palette.text, size: 16),
              SizedBox(width: compact ? 6 : 8),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
