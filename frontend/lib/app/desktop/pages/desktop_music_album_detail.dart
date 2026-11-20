part of 'desktop_music_page.dart';

/// 专辑点入的集合页，和原型 `Music.tsx::collection` 共用相同的返回、封面、
/// 专辑信息、播放操作与曲目表结构。
class _AlbumDetail extends StatelessWidget {
  const _AlbumDetail({
    required this.album,
    required this.tracks,
    required this.currentId,
    required this.playing,
    required this.onBack,
    required this.onPlay,
    required this.onShuffle,
    required this.onAddToQueue,
    required this.onTrackPlay,
  });

  final MusicAlbum album;
  final List<MusicTrack> tracks;
  final String? currentId;
  final bool playing;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback onAddToQueue;
  final ValueChanged<MusicTrack> onTrackPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final runtime = tracks.fold<int>(
      0,
      (total, track) => total + (track.durationSeconds ?? 0),
    );
    return Column(
      key: ValueKey<String>('desktop-music-album-detail-${album.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopLink(
          label: l10n.musicNavAlbums,
          icon: DesktopIcons.left,
          onPressed: onBack,
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 190,
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                  child: DesktopCover(
                    url: album.listCoverUrl,
                    kind: DesktopCoverKind.music,
                    fallbackIcon: DesktopIcons.music,
                    cacheKey: 'desktop-album-detail-${album.id}',
                    iconSize: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopEyebrow(l10n.musicNavAlbums),
                    const SizedBox(height: 8),
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.displayXl(
                        skin.text,
                        MediaQuery.sizeOf(context).width,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${album.artistName} · ${l10n.musicDeckTrackCount(tracks.length)} · ${formatDesktopClock(Duration(seconds: runtime))}',
                      style: DesktopType.body(skin.text2),
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (tracks.isEmpty)
          DesktopEmpty(
            icon: DesktopIcons.music,
            message: l10n.musicAlbumNoTracks,
            large: true,
          )
        else
          _TrackRows(
            tracks: tracks,
            currentId: currentId,
            playing: playing,
            onPlay: onTrackPlay,
          ),
      ],
    );
  }
}
