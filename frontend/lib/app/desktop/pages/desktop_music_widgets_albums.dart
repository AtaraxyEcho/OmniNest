part of 'desktop_music_page.dart';

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final MusicAlbum album;
  final VoidCallback onTap;

  Future<void> _playAlbum(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(musicCenterControllerProvider.notifier);
    final state = ref.read(musicCenterControllerProvider).asData?.value;
    final matched =
        state?.tracks
            .where((track) => track.albumTitle == album.title)
            .toList(growable: false) ??
        const <MusicTrack>[];
    if (matched.isNotEmpty) {
      await controller.playItems(
        matched.map(MusicPlayableItem.local).toList(growable: false),
        source: MusicQueueSource(
          kind: MusicQueueSourceKind.album,
          id: album.id,
          title: album.title,
        ),
      );
      return;
    }
    onTap();
  }

  void _enqueueAlbum(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(musicCenterControllerProvider.notifier);
    final state = ref.read(musicCenterControllerProvider).asData?.value;
    final matched =
        state?.tracks
            .where((track) => track.albumTitle == album.title)
            .toList(growable: false) ??
        const <MusicTrack>[];
    if (matched.isNotEmpty) {
      controller.enqueueItems(
        matched.map(MusicPlayableItem.local),
        playNext: false,
      );
      showDesktopToast(context, l10n.musicAddToQueue, icon: DesktopIcons.queue);
      return;
    }
    onTap();
  }

  void _openContextMenu(BuildContext context, WidgetRef ref, Offset position) {
    final l10n = AppLocalizations.of(context);
    ref.read(desktopShellProvider.notifier).openMenu(position, [
      DesktopMenuItem(
        label: l10n.musicPlay,
        icon: DesktopIcons.play,
        onPressed: () => unawaited(_playAlbum(context, ref)),
      ),
      DesktopMenuItem(
        label: l10n.musicAddToQueue,
        icon: DesktopIcons.queue,
        onPressed: () => _enqueueAlbum(context, ref),
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        label: l10n.desktopOpenDetails,
        icon: DesktopIcons.info,
        onPressed: onTap,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final subtitle =
        album.trackCount > 0
            ? '${album.artistName} · ${l10n.musicDeckTrackCount(album.trackCount)}'
            : album.artistName;
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            key: ValueKey<String>('desktop-music-album-${album.id}'),
            onTap: onTap,
            onSecondaryTapDown:
                (details) =>
                    _openContextMenu(context, ref, details.globalPosition),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: DesktopMotion.springHover,
              curve: DesktopMotion.spring,
              transform: Matrix4.translationValues(0, hovered ? -4 : 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final discSize = constraints.maxWidth * 0.88;
                        final slideOffset =
                            hovered ? constraints.maxWidth * 0.16 : 0.0;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 悬停滑出黑胶盘。
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: AnimatedContainer(
                                    duration: DesktopMotion.of(
                                      context,
                                      const Duration(milliseconds: 320),
                                    ),
                                    curve: DesktopMotion.spring,
                                    transform: Matrix4.translationValues(
                                      slideOffset,
                                      0,
                                      0,
                                    ),
                                    child: AnimatedOpacity(
                                      duration: DesktopMotion.of(
                                        context,
                                        DesktopMotion.fast,
                                      ),
                                      opacity: hovered ? 1.0 : 0.0,
                                      alwaysIncludeSemantics: true,
                                      child: _AlbumSlideVinyl(
                                        size: discSize,
                                        accent: skin.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // 专辑封面主体。
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.6,
                                      ),
                                      blurRadius: 30,
                                      offset: const Offset(0, 14),
                                      spreadRadius: -12,
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: DesktopCover(
                                    url: album.listCoverUrl,
                                    kind: DesktopCoverKind.music,
                                    fallbackIcon: DesktopIcons.music,
                                    cacheKey: 'desktop-album-${album.id}',
                                    iconSize: 28,
                                  ),
                                ),
                              ),
                            ),
                            // 右下悬停播放钮。
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: AnimatedOpacity(
                                duration: DesktopMotion.of(
                                  context,
                                  const Duration(milliseconds: 220),
                                ),
                                opacity: hovered ? 1.0 : 0.0,
                                alwaysIncludeSemantics: true,
                                child: AnimatedScale(
                                  duration: DesktopMotion.of(
                                    context,
                                    const Duration(milliseconds: 260),
                                  ),
                                  curve: DesktopMotion.spring,
                                  scale: hovered ? 1.0 : 0.86,
                                  child: IgnorePointer(
                                    ignoring: !hovered,
                                    child: Tooltip(
                                      message: l10n.musicPlay,
                                      child: GestureDetector(
                                        onTap:
                                            () => unawaited(
                                              _playAlbum(context, ref),
                                            ),
                                        child: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: skin.accent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.45,
                                                ),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            DesktopIcons.play,
                                            size: 17,
                                            color: skin.accentInk,
                                          ),
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
                  const SizedBox(height: 10),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.bodyStrong(skin.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

/// 专辑卡悬停时从右侧滑出的装饰黑胶盘。
class _AlbumSlideVinyl extends StatelessWidget {
  const _AlbumSlideVinyl({required this.size, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFF18181A),
            Color(0xFF0A0A0B),
            Color(0xFF1A1B1E),
            Color(0xFF0B0B0C),
          ],
          stops: [0.0, 0.45, 0.72, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 16,
            offset: const Offset(4, 6),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.30,
          height: size * 0.30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.85),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Center(
            child: Container(
              width: size * 0.06,
              height: size * 0.06,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0A0A0B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _MusicTrackSort { title, artist, album, duration }

class _TracksView extends StatefulWidget {
  const _TracksView({
    required this.tracks,
    required this.search,
    required this.onPlay,
    required this.currentId,
    required this.playing,
    this.showControls = true,
  });

  final List<MusicTrack> tracks;
  final TextEditingController search;
  final ValueChanged<MusicTrack> onPlay;
  final String? currentId;
  final bool playing;
  final bool showControls;

  @override
  State<_TracksView> createState() => _TracksViewState();
}

class _TracksViewState extends State<_TracksView> {
  bool _favoritesOnly = false;
  _MusicTrackSort _sort = _MusicTrackSort.title;
  int _page = 0;
  int _pageSize = 20;

  List<MusicTrack> _filteredTracks() {
    final query = widget.search.text.trim().toLowerCase();
    final tracks =
        widget.tracks.where((track) {
          if (widget.showControls && _favoritesOnly && !track.favorite) {
            return false;
          }
          if (!widget.showControls || query.isEmpty) {
            return true;
          }
          return '${track.title} ${track.artistName} ${track.albumTitle}'
              .toLowerCase()
              .contains(query);
        }).toList();
    if (widget.showControls) {
      tracks.sort((a, b) {
        return switch (_sort) {
          _MusicTrackSort.title => a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          ),
          _MusicTrackSort.artist => a.artistName.toLowerCase().compareTo(
            b.artistName.toLowerCase(),
          ),
          _MusicTrackSort.album => a.albumTitle.toLowerCase().compareTo(
            b.albumTitle.toLowerCase(),
          ),
          _MusicTrackSort.duration => (a.durationSeconds ?? 0).compareTo(
            b.durationSeconds ?? 0,
          ),
        };
      });
    }
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final filtered = _filteredTracks();
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, totalPages - 1);
    final start = page * _pageSize;
    final visible =
        widget.showControls
            ? filtered.skip(start).take(_pageSize).toList(growable: false)
            : filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showControls)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 18,
              runSpacing: 12,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DesktopTextField(
                        key: const ValueKey<String>('desktop-music-search'),
                        controller: widget.search,
                        onChanged: (value) {
                          setState(() => _page = 0);
                        },
                        hint: l10n.desktopMusicSearchHint,
                        prefixIcon: DesktopIcons.search,
                        height: 36,
                      ),
                    ),
                    DesktopChipButton(
                      soft: true,
                      label: l10n.desktopFilterAll,
                      selected: !_favoritesOnly,
                      count: widget.tracks.length,
                      onTap:
                          () => setState(() {
                            _favoritesOnly = false;
                            _page = 0;
                          }),
                    ),
                    DesktopChipButton(
                      soft: true,
                      label: l10n.desktopPinnedFavorites,
                      selected: _favoritesOnly,
                      count:
                          widget.tracks.where((track) => track.favorite).length,
                      onTap:
                          () => setState(() {
                            _favoritesOnly = true;
                            _page = 0;
                          }),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.desktopReaderSortLabel,
                      style: DesktopType.caption(skin.text3),
                    ),
                    const SizedBox(width: 8),
                    DesktopSelect<_MusicTrackSort>(
                      value: _sort,
                      variant: DesktopSelectVariant.small,
                      width: 158,
                      options: [
                        DesktopSelectOption(
                          value: _MusicTrackSort.title,
                          label: l10n.desktopSortTitle,
                        ),
                        DesktopSelectOption(
                          value: _MusicTrackSort.artist,
                          label: l10n.musicFieldArtist,
                        ),
                        DesktopSelectOption(
                          value: _MusicTrackSort.album,
                          label: l10n.desktopColAlbum,
                        ),
                        DesktopSelectOption(
                          value: _MusicTrackSort.duration,
                          label: l10n.musicFieldDuration,
                        ),
                      ],
                      onChanged:
                          (value) => setState(() {
                            _sort = value;
                            _page = 0;
                          }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (visible.isEmpty)
          DesktopEmpty(
            message:
                widget.showControls
                    ? l10n.desktopMusicNoTracks
                    : l10n.musicNoFavoritesYet,
            icon:
                widget.showControls ? DesktopIcons.search : DesktopIcons.heart,
            description: widget.showControls ? null : l10n.musicNoFavoritesHint,
            actionLabel:
                widget.showControls &&
                        (widget.search.text.isNotEmpty || _favoritesOnly)
                    ? l10n.desktopReaderClearFilters
                    : null,
            onAction:
                widget.showControls &&
                        (widget.search.text.isNotEmpty || _favoritesOnly)
                    ? () {
                      widget.search.clear();
                      setState(() {
                        _favoritesOnly = false;
                        _page = 0;
                      });
                    }
                    : null,
            large: !widget.showControls,
          )
        else
          _TrackRows(
            tracks: visible,
            currentId: widget.currentId,
            playing: widget.playing,
            onPlay: widget.onPlay,
          ),
        if (widget.showControls)
          DesktopPager(
            page: page,
            totalItems: filtered.length,
            onPageChanged: (value) => setState(() => _page = value),
            pageSize: _pageSize,
            pageSizeOptions: const [20, 50, 100],
            onPageSizeChanged:
                (value) => setState(() {
                  _pageSize = value;
                  _page = 0;
                }),
          ),
      ],
    );
  }
}
