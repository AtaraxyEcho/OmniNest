part of 'desktop_music_page.dart';

const int _desktopOnlinePlaylistLimit = 12;
const int _desktopOnlineAlbumLimit = 12;
const int _desktopOnlineTrackViewportRows = 10;
const double _desktopOnlineTrackRowHeight = 56;

List<OnlineTrack> _knownPlatformTracks(MusicPlatformLibraryState library) {
  final seen = <String>{};
  final tracks = <OnlineTrack>[];
  for (final track in library.likedTracks) {
    if (seen.add('${track.platform}:${track.songId}')) tracks.add(track);
  }
  return List<OnlineTrack>.unmodifiable(tracks);
}

List<String> _likedPlatformApis(MusicPlatformLibraryState library) {
  return library.connectedStatuses
      .where((status) => status.capabilities.likedTracks)
      .map((status) => status.platform)
      .toList(growable: false);
}

/// 桌面端旧页面的本地曲库区域继续复用原有组件，平台内容在这里以独立区块呈现。
/// 这样不会把平台曲目伪装成本地文件，也不会把平台歌单 ID 送进本地接口。
class _DesktopOnlinePlaylistSection extends StatelessWidget {
  const _DesktopOnlinePlaylistSection({
    required this.library,
    required this.playlists,
    required this.onOpen,
  });

  final MusicPlatformLibraryState library;
  final List<OnlinePlaylist> playlists;
  final ValueChanged<OnlinePlaylist> onOpen;

  String _platformLabel(OnlinePlaylist playlist) {
    for (final status in library.statuses) {
      if (status.platform == playlist.platform) return status.displayName;
    }
    return playlist.platform;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visiblePlaylists = playlists
        .take(_desktopOnlinePlaylistLimit)
        .toList(growable: false);
    return DesktopSection(
      eyebrow: visiblePlaylists.map(_platformLabel).toSet().join(' · '),
      title: l10n.musicNavPlaylists,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 208).floor().clamp(2, 8);
          final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
          return Wrap(
            spacing: 18,
            runSpacing: 24,
            children: [
              for (var index = 0; index < visiblePlaylists.length; index++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: index,
                    child: _DesktopOnlinePlaylistCard(
                      playlist: visiblePlaylists[index],
                      coverUrl: library.coverUrlForPlaylist(
                        visiblePlaylists[index],
                      ),
                      onOpen: () => onOpen(visiblePlaylists[index]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DesktopOnlinePlaylistCard extends StatelessWidget {
  const _DesktopOnlinePlaylistCard({
    required this.playlist,
    required this.coverUrl,
    required this.onOpen,
  });

  final OnlinePlaylist playlist;
  final String coverUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHoverLift(
      onTap: onOpen,
      tooltip: l10n.musicOpenPlaylist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
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
                    child: DesktopCover(
                      url: coverUrl,
                      kind: DesktopCoverKind.music,
                      fallbackIcon: DesktopIcons.queue,
                      cacheKey:
                          'desktop-online-playlist-${playlist.platform}-${playlist.playlistId}',
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
            l10n.musicDeckTrackCount(playlist.trackCount ?? 0),
            style: DesktopType.caption(skin.text3),
          ),
        ],
      ),
    );
  }
}

class _DesktopOnlineTrackSection extends StatelessWidget {
  const _DesktopOnlineTrackSection({
    required this.tracks,
    required this.currentId,
    required this.playing,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onPlay,
  });

  final List<OnlineTrack> tracks;
  final String? currentId;
  final bool playing;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<OnlineTrack> onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rowCount =
        (tracks.length + (hasMore ? 1 : 0))
            .clamp(1, _desktopOnlineTrackViewportRows)
            .toInt();
    return DesktopSection(
      eyebrow: l10n.musicDeckSourceNetease,
      title: l10n.musicNavFavorites,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DesktopOnlineTrackHead(),
          SizedBox(
            height: rowCount * _desktopOnlineTrackRowHeight,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 180 &&
                    hasMore &&
                    !loadingMore) {
                  onLoadMore();
                }
                return false;
              },
              child: ListView.builder(
                itemExtent: _desktopOnlineTrackRowHeight,
                itemCount: tracks.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= tracks.length) {
                    return Center(
                      child:
                          loadingMore
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const SizedBox.shrink(),
                    );
                  }
                  final track = tracks[index];
                  return _DesktopOnlineTrackRow(
                    index: index,
                    track: track,
                    current: _onlineTrackKey(track) == currentId,
                    playing: playing,
                    onPlay: () => onPlay(track),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: DesktopSkin.of(context).line),
        ],
      ),
    );
  }
}

class _DesktopOnlineAlbumSection extends StatelessWidget {
  const _DesktopOnlineAlbumSection({
    required this.tracks,
    required this.currentId,
    required this.playing,
    required this.onPlay,
  });

  final List<OnlineTrack> tracks;
  final String? currentId;
  final bool playing;
  final ValueChanged<List<OnlineTrack>> onPlay;

  Map<String, List<OnlineTrack>> _groups() {
    final groups = <String, List<OnlineTrack>>{};
    for (final track in tracks) {
      final album = track.albumTitle.trim();
      if (album.isEmpty) continue;
      final key = '$album\u0000${track.artistName}';
      groups.putIfAbsent(key, () => <OnlineTrack>[]).add(track);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _groups().values
        .take(_desktopOnlineAlbumLimit)
        .toList(growable: false);
    if (groups.isEmpty) return const SizedBox.shrink();
    return DesktopSection(
      eyebrow: l10n.musicDeckSourceNetease,
      title: l10n.musicNavAlbums,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 208).floor().clamp(2, 8);
          final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
          return Wrap(
            spacing: 18,
            runSpacing: 24,
            children: [
              for (var index = 0; index < groups.length; index++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: index,
                    child: _DesktopOnlineAlbumCard(
                      tracks: groups[index],
                      currentId: currentId,
                      playing: playing,
                      onPlay: () => onPlay(groups[index]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DesktopOnlineAlbumCard extends StatelessWidget {
  const _DesktopOnlineAlbumCard({
    required this.tracks,
    required this.currentId,
    required this.playing,
    required this.onPlay,
  });

  final List<OnlineTrack> tracks;
  final String? currentId;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final first = tracks.first;
    final current = tracks.any((track) => _onlineTrackKey(track) == currentId);
    return DesktopHoverLift(
      onTap: onPlay,
      tooltip: AppLocalizations.of(context).desktopPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DesktopCover(
                    url: first.listCoverUrl,
                    kind: DesktopCoverKind.music,
                    fallbackIcon: DesktopIcons.music,
                    cacheKey:
                        'desktop-online-album-${first.platform}-${first.albumTitle}-${first.artistName}',
                    iconSize: 28,
                  ),
                ),
              ),
              if (current && playing)
                Positioned.fill(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: skin.bg.withValues(alpha: 0.72),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          DesktopIcons.play,
                          size: 18,
                          color: skin.accent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            first.albumTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.bodyStrong(skin.text),
          ),
          const SizedBox(height: 2),
          Text(
            '${first.artistName} · ${tracks.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.caption(skin.text3),
          ),
        ],
      ),
    );
  }
}

class _DesktopOnlineTrackHead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final style = DesktopType.tableHead(skin.text3);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text('#', style: style)),
          Expanded(flex: 3, child: Text(l10n.desktopColTitle, style: style)),
          Expanded(flex: 2, child: Text(l10n.musicFieldArtist, style: style)),
          SizedBox(
            width: 70,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(DesktopIcons.clock, size: 13, color: skin.text3),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _DesktopOnlineTrackRow extends StatelessWidget {
  const _DesktopOnlineTrackRow({
    required this.index,
    required this.track,
    required this.current,
    required this.playing,
    required this.onPlay,
  });

  final int index;
  final OnlineTrack track;
  final bool current;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final duration = track.durationText.isEmpty ? '—' : track.durationText;
    return DesktopHoverLift(
      onTap: onPlay,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: current ? skin.accentWash(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Center(
                child: Text(
                  current && playing ? '▶' : '${index + 1}',
                  style: DesktopType.caption(
                    current ? skin.accent : skin.text3,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: DesktopCover(
                        url: track.listCoverUrl,
                        kind: DesktopCoverKind.music,
                        fallbackIcon: DesktopIcons.music,
                        cacheKey:
                            'desktop-online-track-${track.platform}-${track.songId}',
                        iconSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.bodyStrong(skin.text),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                track.artistName.isEmpty ? '—' : track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.body(skin.text2),
              ),
            ),
            SizedBox(
              width: 70,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(duration, style: DesktopType.caption(skin.text3)),
              ),
            ),
            SizedBox(
              width: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(DesktopIcons.play, size: 16, color: skin.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _onlineTrackKey(OnlineTrack track) {
  return 'online:${track.platform.trim().toLowerCase()}:${track.songId}';
}

extension on _DesktopMusicPageState {
  Future<void> _playAlbumTracks(
    List<MusicTrack> tracks, {
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final ordered = tracks.toList(growable: true);
    if (shuffle) ordered.shuffle();
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .playItems(ordered.map(MusicPlayableItem.local).toList());
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.musicPlay, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  /// 在线歌单卡片先加载首屏，再交给统一播放队列补齐整张歌单。
  ///
  /// 桌面端旧页面只认识本地 [MusicPlaylist]，这里显式走平台歌单命令，
  /// 避免把平台歌单 ID 误传给本地曲库接口。
  Future<void> _playOnlinePlaylist(OnlinePlaylist playlist) async {
    final l10n = AppLocalizations.of(context);
    try {
      final tracks = await ref
          .read(musicPlatformLibraryProvider.notifier)
          .loadPlaylistTracks(playlist);
      if (!mounted || tracks.isEmpty) return;
      await ref
          .read(musicCenterControllerProvider.notifier)
          .playPlatformPlaylist(
            playlist,
            startItem: MusicPlayableItem.online(tracks.first),
          );
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.musicPlay, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  Future<void> _playOnlineTracks(List<OnlineTrack> tracks) async {
    if (tracks.isEmpty) return;
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .playItems(tracks.map(MusicPlayableItem.online).toList());
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showDesktopToast(
        context,
        failureToast(l10n, l10n.musicPlay, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  void _enqueueAlbumTracks(List<MusicTrack> tracks) {
    final controller = ref.read(musicCenterControllerProvider.notifier);
    for (final track in tracks) {
      controller.enqueue(MusicPlayableItem.local(track));
    }
    if (tracks.isNotEmpty) {
      showDesktopToast(
        context,
        AppLocalizations.of(context).musicPlayNextAdded,
        icon: DesktopIcons.queue,
      );
    }
  }
}
