part of 'desktop_now_playing_page.dart';

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.track,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.position,
    required this.positionStream,
    required this.playing,
    required this.hueColor,
    required this.tab,
    required this.onTab,
    required this.showTranslation,
    required this.onToggleTranslation,
    required this.onSeek,
    required this.queue,
    required this.currentKey,
    required this.onPickQueue,
    required this.onToggleFavorite,
    required this.onBrowseMusic,
    required this.onEdit,
  });

  final MusicTrack track;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final Duration position;
  final Stream<Duration> positionStream;
  final bool playing;
  final Color hueColor;
  final int tab;
  final ValueChanged<int> onTab;
  final bool showTranslation;
  final VoidCallback onToggleTranslation;
  final ValueChanged<Duration> onSeek;
  final List<MusicPlayableItem> queue;
  final String? currentKey;
  final ValueChanged<int> onPickQueue;
  final VoidCallback onToggleFavorite;
  final VoidCallback onBrowseMusic;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final skin = DesktopSkin.of(context);
    final style = ref.watch(desktopNpStyleProvider);
    final timedLyrics = track.lyricLines;
    final plainLyrics =
        timedLyrics.isEmpty
            ? _plainLyricLines(track.lyricsRaw)
            : const <String>[];
    final hasTranslation = timedLyrics.any((line) => line.hasTranslation);
    final activeColor = style.effectiveFillPaint(hueColor).primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.isEmpty ? l10n.musicNowPlayingEyebrow : artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.eyebrow(
                      Colors.white.withValues(alpha: 0.6),
                    ).copyWith(letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.displayXl(
                      Colors.white,
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (album.isNotEmpty) album,
                      formatDesktopClock(duration),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.medium(
                      Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: DesktopIconButton(
                key: const ValueKey('desktop-np-favorite'),
                icon:
                    track.favorite
                        ? DesktopIcons.heartFilled
                        : DesktopIcons.heart,
                size: 40,
                iconSize: 22,
                color:
                    track.favorite
                        ? skin.liked
                        : Colors.white.withValues(alpha: 0.78),
                tooltip: l10n.desktopFavorite,
                onPressed: onToggleFavorite,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            DesktopSeg<int>(
              options: const [0, 1, 2],
              value: tab,
              labelOf:
                  (value) => switch (value) {
                    0 => l10n.musicNowPlayingLyrics,
                    1 => l10n.musicQueueTitle,
                    _ => l10n.musicNowPlayingAbout,
                  },
              small: true,
              onChanged: onTab,
            ),
            if (tab == 0 && hasTranslation) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onToggleTranslation,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.fast),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        showTranslation
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          showTranslation
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    '译',
                    style: DesktopType.chip(
                      showTranslation
                          ? const Color(0xFF0A0C0E)
                          : Colors.white.withValues(alpha: 0.8),
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child:
              tab == 0
                  ? DesktopNowPlayingLyrics(
                    lines: timedLyrics,
                    plainLines: plainLyrics,
                    position: position,
                    positionStream: positionStream,
                    duration: duration,
                    playing: playing,
                    style: style,
                    hueColor: hueColor,
                    showTranslation: showTranslation,
                    onSeek: onSeek,
                    onEdit: onEdit,
                  )
                  : tab == 1
                  ? (queue.isEmpty
                      ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                DesktopIcons.queue,
                                size: 32,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.musicQueueEmpty,
                                textAlign: TextAlign.center,
                                style: DesktopType.medium(
                                  Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isZh
                                    ? '从曲库中选择曲目加入队列，编排接下来要听的歌。'
                                    : 'Add tracks from your library to line up what plays next.',
                                textAlign: TextAlign.center,
                                style: DesktopType.dense(
                                  Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              DesktopButton(
                                key: const ValueKey('desktop-np-queue-browse'),
                                label: isZh ? '浏览音乐' : 'Browse music',
                                icon: DesktopIcons.music,
                                variant: DesktopButtonVariant.glass,
                                foregroundOverride: Colors.white,
                                onPressed: onBrowseMusic,
                              ),
                            ],
                          ),
                        ),
                      )
                      : ListView.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final item = queue[index];
                          final active = item.playableKey == currentKey;
                          return GestureDetector(
                            onTap: () => onPickQueue(index),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    active
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  DesktopMetrics.radiusSmall,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    active
                                        ? DesktopIcons.play
                                        : DesktopIcons.music,
                                    size: 13,
                                    color:
                                        active
                                            ? skin.accent
                                            : Colors.white.withValues(
                                              alpha: 0.45,
                                            ),
                                  ),
                                  const SizedBox(width: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: DesktopImage(
                                        url: item.track.coverUrl,
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopType.dense(
                                            active
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                  alpha: 0.82,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          item.track.artistName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopType.nano(
                                            Colors.white.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _queueDuration(item.track.durationSeconds),
                                    style: DesktopType.numeric(
                                      Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ))
                  : _NowPlayingAbout(
                    playing: playing,
                    color: activeColor,
                    artist: artist,
                    album: album,
                    duration: duration,
                    format: format,
                    bitrate: bitrate,
                    sampleRate: sampleRate,
                    fileSize: fileSize,
                    onEdit: onEdit,
                  ),
        ),
      ],
    );
  }
}

class _NowPlayingAbout extends StatelessWidget {
  const _NowPlayingAbout({
    required this.playing,
    required this.color,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.onEdit,
  });

  final bool playing;
  final Color color;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <MapEntry<String, String>>[
      MapEntry(l10n.musicFieldArtist, artist),
      MapEntry(l10n.musicFieldAlbum, album),
      MapEntry(l10n.musicFieldDuration, formatDesktopClock(duration)),
      MapEntry(l10n.musicFieldFormat, format?.toUpperCase() ?? '—'),
      MapEntry(l10n.musicFieldBitrate, bitrate == null ? '—' : '$bitrate kbps'),
      MapEntry(
        l10n.musicFieldSampleRate,
        sampleRate == null
            ? '—'
            : '${(sampleRate! / 1000).toStringAsFixed(1)} kHz',
      ),
      MapEntry(
        l10n.musicFieldFileSize,
        fileSize == null ? '—' : formatFileSize(fileSize!),
      ),
    ];
    final skin = DesktopSkin.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.musicEditDetailsLyrics,
            icon: DesktopIcons.edit,
            variant: DesktopButtonVariant.glass,
            foregroundOverride: Colors.white,
            onPressed: onEdit,
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0)
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    rows[index].key,
                    style: DesktopType.caption(
                      Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 6,
                  child: Text(
                    rows[index].value.isEmpty ? '—' : rows[index].value,
                    textAlign: TextAlign.right,
                    style: DesktopType.dense(skin.onStage),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 90,
          child: Opacity(
            opacity: 0.85,
            child: DesktopVisualizer(
              playing: playing,
              color: color,
              bars: 64,
              seed: 5,
            ),
          ),
        ),
      ],
    );
  }
}
