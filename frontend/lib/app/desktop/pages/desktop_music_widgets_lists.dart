part of 'desktop_music_page.dart';

class _AlbumRail extends StatelessWidget {
  const _AlbumRail({
    required this.albums,
    required this.onlineAlbums,
    required this.currentId,
    required this.playing,
    required this.onOpen,
    required this.onPlayOnline,
  });

  final List<MusicAlbum> albums;
  final List<List<OnlineTrack>> onlineAlbums;
  final String? currentId;
  final bool playing;
  final ValueChanged<MusicAlbum> onOpen;
  final ValueChanged<List<OnlineTrack>> onPlayOnline;

  @override
  Widget build(BuildContext context) {
    // 样例 `.album-row.big .album`：宽度 clamp(168px, 14vw, 210px)，gap 20。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.14).clamp(168.0, 210.0);
        return SizedBox(
          height: width + 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            itemCount: albums.length + onlineAlbums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder: (context, index) {
              if (index < albums.length) {
                final album = albums[index];
                return SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: index,
                    child: _AlbumCard(album: album, onTap: () => onOpen(album)),
                  ),
                );
              }
              final onlineAlbum = onlineAlbums[index - albums.length];
              return SizedBox(
                width: width,
                child: DesktopStagger(
                  index: index,
                  child: _DesktopOnlineAlbumCard(
                    tracks: onlineAlbum,
                    currentId: currentId,
                    playing: playing,
                    onPlay: () => onPlayOnline(onlineAlbum),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist, required this.onOpen});

  final MusicPlaylist playlist;
  final VoidCallback onOpen;

  List<String> _resolveCollageUrls(MusicCenterState? state) {
    final seen = <String>{};
    final urls = <String>[];
    void addIfValid(String? raw) {
      final trimmed = raw?.trim() ?? '';
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        urls.add(trimmed);
      }
    }

    if (state != null && state.selectedPlaylist?.id == playlist.id) {
      for (final track in state.selectedPlaylistTracks) {
        addIfValid(_firstMusicCover(track.listCoverUrl, track.coverUrl));
        if (urls.length >= 4) return urls;
      }
    }
    return urls;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final musicState = ref.watch(musicCenterControllerProvider).asData?.value;
    final covers = _resolveCollageUrls(musicState);
    final useCollage = covers.length >= 2;
    return DesktopHoverLift(
      onTap: onOpen,
      tooltip: l10n.musicOpenPlaylist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              // 样例歌单卡是 `.album`，没有 `.tilt`：只有封面静态描边 +
              // 14px 圆角，hover 只上移 4px。多图可用时渲染 2×2 四宫格拼贴封面。
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child:
                        useCollage
                            ? _PlaylistCollageCover(
                              playlistId: playlist.id,
                              urls: covers,
                            )
                            : DesktopCover(
                              url: playlist.listCoverUrl,
                              kind: DesktopCoverKind.music,
                              fallbackIcon: DesktopIcons.queue,
                              cacheKey: 'desktop-playlist-${playlist.id}',
                              iconSize: 28,
                            ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: skin.bg.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(color: skin.line2),
                  ),
                  child: Icon(DesktopIcons.play, size: 16, color: skin.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.bodyStrong(skin.text),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.musicDeckTrackCount(playlist.trackCount),
            style: DesktopType.caption(skin.text3),
          ),
        ],
      ),
    );
  }
}

/// 歌单 2×2 四宫格拼贴封面。
class _PlaylistCollageCover extends StatelessWidget {
  const _PlaylistCollageCover({required this.playlistId, required this.urls});

  final String playlistId;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    Widget tile(int index) {
      final url = urls[index % urls.length];
      return Expanded(
        child: DesktopCover(
          url: url,
          kind: DesktopCoverKind.music,
          fallbackIcon: DesktopIcons.music,
          cacheKey: 'desktop-playlist-$playlistId-q$index',
          fit: BoxFit.cover,
          iconSize: 16,
        ),
      );
    }

    return ColoredBox(
      color: skin.raise,
      child: Column(
        children: [
          Expanded(
            child: Row(children: [tile(0), const SizedBox(width: 1), tile(1)]),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Row(children: [tile(2), const SizedBox(width: 1), tile(3)]),
          ),
        ],
      ),
    );
  }
}

class _NewPlaylistCard extends StatelessWidget {
  const _NewPlaylistCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHoverLift(
      onTap: onCreate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
                border: Border.all(color: skin.line2),
              ),
              child: Center(
                child: Icon(DesktopIcons.plus, size: 28, color: skin.accent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.musicCreatePlaylist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.bodyStrong(skin.text),
          ),
        ],
      ),
    );
  }
}

class _PlaylistDetail extends StatelessWidget {
  const _PlaylistDetail({
    required this.playlist,
    required this.tracks,
    required this.loadingMore,
    required this.currentId,
    required this.playing,
    required this.onBack,
    required this.onPlay,
    required this.onShuffle,
    required this.onAddToQueue,
    required this.onEdit,
    required this.onDelete,
    required this.onTrackPlay,
  });

  final MusicPlaylist playlist;
  final List<MusicTrack> tracks;
  final bool loadingMore;
  final String? currentId;
  final bool playing;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback onAddToQueue;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<MusicTrack> onTrackPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.musicDeckPlaylists,
            icon: DesktopIcons.left,
            variant: DesktopButtonVariant.ghost,
            onPressed: onBack,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
                child: DesktopCover(
                  url: playlist.listCoverUrl,
                  kind: DesktopCoverKind.music,
                  fallbackIcon: DesktopIcons.queue,
                  cacheKey: 'desktop-playlist-detail-${playlist.id}',
                  iconSize: 36,
                ),
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopEyebrow(l10n.musicDeckPlaylists.toUpperCase()),
                  const SizedBox(height: 8),
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.displayXl(
                      skin.text,
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  if ((playlist.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      playlist.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.dense(skin.text2),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    l10n.musicDeckTrackCount(playlist.trackCount),
                    style: DesktopType.caption(skin.text3),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DesktopButton(
                        label: l10n.musicPlay,
                        icon: DesktopIcons.play,
                        variant: DesktopButtonVariant.primary,
                        large: true,
                        onPressed: tracks.isEmpty ? null : onPlay,
                      ),
                      DesktopButton(
                        label: l10n.musicShuffle,
                        icon: DesktopIcons.shuffle,
                        variant: DesktopButtonVariant.soft,
                        large: true,
                        onPressed: tracks.isEmpty ? null : onShuffle,
                      ),
                      DesktopButton(
                        label: l10n.musicAddToQueue,
                        icon: DesktopIcons.queue,
                        variant: DesktopButtonVariant.ghost,
                        large: true,
                        onPressed: tracks.isEmpty ? null : onAddToQueue,
                      ),
                      DesktopButton(
                        label: l10n.musicEditPlaylist,
                        icon: DesktopIcons.edit,
                        variant: DesktopButtonVariant.ghost,
                        large: true,
                        onPressed: onEdit,
                      ),
                      DesktopButton(
                        label: l10n.musicDeletePlaylist,
                        icon: DesktopIcons.trash,
                        variant: DesktopButtonVariant.ghost,
                        large: true,
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Center(
              child: Text(
                l10n.musicPlaylistEmptyHint,
                style: DesktopType.medium(skin.text3),
              ),
            ),
          )
        else
          _TrackRows(
            tracks: tracks,
            currentId: currentId,
            playing: playing,
            onPlay: onTrackPlay,
          ),
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaylistEditor extends StatefulWidget {
  const _PlaylistEditor({required this.playlist, required this.takenNames});

  final MusicPlaylist? playlist;
  final Set<String> takenNames;

  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.playlist?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.playlist?.description ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final name = _name.text.trim();
    final duplicate =
        name.isNotEmpty && widget.takenNames.contains(name.toLowerCase());
    final canSave = name.isNotEmpty && !duplicate;
    return DesktopDrawerFrame(
      eyebrow: l10n.musicDeckPlaylists,
      title:
          widget.playlist == null
              ? l10n.musicCreatePlaylist
              : l10n.musicEditPlaylist,
      footer: Wrap(
        spacing: 8,
        children: [
          DesktopButton(
            label: l10n.filesCancel,
            onPressed: () => closeDesktopModal(context),
          ),
          DesktopButton(
            label: widget.playlist == null ? l10n.musicCreate : l10n.musicSave,
            variant: DesktopButtonVariant.primary,
            onPressed:
                canSave
                    ? () => closeDesktopModal(context, (
                      name,
                      _description.text.trim(),
                    ))
                    : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopTextField(
            keyName: 'desktop-playlist-name',
            controller: _name,
            label: l10n.musicPlaylistName,
            hint: l10n.musicPlaylistName,
            required: true,
            maxLength: 48,
            autofocus: true,
            error: duplicate ? l10n.musicPlaylistNameDuplicate : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          DesktopTextField(
            keyName: 'desktop-playlist-description',
            controller: _description,
            label: l10n.musicPlaylistDescription,
            hint: l10n.musicPlaylistDescription,
            maxLength: 160,
            maxLines: 3,
            height: 96,
            onChanged: (_) => setState(() {}),
          ),
          if (duplicate) ...[
            const SizedBox(height: 8),
            Text(
              l10n.musicPlaylistNameDuplicate,
              style: DesktopType.caption(skin.bad),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.albums,
    required this.emptyLabel,
    required this.onOpen,
    this.onlineTracks = const <OnlineTrack>[],
    this.currentId,
    this.playing = false,
    this.onPlayOnline,
  });

  final List<MusicAlbum> albums;
  final String emptyLabel;
  final ValueChanged<MusicAlbum> onOpen;
  final List<OnlineTrack> onlineTracks;
  final String? currentId;
  final bool playing;
  final ValueChanged<List<OnlineTrack>>? onPlayOnline;

  @override
  Widget build(BuildContext context) {
    final onlineAlbums = _onlineAlbumGroups(onlineTracks);
    if (albums.isEmpty && onlineAlbums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Text(
            emptyLabel,
            style: DesktopType.medium(DesktopSkin.of(context).text3),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 200).floor().clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
        return Wrap(
          spacing: 18,
          runSpacing: 24,
          children: [
            for (var i = 0; i < albums.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _AlbumCard(
                    album: albums[i],
                    onTap: () => onOpen(albums[i]),
                  ),
                ),
              ),
            if (onPlayOnline != null)
              for (var i = 0; i < onlineAlbums.length; i++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: albums.length + i,
                    child: _DesktopOnlineAlbumCard(
                      tracks: onlineAlbums[i],
                      currentId: currentId,
                      playing: playing,
                      onPlay: () => onPlayOnline!(onlineAlbums[i]),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
