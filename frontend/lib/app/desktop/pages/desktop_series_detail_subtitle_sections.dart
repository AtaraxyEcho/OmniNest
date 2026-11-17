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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
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
                DesktopButton(
                  label: l10n.videoDetailUploadSubtitle,
                  icon: DesktopIcons.upload,
                  variant: DesktopButtonVariant.soft,
                  busy: _uploading,
                  onPressed:
                      _uploading
                          ? null
                          : () => unawaited(_pickAndUploadSubtitle(selected)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _EpisodeSubtitles(
              videoItemId: selected,
              deletingTrackId: _deletingTrackId,
              onDelete: (track) => unawaited(_deleteSubtitle(selected, track)),
            ),
          ],
        );
      },
    );
  }
}

class _EpisodeSubtitles extends ConsumerWidget {
  const _EpisodeSubtitles({
    required this.videoItemId,
    required this.deletingTrackId,
    required this.onDelete,
  });

  final String videoItemId;
  final String? deletingTrackId;
  final ValueChanged<SubtitleTrack> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final subtitles = ref.watch(movieSubtitlesProvider(videoItemId));
    return subtitles.when(
      loading: () => const DesktopSkeletonRows(count: 2, avatar: false),
      error:
          (error, _) => Text(
            failureToast(l10n, l10n.desktopSeriesSubtitles, error),
            style: DesktopType.caption(skin.bad),
          ),
      data: (tracks) {
        if (tracks.isEmpty) {
          return DesktopEmpty(
            icon: DesktopIcons.captions,
            message: l10n.desktopSeriesNoSubtitles,
            actionLabel: null,
          );
        }
        return Column(
          children: [
            for (var index = 0; index < tracks.length; index++)
              _SubtitleTrackRow(
                track: tracks[index],
                index: index,
                count: tracks.length,
                deleting: deletingTrackId == tracks[index].id,
                anyDeleting: deletingTrackId != null,
                onDelete: () => onDelete(tracks[index]),
              ),
          ],
        );
      },
    );
  }
}

class _SubtitleTrackRow extends StatelessWidget {
  const _SubtitleTrackRow({
    required this.track,
    required this.index,
    required this.count,
    required this.deleting,
    required this.anyDeleting,
    required this.onDelete,
  });

  final SubtitleTrack track;
  final int index;
  final int count;
  final bool deleting;
  final bool anyDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: skin.panel,
        border: Border(
          top: BorderSide(color: skin.line),
          left: BorderSide(color: skin.line),
          right: BorderSide(color: skin.line),
          bottom:
              index == count - 1
                  ? BorderSide(color: skin.line)
                  : BorderSide.none,
        ),
        borderRadius: BorderRadius.vertical(
          top:
              index == 0
                  ? const Radius.circular(DesktopMetrics.radiusSmall)
                  : Radius.zero,
          bottom:
              index == count - 1
                  ? const Radius.circular(DesktopMetrics.radiusSmall)
                  : Radius.zero,
        ),
      ),
      child: Row(
        children: [
          Icon(DesktopIcons.captions, color: skin.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.label, style: DesktopType.rowTitle(skin.text)),
                Text(track.language, style: DesktopType.caption(skin.text3)),
              ],
            ),
          ),
          Text(
            track.embedded
                ? l10n.videoSubtitleEmbedded
                : l10n.videoSubtitleExternal,
            style: DesktopType.caption(skin.text3),
          ),
          if (!track.embedded) ...[
            const SizedBox(width: 8),
            if (deleting)
              const SizedBox(
                width: 36,
                height: 36,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              DesktopIconButton(
                icon: DesktopIcons.trash,
                tooltip: l10n.videoDeleteSubtitleTooltip,
                onPressed: anyDeleting ? null : onDelete,
              ),
          ],
        ],
      ),
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
