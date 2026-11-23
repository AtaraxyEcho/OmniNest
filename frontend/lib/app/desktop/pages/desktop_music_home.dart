part of 'desktop_music_page.dart';

/// 音乐首页标签页内容：与页面状态分离，便于单独演进。
class _Home extends StatelessWidget {
  const _Home({
    required this.state,
    required this.playlists,
    required this.onlinePlaylists,
    required this.onlineTracks,
    required this.onlineLibrary,
    required this.currentId,
    required this.playing,
    required this.onSeeAlbums,
    required this.onOpenAlbum,
    required this.onPlayPlaylist,
    required this.onPlayOnlinePlaylist,
    required this.onPlayOnlineTracks,
    required this.onSeePlaylists,
    required this.onTogglePlayback,
    required this.onOpenQueue,
    required this.onPlayQueueItem,
  });

  final MusicCenterState? state;
  final List<MusicPlaylist> playlists;
  final List<OnlinePlaylist> onlinePlaylists;
  final List<OnlineTrack> onlineTracks;
  final MusicPlatformLibraryState onlineLibrary;
  final String? currentId;
  final bool playing;
  final VoidCallback onSeeAlbums;
  final ValueChanged<MusicAlbum> onOpenAlbum;
  final ValueChanged<MusicPlaylist> onPlayPlaylist;
  final ValueChanged<OnlinePlaylist> onPlayOnlinePlaylist;
  final ValueChanged<List<OnlineTrack>> onPlayOnlineTracks;
  final VoidCallback onSeePlaylists;
  final VoidCallback onTogglePlayback;
  final VoidCallback onOpenQueue;
  final ValueChanged<int> onPlayQueueItem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final albums =
        state?.albums.isNotEmpty == true
            ? state!.albums
            : (state?.dashboard.recentAlbums ?? const <MusicAlbum>[]);
    final album = albums.take(10).toList(growable: false);
    final onlineAlbums = _onlineAlbumGroups(onlineTracks);
    final localAlbumCount =
        (state?.dashboard.albumCount ?? 0) > 0
            ? state!.dashboard.albumCount
            : albums.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusHero(state: state, onTogglePlayback: onTogglePlayback),
        DesktopSection(
          eyebrow: l10n.desktopMusicLibraryEyebrow,
          title: l10n.musicNavAlbums,
          actionLabel: l10n.desktopSeeAllCount(
            localAlbumCount + onlineAlbums.length,
          ),
          onAction: onSeeAlbums,
          child: _AlbumRail(
            albums: album,
            onlineAlbums: onlineAlbums,
            currentId: currentId,
            playing: playing,
            onOpen: onOpenAlbum,
            onPlayOnline: onPlayOnlineTracks,
          ),
        ),
        DesktopSection(
          eyebrow: l10n.desktopMusicLibraryEyebrow,
          title: l10n.musicDeckPlaylists,
          actionLabel: l10n.desktopSeeAllCount(
            playlists.length + onlinePlaylists.length,
          ),
          onAction: onSeePlaylists,
          child: _PlaylistRail(
            playlists: playlists.take(8).toList(growable: false),
            onPlay: onPlayPlaylist,
            onlinePlaylists: onlinePlaylists,
            onlineLibrary: onlineLibrary,
            onPlayOnline: onPlayOnlinePlaylist,
          ),
        ),
        DesktopSection(
          title: l10n.desktopUpNext,
          actionLabel: l10n.desktopOpenQueue,
          onAction: onOpenQueue,
          child: _QueueRows(state: state, onPlayAt: onPlayQueueItem),
        ),
      ],
    );
  }
}
