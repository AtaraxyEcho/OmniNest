part of 'music_immersive_player.dart';

class _DigitalImmersiveTrackHeader extends StatelessWidget {
  const _DigitalImmersiveTrackHeader({
    required this.palette,
    required this.track,
    required this.scale,
  });

  final MusicImmersivePalette palette;
  final MusicTrack? track;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = track?.title ?? l10n.musicNotPlaying;
    final subtitle =
        track == null
            ? l10n.portalDockMusic
            : '${track!.artistName} / ${track!.albumTitle}';
    final titleSize = musicHeaderTitleSize(scale);
    final subtitleSize = musicHeaderSubtitleSize(scale);
    return Row(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 820 * scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    // 强制 strut 行高：否则字体自身行高会大于设定行高，行盒比
                    strutStyle: StrutStyle(
                      fontSize: titleSize,
                      height: kMusicHeaderTitleHeightRatio,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: titleSize,
                      height: kMusicHeaderTitleHeightRatio,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: kMusicHeaderTitleGap * scale),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    strutStyle: StrutStyle(
                      fontSize: subtitleSize,
                      height: kMusicHeaderSubtitleHeightRatio,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: subtitleSize,
                      height: kMusicHeaderSubtitleHeightRatio,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
