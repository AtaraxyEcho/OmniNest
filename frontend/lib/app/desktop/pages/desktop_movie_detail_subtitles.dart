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
    final l10n = AppLocalizations.of(context);
    final subtitles = ref.watch(movieSubtitlesProvider(widget.videoItemId));
    final tracks = subtitles.asData?.value ?? const <SubtitleTrack>[];
    if (subtitles.isLoading && tracks.isEmpty) {
      return const SizedBox(height: 40);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: DesktopEmpty(
              icon: DesktopIcons.captions,
              message: l10n.videoNoSubtitlesAvailable,
              actionLabel: null,
            ),
          )
        else
          for (var i = 0; i < tracks.length; i++)
            _SubtitleRow(
              track: tracks[i],
              first: i == 0,
              deleting: _deletingId == tracks[i].id,
              anyDeleting: _deletingId != null,
              onDelete: () => unawaited(_delete(tracks[i])),
            ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.videoDetailUploadSubtitle,
            icon: DesktopIcons.upload,
            variant: DesktopButtonVariant.soft,
            busy: _uploading,
            onPressed: _uploading ? null : () => unawaited(_pickAndUpload()),
          ),
        ),
      ],
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({
    required this.track,
    required this.first,
    required this.deleting,
    required this.anyDeleting,
    required this.onDelete,
  });

  final SubtitleTrack track;
  final bool first;
  final bool deleting;
  final bool anyDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line, width: first ? 0 : 1)),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
            child: Text(
              track.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopType.rowTitle(skin.text),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              [
                track.embedded
                    ? l10n.videoRedesignSubtitleEmbedded
                    : l10n.videoRedesignSubtitleExternal,
                track.kind,
              ].join(' · '),
              style: DesktopType.caption(skin.text3),
            ),
          ),
          Text(track.language, style: DesktopType.body(skin.text2)),
          if (!track.embedded) ...[
            const SizedBox(width: 12),
            if (deleting)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
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

String _subtitleMime(String? extension) => switch (extension?.toLowerCase()) {
  'vtt' => 'text/vtt',
  'srt' => 'application/x-subrip',
  _ => 'text/plain',
};
