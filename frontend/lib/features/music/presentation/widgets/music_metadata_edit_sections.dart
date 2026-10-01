part of 'music_metadata_edit_dialog.dart';

/// 元数据编辑弹窗的分区组件：封面面板、表单字段、歌词区与刮削候选
/// （自编辑弹窗主体拆出以控制单文件规模）。

class _CoverPanel extends StatefulWidget {
  const _CoverPanel({
    required this.track,
    required this.previewBytes,
    required this.pendingFileName,
    required this.clearCover,
    required this.onPickCover,
    required this.onRemoveCover,
  });

  final MusicTrack track;
  final List<int>? previewBytes;
  final String? pendingFileName;
  final bool clearCover;
  final VoidCallback onPickCover;
  final VoidCallback onRemoveCover;

  @override
  State<_CoverPanel> createState() => _CoverPanelState();
}

class _CoverPanelState extends State<_CoverPanel> {
  bool _hovering = false;

  bool get _hasPendingSelection => widget.previewBytes != null;

  bool get _hasCoverToClear =>
      _hasPendingSelection ||
      (!widget.clearCover && widget.track.coverUrl?.isNotEmpty == true);

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final showRemoteCover = widget.previewBytes == null && !widget.clearCover;
    return Column(
      children: [
        Semantics(
          button: true,
          label: l10n.musicCoverPick,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: InkWell(
              onTap: widget.onPickCover,
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox.square(
                        dimension: 220,
                        child:
                            widget.previewBytes != null
                                ? Image.memory(
                                  Uint8List.fromList(widget.previewBytes!),
                                  fit: BoxFit.cover,
                                )
                                : MusicDeckArtwork(
                                  title: widget.track.title,
                                  imageUrl:
                                      showRemoteCover
                                          ? widget.track.coverUrl
                                          : null,
                                  borderRadius: 12,
                                  icon: Icons.album_rounded,
                                ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _hovering ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: colors.overlay.withValues(alpha: 0.36),
                          ),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            color: scheme.onPrimary.withValues(alpha: 0.92),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          widget.pendingFileName ??
              (widget.clearCover ? l10n.musicCoverRemove : l10n.musicCoverPick),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (_hasCoverToClear) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.onRemoveCover,
            child: Text(
              _hasPendingSelection ? l10n.musicCancel : l10n.musicCoverRemove,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          widget.track.qualityText,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _FormFields extends StatelessWidget {
  const _FormFields({
    required this.titleController,
    required this.artistController,
    required this.albumController,
    required this.genreController,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;
  final TextEditingController albumController;
  final TextEditingController genreController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnderlineField(
          label: l10n.musicFieldTitle,
          controller: titleController,
          required: true,
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          label: l10n.musicFieldArtist,
          controller: artistController,
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          label: l10n.musicFieldAlbum,
          controller: albumController,
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          label: l10n.musicFieldGenre,
          controller: genreController,
        ),
      ],
    );
  }
}

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.label,
    required this.controller,
    this.required = false,
  });

  final String label;
  final TextEditingController controller;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.onSurface, height: 1.4),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 10, top: 4),
            border: _underline(colors.outline),
            enabledBorder: _underline(colors.outline),
            focusedBorder: _underline(colors.primary, width: 1.5),
            errorBorder: _underline(colors.danger),
            focusedErrorBorder: _underline(colors.danger, width: 1.5),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _underline(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _LyricsSection extends StatelessWidget {
  const _LyricsSection({
    required this.lyricsFileName,
    required this.existingLyrics,
    required this.pendingLyrics,
    required this.detailPending,
    required this.onPickLyrics,
    required this.onClearLyrics,
    required this.onSearchLyrics,
    required this.searchingLyrics,
  });

  final String? lyricsFileName;
  final String? existingLyrics;
  final String? pendingLyrics;
  final bool detailPending;
  final VoidCallback onPickLyrics;
  final VoidCallback onClearLyrics;
  final VoidCallback? onSearchLyrics;
  final bool searchingLyrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final previewSource = pendingLyrics ?? existingLyrics;
    final preview = previewSource?.trim() ?? '';
    final cleared = pendingLyrics == '';
    final status =
        cleared
            ? l10n.musicNoLyrics
            : pendingLyrics != null
            ? l10n.musicLyricsOnlineSource
            : preview.isNotEmpty
            ? l10n.musicLyricsExisting
            : l10n.musicNoLyrics;
    final canClear = !cleared && preview.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.musicLyricsFile,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onPickLyrics,
              icon: const Icon(Icons.lyrics_rounded, size: 18),
              label: Text(lyricsFileName ?? l10n.musicLyricsPick),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, AppControlTokens.buttonHeight),
                padding: AppControlTokens.buttonPadding,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onSearchLyrics,
              icon:
                  searchingLyrics
                      ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text(l10n.musicLyricsSearch),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, AppControlTokens.buttonHeight),
                padding: AppControlTokens.buttonPadding,
              ),
            ),
            if (canClear)
              TextButton(
                onPressed: onClearLyrics,
                child: Text(l10n.musicLyricsClear),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (detailPending && preview.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.fieldFill.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.fieldBorder),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    preview,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: AppTypography.monoFamily,
                      height: 1.55,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ScrapeCandidates extends StatelessWidget {
  const _ScrapeCandidates({
    required this.candidates,
    required this.applying,
    required this.onApply,
  });

  final List<MusicScrapeCandidate> candidates;
  final bool applying;
  final ValueChanged<MusicScrapeCandidate> onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.musicScrapeCandidatesTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Text(
            l10n.musicScrapeNoCandidates,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          )
        else
          for (final candidate in candidates)
            _ScrapeCandidateRow(
              candidate: candidate,
              applying: applying,
              onApply: () => onApply(candidate),
            ),
      ],
    );
  }
}

class _ScrapeCandidateRow extends StatelessWidget {
  const _ScrapeCandidateRow({
    required this.candidate,
    required this.applying,
    required this.onApply,
  });

  final MusicScrapeCandidate candidate;
  final bool applying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final chips = <String>[
      if (candidate.releaseDate != null)
        '${candidate.releaseDate!.year}-${candidate.releaseDate!.month.toString().padLeft(2, '0')}-${candidate.releaseDate!.day.toString().padLeft(2, '0')}',
      if (candidate.durationSeconds != null)
        _formatDuration(candidate.durationSeconds!),
      if (candidate.trackNumber != null) '#${candidate.trackNumber}',
      if (candidate.coverUrl != null) l10n.musicCoverImage,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: applying ? null : onApply,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${candidate.artistName} · ${candidate.albumTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final chip in chips)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.fieldFill,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colors.fieldBorder),
                                ),
                                child: Text(
                                  chip,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: applying ? null : onApply,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, AppControlTokens.buttonHeight),
                    padding: AppControlTokens.buttonPadding,
                  ),
                  child: Text(l10n.musicScrapeApply),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }
}
