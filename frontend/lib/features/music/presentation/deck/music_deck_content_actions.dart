part of 'music_deck_content.dart';

/// 曲库批量操作条：全选、加入歌单、下一首播放与退出多选。
class _MusicBatchActionBar extends ConsumerWidget {
  const _MusicBatchActionBar({required this.center, required this.selection});

  final MusicCenterState center;
  final MusicSelectionState selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    final notifier = ref.read(musicSelectionControllerProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(
            l10n.musicSelectionCount(selection.selectedIds.length),
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed:
                () =>
                    notifier.selectAll(center.tracks.map((track) => track.id)),
            child: Text(l10n.musicSelectionSelectAll),
          ),
          TextButton(
            onPressed:
                selection.hasSelection
                    ? () => _addToPlaylist(context, ref)
                    : null,
            child: Text(l10n.musicAddToPlaylist),
          ),
          TextButton(
            onPressed:
                selection.hasSelection ? () => _enqueue(context, ref) : null,
            child: Text(l10n.musicPlayNext),
          ),
          IconButton(
            tooltip: l10n.musicSelectionExit,
            onPressed: notifier.exitSelectionMode,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final playlist = await _showPlaylistPicker(context, ref);
    if (playlist == null || !context.mounted) {
      return;
    }
    final notifier = ref.read(musicSelectionControllerProvider.notifier);
    final results = await notifier.addSelectedToPlaylist(
      playlist,
      center.tracks,
    );
    if (!context.mounted) {
      return;
    }
    final success = results.where((item) => item.success).length;
    final failedTitles =
        results
            .where((item) => !item.success)
            .map((item) => item.title)
            .toList();
    final failed = failedTitles.length;
    final text =
        failed == 0
            ? l10n.musicBatchAddedToPlaylist(success, playlist.name)
            : '${l10n.musicBatchPartial(success, failed)}'
                ' · ${l10n.musicBatchFailedTitles(failedTitles.join(', '))}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _enqueue(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(musicSelectionControllerProvider.notifier);
    final results = notifier.enqueueSelected(center.tracks);
    notifier.exitSelectionMode();
    if (!context.mounted) {
      return;
    }
    final success = results.where((item) => item.success).length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.musicBatchEnqueued(success))));
  }

  Future<MusicPlaylist?> _showPlaylistPicker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    MusicPlaylist? selected;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final playlists = center.playlists;
        return SafeArea(
          child: Material(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final playlist in playlists)
                  ListTile(
                    title: Text(playlist.name),
                    onTap: () {
                      selected = playlist;
                      Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
    return selected;
  }
}

/// 艺人详情页的专辑横向封面架，进入详情时按需加载。
class _ArtistAlbumsShelf extends ConsumerStatefulWidget {
  const _ArtistAlbumsShelf({required this.artistId});

  final String artistId;

  @override
  ConsumerState<_ArtistAlbumsShelf> createState() => _ArtistAlbumsShelfState();
}

class _ArtistAlbumsShelfState extends ConsumerState<_ArtistAlbumsShelf> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(musicArtistAlbumsControllerProvider.notifier)
            .ensureLoaded(widget.artistId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicArtistAlbumsControllerProvider);
    final albums = state.albumsByArtist[widget.artistId];
    if (albums == null || albums.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final items = [
      for (final album in albums)
        MusicDeckCoverItem(
          id: album.id,
          title: album.title,
          subtitle: l10n.musicDeckTrackCount(album.trackCount),
          imageUrl: album.coverUrl,
          icon: Icons.album_rounded,
          onTap:
              () => ref
                  .read(musicCenterControllerProvider.notifier)
                  .openAlbum(album),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: MusicDeckCoverShelf(items: items),
    );
  }
}

/// 流派浏览：客户端聚合本地曲目 genre → 计数，点按流派过滤曲目。
class _GenresContent extends ConsumerStatefulWidget {
  const _GenresContent({
    required this.center,
    required this.platform,
    required this.sources,
  });

  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final Set<MusicPlatform> sources;

  @override
  ConsumerState<_GenresContent> createState() => _GenresContentState();
}

class _GenresContentState extends ConsumerState<_GenresContent> {
  String? _selectedGenre;
  List<MusicTrack>? _groupedTracks;
  Map<String, List<MusicTrack>>? _groupedByGenre;

  /// 按曲目列表身份缓存分组：中心状态每次发布都是新实例，但 `tracks` 列表
  /// 通常原样传递，列表未变时不再整表重分组。
  Map<String, List<MusicTrack>> _groupByGenre(List<MusicTrack> tracks) {
    final cached = _groupedByGenre;
    if (cached != null && identical(_groupedTracks, tracks)) {
      return cached;
    }
    final result = <String, List<MusicTrack>>{};
    for (final track in tracks) {
      final genre = track.genre?.trim();
      if (genre == null || genre.isEmpty) {
        continue;
      }
      result.putIfAbsent(genre, () => []).add(track);
    }
    _groupedTracks = tracks;
    _groupedByGenre = result;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byGenre = _groupByGenre(widget.center.tracks);
    final genres = byGenre.keys.toList()..sort();
    if (genres.isEmpty) {
      return _InlineEmpty(message: l10n.musicGenresEmpty);
    }
    final selectedGenre =
        _selectedGenre != null && genres.contains(_selectedGenre)
            ? _selectedGenre!
            : null;
    final filteredTracks =
        selectedGenre == null ? <MusicTrack>[] : byGenre[selectedGenre]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              for (final genre in genres)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$genre (${byGenre[genre]!.length})'),
                    selected: selectedGenre == genre,
                    onSelected: (selected) {
                      setState(() {
                        _selectedGenre = selected ? genre : null;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child:
              selectedGenre == null
                  ? Center(
                    child: Text(
                      l10n.musicGenresPickHint,
                      style: TextStyle(
                        color: context.musicColors.onSurfaceVariant,
                      ),
                    ),
                  )
                  : MusicDeckTrackList(
                    items: filteredTracks
                        .map(MusicPlayableItem.local)
                        .toList(growable: false),
                    currentPlayableKey: widget.center.currentItem?.playableKey,
                    onPlay:
                        (index) => ref
                            .read(musicCenterControllerProvider.notifier)
                            .playItems(
                              filteredTracks
                                  .map(MusicPlayableItem.local)
                                  .toList(growable: false),
                              startIndex: index,
                            ),
                    onToggleFavorite: _favoriteHandler(ref),
                    onDelete: _deleteTrackHandler(context, ref),
                    onEnqueue: _enqueueTrackHandler(context, ref),
                    onAddToPlaylist: _addToPlaylistHandler(context, ref),
                  ),
        ),
      ],
    );
  }
}
