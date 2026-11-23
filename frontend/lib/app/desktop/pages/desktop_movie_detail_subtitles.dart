part of 'desktop_movie_detail_page.dart';

class _Subtitles extends ConsumerStatefulWidget {
  const _Subtitles({required this.videoItemId});

  final String videoItemId;

  @override
  ConsumerState<_Subtitles> createState() => _SubtitlesState();
}

class _SubtitlesState extends ConsumerState<_Subtitles> {
  bool _uploading = false;
  String? _deletingId;

  Future<void> _pickAndUpload() async {
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
            videoItemId: widget.videoItemId,
            fileName: file.name,
            bytes: bytes,
            mimeType: _subtitleMime(file.extension),
            language: 'und',
          );
      if (!mounted) return;
      ref.invalidate(movieSubtitlesProvider(widget.videoItemId));
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

  Future<void> _delete(SubtitleTrack track) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _deletingId = track.id);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .deleteSubtitle(
            videoItemId: widget.videoItemId,
            subtitleId: track.id,
          );
      if (!mounted) return;
      ref.invalidate(movieSubtitlesProvider(widget.videoItemId));
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
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitles = ref.watch(movieSubtitlesProvider(widget.videoItemId));
    final tracks = subtitles.asData?.value ?? const <SubtitleTrack>[];
    if (subtitles.isLoading && tracks.isEmpty) {
      return const DesktopSkeletonRows(count: 2, avatar: false);
    }
    return DesktopSubtitlePanel(
      tracks: tracks,
      uploading: _uploading,
      deletingTrackId: _deletingId,
      onUpload: () => unawaited(_pickAndUpload()),
      onDelete: _delete,
    );
  }
}

String _subtitleMime(String? extension) => switch (extension?.toLowerCase()) {
  'vtt' => 'text/vtt',
  'srt' => 'application/x-subrip',
  _ => 'text/plain',
};
