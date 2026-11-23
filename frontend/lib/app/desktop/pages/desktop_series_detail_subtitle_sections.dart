part of 'desktop_series_detail_page.dart';

class _SubtitlesTab extends ConsumerStatefulWidget {
  const _SubtitlesTab({required this.seriesId});

  final String seriesId;

  @override
  ConsumerState<_SubtitlesTab> createState() => _SubtitlesTabState();
}

class _SubtitlesTabState extends ConsumerState<_SubtitlesTab> {
  String? _selectedEpisodeId;
  bool _uploading = false;
  String? _deletingTrackId;

  Future<void> _pickAndUploadSubtitle(String videoItemId) async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePick.pickFiles(
      allowedExtensions: const ['srt', 'vtt'],
    );
    final file = picked.singleOrNull;
    if (file == null || !mounted) return;
    final length = await file.length();
    if (!mounted) return;
    if (length != null && length > maxLocalSubtitleBytes) {
      showDesktopToast(
        context,
        l10n.videoSubtitleFileTooLarge,
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
      return;
    }
    final bytes = await file.readBytes();
    if (!mounted || bytes.isEmpty) return;
    setState(() => _uploading = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .uploadSubtitle(
            videoItemId: videoItemId,
            fileName: file.name,
            bytes: bytes,
            mimeType: _subtitleMime(file.extension),
            language: 'und',
          );
      if (!mounted) return;
      ref.invalidate(movieSubtitlesProvider(videoItemId));
      showDesktopToast(
        context,
        l10n.videoSubtitleUploaded,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoUploadSubtitle, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteSubtitle(String videoItemId, SubtitleTrack track) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _deletingTrackId = track.id);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .deleteSubtitle(videoItemId: videoItemId, subtitleId: track.id);
      if (!mounted) return;
      ref.invalidate(movieSubtitlesProvider(videoItemId));
      showDesktopToast(
        context,
        l10n.videoSubtitleDeleted,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoDeleteSubtitleTooltip, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _deletingTrackId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final episodes = ref.watch(movieSeriesEpisodesProvider(widget.seriesId));
    return episodes.when(
      loading: () => const DesktopSkeletonRows(count: 4, avatar: false),
      error:
          (error, _) => Text(
            failureToast(l10n, l10n.desktopSeriesSubtitles, error),
            style: DesktopType.caption(DesktopSkin.of(context).bad),
          ),
      data: (items) {
        if (items.isEmpty) {
          return DesktopEmpty(
            icon: DesktopIcons.captions,
            message: l10n.desktopSeriesEpisodesEmpty,
            actionLabel: null,
          );
        }
        final ordered = [...items]..sort((a, b) {
          final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
          return season != 0
              ? season
              : (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
        });
        final selected =
            ordered.any((item) => item.id == _selectedEpisodeId)
                ? _selectedEpisodeId!
                : ordered.first.id;
        final subtitles = ref.watch(movieSubtitlesProvider(selected));
        return subtitles.when(
          loading: () => const DesktopSkeletonRows(count: 2, avatar: false),
          error:
              (error, _) => Text(
                failureToast(l10n, l10n.desktopSeriesSubtitles, error),
                style: DesktopType.caption(DesktopSkin.of(context).bad),
              ),
          data:
              (tracks) => DesktopSubtitlePanel(
                tracks: tracks,
                uploading: _uploading,
                deletingTrackId: _deletingTrackId,
                emptyMessage: l10n.desktopSeriesNoSubtitles,
                leading: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: DesktopSelect<String>(
                    options: [
                      for (final item in ordered)
                        DesktopSelectOption(
                          value: item.id,
                          label:
                              '${l10n.videoEpisodeShortLabel(item.seasonNumber ?? 0, item.episodeNumber ?? 0)} · ${item.title}',
                          hint:
                              item.available
                                  ? null
                                  : l10n.videoEpisodeSourceUnavailable,
                        ),
                    ],
                    value: selected,
                    onChanged: (id) => setState(() => _selectedEpisodeId = id),
                    variant: DesktopSelectVariant.field,
                    icon: DesktopIcons.film,
                  ),
                ),
                onUpload: () => unawaited(_pickAndUploadSubtitle(selected)),
                onDelete: (track) => _deleteSubtitle(selected, track),
              ),
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

String _subtitleMime(String? extension) => switch (extension?.toLowerCase()) {
  'vtt' => 'text/vtt',
  'srt' => 'application/x-subrip',
  _ => 'text/plain',
};

class _SeriesFileRow extends StatelessWidget {
  const _SeriesFileRow({
    required this.episode,
    required this.busy,
    required this.anyBusy,
    required this.isZh,
    required this.onProbe,
    required this.onExportNfo,
  });

  final MovieVideoItem episode;
  final bool busy;
  final bool anyBusy;
  final bool isZh;
  final VoidCallback onProbe;
  final VoidCallback onExportNfo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final meta = [
      if (episode.versionLabel?.isNotEmpty == true) episode.versionLabel!,
      if (episode.containerFormat?.isNotEmpty == true)
        episode.containerFormat!.toUpperCase(),
      if (episode.videoCodec?.isNotEmpty == true)
        episode.videoCodec!.toUpperCase(),
    ].join(' · ').ifEmpty(l10n.desktopSeriesFileDetailsUnavailable);

    return DesktopHover(
      cursor: SystemMouseCursors.basic,
      builder:
          (context, hovered) => AnimatedContainer(
            duration: DesktopMotion.of(
              context,
              const Duration(milliseconds: 140),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: hovered ? skin.raise : skin.panel,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: hovered ? skin.line2 : skin.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        episode.available
                            ? skin.raise2
                            : skin.bad.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    DesktopIcons.film,
                    size: 16,
                    color: episode.available ? skin.text2 : skin.bad,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.videoEpisodeShortLabel(
                              episode.seasonNumber ?? 0,
                              episode.episodeNumber ?? 0,
                            ),
                            style: DesktopType.mono(skin.text3),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              episode.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.rowTitle(skin.text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (episode.available ? skin.ok : skin.bad).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    episode.available
                        ? l10n.videoEpisodeAvailable
                        : l10n.videoEpisodeSourceUnavailable,
                    style: DesktopType.micro(
                      episode.available ? skin.ok : skin.bad,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  const SizedBox.square(
                    dimension: 24,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  DesktopIconButton(
                    icon: DesktopIcons.retry,
                    tooltip: l10n.desktopMoviesReprobe,
                    onPressed: anyBusy ? null : onProbe,
                  ),
                  DesktopIconButton(
                    icon: DesktopIcons.download,
                    tooltip: isZh ? '导出单集 NFO' : 'Export episode NFO',
                    onPressed: anyBusy ? null : onExportNfo,
                  ),
                ],
              ],
            ),
          ),
    );
  }
}
