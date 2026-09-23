part of 'music_deck_content.dart';

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.musicColors.onSurface,
            fontSize: AppTypography.headlineSmall,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.musicColors.onSurfaceVariant,
            fontSize: AppTypography.bodySmall,
            height: 1.4,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (trailing != null && constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: trailing),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: identity),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        );
      },
    );
  }
}

class _CollectionDetailHeader extends StatelessWidget {
  const _CollectionDetailHeader({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.source,
    required this.onBack,
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final MusicPlatform source;
  final VoidCallback onBack;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final identity = Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            SizedBox(width: compact ? 4 : 8),
            SizedBox.square(
              dimension: compact ? 56 : 72,
              child: MusicDeckArtwork(title: title, imageUrl: imageUrl),
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.musicColors.onSurface,
                      fontSize: compact ? 18 : 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      MusicDeckSourceBadge(platform: source),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.musicColors.onSurfaceVariant,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        final playButton = MusicPlaybackButton(
          onPressed: onPlay,
          isPlaying: false,
          tooltip: AppLocalizations.of(context).musicPlay,
          buttonSize:
              compact
                  ? MusicPlaybackButtonSize.compact
                  : MusicPlaybackButtonSize.regular,
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: playButton),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 16),
            playButton,
          ],
        );
      },
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.view, required this.onViewChanged});

  final MusicDeckLibraryView view;
  final ValueChanged<MusicDeckLibraryView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selector = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<MusicDeckLibraryView>(
        segments: <ButtonSegment<MusicDeckLibraryView>>[
          ButtonSegment(
            value: MusicDeckLibraryView.tracks,
            label: Text(l10n.musicNavSongs),
          ),
          ButtonSegment(
            value: MusicDeckLibraryView.albums,
            label: Text(l10n.musicNavAlbums),
          ),
          ButtonSegment(
            value: MusicDeckLibraryView.artists,
            label: Text(l10n.musicNavArtists),
          ),
          ButtonSegment(
            value: MusicDeckLibraryView.genres,
            label: Text(l10n.musicNavGenres),
          ),
        ],
        selected: <MusicDeckLibraryView>{view},
        showSelectedIcon: false,
        onSelectionChanged: (value) => onViewChanged(value.first),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ContentHeader(
                title: l10n.musicDeckLibrary,
                subtitle: l10n.musicDeckLibrarySubtitle,
              ),
              const SizedBox(height: 12),
              selector,
            ],
          );
        }
        return _ContentHeader(
          title: l10n.musicDeckLibrary,
          subtitle: l10n.musicDeckLibrarySubtitle,
          trailing: selector,
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.musicColors.onSurface,
              fontSize: AppTypography.titleLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (actionLabel != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
            iconAlignment: IconAlignment.end,
            label: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MusicDeckGlass(
      opacity: 0.12,
      blur: 8,
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.musicColors.onSurfaceVariant,
            fontSize: AppTypography.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _PartialFailureBanner extends StatelessWidget {
  const _PartialFailureBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MusicDeckGlass(
      opacity: 0.2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_rounded, color: Color(0xFFF0CD76)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.musicColors.onSurface,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context).musicDeckRetry),
          ),
        ],
      ),
    );
  }
}

List<MusicPlayableItem> _libraryItems(
  MusicCenterState center,
  MusicPlatformLibraryState platform,
  Set<MusicPlatform> sources,
) {
  return <MusicPlayableItem>[
    if (sources.contains(MusicPlatform.local))
      ...center.tracks.map(MusicPlayableItem.local),
    for (final source in sources)
      if (source != MusicPlatform.local)
        ...(platform.likedTracksByPlatform[source.apiValue] ??
                const <OnlineTrack>[])
            .map(MusicPlayableItem.online),
  ];
}

List<MusicDeckCoverItem> _albumCoverItems(
  MusicCenterState center,
  MusicPlatformLibraryState platform,
  Set<MusicPlatform> sources,
  ValueChanged<MusicDeckCollectionSelection> onOpenCollection,
) {
  final items = <MusicDeckCoverItem>[];
  if (sources.contains(MusicPlatform.local)) {
    items.addAll(
      center.albums.map(
        (album) => MusicDeckCoverItem(
          id: album.id,
          title: album.title,
          subtitle: album.artistName,
          imageUrl: album.listCoverUrl,
          onTap: () => onOpenCollection(AlbumMusicDeckCollection(album)),
        ),
      ),
    );
  }
  for (final source in sources.where(
    (source) => source != MusicPlatform.local,
  )) {
    final groups = <String, List<OnlineTrack>>{};
    for (final track in _knownOnlineTracks(platform, source)) {
      final album = track.albumTitle.trim();
      if (album.isEmpty) {
        continue;
      }
      groups
          .putIfAbsent('$album\u0000${track.artistName}', () => [])
          .add(track);
    }
    for (final tracks in groups.values) {
      final first = tracks.first;
      final selection = OnlineAlbumMusicDeckCollection(
        platform: source,
        title: first.albumTitle,
        artistName: first.artistName,
        coverUrl: first.listCoverUrl,
        tracks: List<OnlineTrack>.unmodifiable(tracks),
      );
      items.add(
        MusicDeckCoverItem(
          id: '${source.apiValue}:album:${first.albumTitle}:${first.artistName}',
          title: first.albumTitle,
          subtitle: first.artistName,
          imageUrl: first.listCoverUrl,
          platform: source,
          onTap: () => onOpenCollection(selection),
        ),
      );
    }
  }
  return items;
}

List<MusicDeckCoverItem> _artistCoverItems(
  AppLocalizations l10n,
  MusicCenterState center,
  MusicPlatformLibraryState platform,
  Set<MusicPlatform> sources,
  ValueChanged<MusicDeckCollectionSelection> onOpenCollection,
) {
  final items = <MusicDeckCoverItem>[];
  if (sources.contains(MusicPlatform.local)) {
    items.addAll(
      center.artists.map(
        (artist) => MusicDeckCoverItem(
          id: artist.id,
          title: artist.name,
          subtitle: l10n.musicDeckTrackCount(artist.trackCount),
          imageUrl: artist.listCoverUrl,
          icon: Icons.person_rounded,
          onTap: () => onOpenCollection(ArtistMusicDeckCollection(artist)),
        ),
      ),
    );
  }
  for (final source in sources.where(
    (source) => source != MusicPlatform.local,
  )) {
    final groups = <String, List<OnlineTrack>>{};
    for (final track in _knownOnlineTracks(platform, source)) {
      final artist = track.artistName.trim();
      if (artist.isEmpty) {
        continue;
      }
      groups.putIfAbsent(artist, () => []).add(track);
    }
    for (final entry in groups.entries) {
      final tracks = entry.value;
      final coverUrl = tracks
          .map((track) => track.listCoverUrl)
          .firstWhere((url) => url.isNotEmpty, orElse: () => '');
      final selection = OnlineArtistMusicDeckCollection(
        platform: source,
        name: entry.key,
        coverUrl: coverUrl,
        tracks: List<OnlineTrack>.unmodifiable(tracks),
      );
      items.add(
        MusicDeckCoverItem(
          id: '${source.apiValue}:artist:${entry.key}',
          title: entry.key,
          subtitle: l10n.musicDeckTrackCount(tracks.length),
          imageUrl: coverUrl,
          icon: Icons.person_rounded,
          platform: source,
          onTap: () => onOpenCollection(selection),
        ),
      );
    }
  }
  return items;
}

List<OnlineTrack> _knownOnlineTracks(
  MusicPlatformLibraryState platform,
  MusicPlatform source,
) {
  final tracks = <OnlineTrack>[
    ...(platform.likedTracksByPlatform[source.apiValue] ??
        const <OnlineTrack>[]),
    for (final entry in platform.playlistTracks.entries)
      if (entry.key.startsWith('${source.apiValue}:')) ...entry.value.items,
  ];
  final knownIds = <String>{};
  return tracks
      .where((track) => knownIds.add(track.songId))
      .toList(growable: false);
}

Future<void> _showCreatePlaylistDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final draft = await showDialog<MusicDeckPlaylistDraft>(
    context: context,
    builder: (dialogContext) => const MusicDeckCreatePlaylistDialog(),
  );
  if (draft == null || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(musicCenterControllerProvider.notifier)
        .createPlaylist(
          name: draft.name,
          description: draft.description,
          coverBytes: draft.coverBytes,
          coverFileName: draft.coverFileName,
        );
  } on Exception catch (error) {
    if (context.mounted) {
      _showPlaylistMessage(
        context,
        AppLocalizations.of(
          context,
        ).musicPlaylistSaveFailed(describeUserFacingError(error).message),
      );
    }
  }
}

Future<void> _showEditPlaylistDialog(
  BuildContext context,
  WidgetRef ref,
  MusicPlaylist playlist,
) async {
  final draft = await showDialog<MusicDeckPlaylistDraft>(
    context: context,
    builder:
        (dialogContext) => MusicDeckCreatePlaylistDialog(
          initialName: playlist.name,
          initialDescription: playlist.description,
          initialCoverUrl: playlist.coverUrl,
          editing: true,
        ),
  );
  if (draft == null || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(musicCenterControllerProvider.notifier)
        .updatePlaylist(
          playlist,
          name: draft.name,
          description: draft.description,
          coverBytes: draft.coverBytes,
          coverFileName: draft.coverFileName,
        );
  } on Exception catch (error) {
    if (context.mounted) {
      _showPlaylistMessage(
        context,
        AppLocalizations.of(
          context,
        ).musicPlaylistSaveFailed(describeUserFacingError(error).message),
      );
    }
  }
}

Future<void> _confirmDeletePlaylist(
  BuildContext context,
  WidgetRef ref,
  MusicPlaylist playlist,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(l10n.musicDeletePlaylistTitle),
          content: Text(l10n.musicDeletePlaylistMessage(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.musicCancel),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC8353D),
                foregroundColor: context.musicColors.onSurface,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(l10n.musicDeletePlaylist),
            ),
          ],
        ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(musicCenterControllerProvider.notifier)
        .deletePlaylist(playlist);
  } on Exception catch (error) {
    if (context.mounted) {
      _showPlaylistMessage(
        context,
        AppLocalizations.of(
          context,
        ).musicPlaylistDeleteFailed(describeUserFacingError(error).message),
      );
    }
  }
}

void _showPlaylistMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

List<MusicPlayableItem> _favoriteItems(
  MusicCenterState center,
  MusicPlatformLibraryState platform,
  Set<MusicPlatform> sources,
) {
  return <MusicPlayableItem>[
    if (sources.contains(MusicPlatform.local))
      ...center.tracks
          .where((track) => track.favorite)
          .map(MusicPlayableItem.local),
    for (final source in sources)
      if (source != MusicPlatform.local)
        ...(platform.likedTracksByPlatform[source.apiValue] ??
                const <OnlineTrack>[])
            .map(MusicPlayableItem.online),
  ];
}

List<MusicPlayableItem> _recentItems(
  MusicCenterState center,
  Set<MusicPlatform> sources,
) {
  return center.recentItems
      .where((item) {
        return switch (item.ref) {
          LocalMusicRef() => sources.contains(MusicPlatform.local),
          OnlineMusicRef(:final platform) => sources.contains(platform),
        };
      })
      .toList(growable: false);
}

List<MusicDeckCoverItem> _playlistCoverItems(
  BuildContext context,
  MusicCenterState center,
  MusicPlatformLibraryState platform,
  Set<MusicPlatform> sources,
  ValueChanged<MusicDeckCollectionSelection> onOpenCollection, {
  ValueChanged<MusicPlaylist>? onEdit,
  ValueChanged<MusicPlaylist>? onDelete,
}) {
  final l10n = AppLocalizations.of(context);
  return <MusicDeckCoverItem>[
    if (sources.contains(MusicPlatform.local))
      for (final playlist in center.playlists)
        MusicDeckCoverItem(
          id: playlist.id,
          title: playlist.name,
          subtitle: l10n.musicDeckTrackCount(playlist.trackCount),
          imageUrl: playlist.listCoverUrl,
          actions:
              playlist.playlistType == 'CUSTOM' &&
                      onEdit != null &&
                      onDelete != null
                  ? <MusicDeckCoverAction>[
                    MusicDeckCoverAction(
                      label: l10n.musicEditPlaylist,
                      icon: Icons.edit_outlined,
                      onSelected: () => onEdit(playlist),
                    ),
                    MusicDeckCoverAction(
                      label: l10n.musicDeletePlaylist,
                      icon: Icons.delete_outline_rounded,
                      destructive: true,
                      onSelected: () => onDelete(playlist),
                    ),
                  ]
                  : const <MusicDeckCoverAction>[],
          onTap: () => onOpenCollection(LocalMusicDeckCollection(playlist)),
        ),
    for (final source in sources)
      if (source != MusicPlatform.local)
        for (final playlist
            in platform.playlistsByPlatform[source.apiValue] ??
                const <OnlinePlaylist>[])
          MusicDeckCoverItem(
            id: '${playlist.platform}:${playlist.playlistId}',
            title: playlist.name,
            subtitle:
                playlist.ownerName.isEmpty
                    ? l10n.musicDeckTrackCount(playlist.trackCount ?? 0)
                    : playlist.ownerName,
            imageUrl: platform.coverUrlForPlaylist(playlist),
            platform: source,
            onTap: () => onOpenCollection(OnlineMusicDeckCollection(playlist)),
          ),
  ];
}

ValueChanged<MusicPlayableItem> _favoriteHandler(WidgetRef ref) {
  return (item) {
    if (item.ref is LocalMusicRef) {
      ref
          .read(musicCenterControllerProvider.notifier)
          .toggleFavorite(item.track);
    }
  };
}

ValueChanged<MusicPlayableItem> _enqueueTrackHandler(
  BuildContext context,
  WidgetRef ref,
) {
  return (item) {
    ref.read(musicCenterControllerProvider.notifier).enqueue(item);
    _showPlaylistMessage(
      context,
      AppLocalizations.of(context).musicPlayNextAdded,
    );
  };
}

ValueChanged<MusicPlayableItem> _addToPlaylistHandler(
  BuildContext context,
  WidgetRef ref,
) {
  return (item) {
    showMusicAddToPlaylistSheet(context, ref, item);
  };
}

ValueChanged<MusicPlayableItem> _deleteTrackHandler(
  BuildContext context,
  WidgetRef ref,
) {
  return (item) async {
    if (item.ref is! LocalMusicRef) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      final deleted = await confirmAndRunFilePurge(
        context,
        resourceName: item.track.title,
        action: (cascade) async {
          await ref
              .read(musicCenterControllerProvider.notifier)
              .deleteTrack(item.track, cascade: cascade);
        },
      );
      if (!deleted || !context.mounted) return;
      if (context.mounted) {
        _showPlaylistMessage(context, l10n.musicDeleteLocalTrackSuccess);
      }
    } on Exception {
      if (context.mounted) {
        _showPlaylistMessage(context, l10n.musicDeleteLocalTrackFailed);
      }
    }
  };
}
