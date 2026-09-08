part of 'movie_management.dart';

class _MediaLibrarySourceWorkspace extends StatelessWidget {
  const _MediaLibrarySourceWorkspace({
    required this.source,
    required this.locations,
    required this.bounded,
    required this.scanning,
    required this.onEdit,
    required this.onScan,
    required this.onDelete,
  });

  final VideoLibrarySource source;
  final List<VideoStorageLocation> locations;
  final bool bounded;
  final bool scanning;
  final VoidCallback onEdit;
  final VoidCallback onScan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final duration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : const Duration(milliseconds: 180);
    final body = _MediaLibraryWorkspaceBody(
      source: source,
      locations: locations,
      bounded: bounded,
    );
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: Material(
        key: ValueKey(source.id),
        color: context.videoColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: context.videoColors.outlineVariant.withValues(alpha: 0.36),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MediaLibrarySourceHeader(
              source: source,
              locations: locations,
              scanning: scanning,
              onEdit: onEdit,
              onScan: onScan,
              onDelete: onDelete,
            ),
            Divider(
              height: 1,
              color: context.videoColors.outlineVariant.withValues(alpha: 0.28),
            ),
            if (bounded) Expanded(child: body) else body,
          ],
        ),
      ),
    );
  }
}

class _MediaLibrarySourceHeader extends StatelessWidget {
  const _MediaLibrarySourceHeader({
    required this.source,
    required this.locations,
    required this.scanning,
    required this.onEdit,
    required this.onScan,
    required this.onDelete,
  });

  final VideoLibrarySource source;
  final List<VideoStorageLocation> locations;
  final bool scanning;
  final VoidCallback onEdit;
  final VoidCallback onScan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = locations.cast<VideoStorageLocation?>().firstWhere(
      (item) => item?.id == source.storageLocationId,
      orElse: () => null,
    );
    final active =
        scanning ||
        const {'QUEUED', 'DISCOVERING', 'APPLYING'}.contains(source.scanStatus);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              source.name,
              style: TextStyle(
                color: context.videoColors.onSurface,
                fontSize: AppTypography.titleLarge,
                fontWeight: FontWeight.w800,
              ),
            ),
            _SourceStatusBadge(source: source),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${location?.name ?? l10n.videoUnknownStorageLocation} · ${source.relativeRoot}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.videoColors.onSurfaceVariant,
            fontSize: AppTypography.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _SourceMeta(
              icon: Icons.movie_filter_outlined,
              label: l10n.videoSourceScanSummary(
                source.lastScannedCount,
                source.lastCandidateCount,
              ),
            ),
            _SourceMeta(
              icon: Icons.group_outlined,
              label: _visibilityLabel(l10n, source.visibility),
            ),
            if (source.lastMissingCount > 0)
              _SourceMeta(
                icon: Icons.link_off_rounded,
                label: l10n.videoSourceMissingCount(source.lastMissingCount),
                issue: true,
              ),
          ],
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        IconButton(
          onPressed: scanning ? null : onDelete,
          tooltip: l10n.videoDeleteLibrarySource,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: Text(l10n.videoEditLibrarySource),
        ),
        FilledButton.icon(
          onPressed: source.enabled && !active ? onScan : null,
          icon:
              active
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.manage_search_rounded),
          label: Text(l10n.videoScanThisSource),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 14), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _MediaLibraryWorkspaceBody extends StatefulWidget {
  const _MediaLibraryWorkspaceBody({
    required this.source,
    required this.locations,
    required this.bounded,
  });

  final VideoLibrarySource source;
  final List<VideoStorageLocation> locations;
  final bool bounded;

  @override
  State<_MediaLibraryWorkspaceBody> createState() =>
      _MediaLibraryWorkspaceBodyState();
}

class _MediaLibraryWorkspaceBodyState
    extends State<_MediaLibraryWorkspaceBody> {
  int _section = 0;

  @override
  void didUpdateWidget(covariant _MediaLibraryWorkspaceBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id != widget.source.id) {
      _section = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selector = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment<int>(
            value: 0,
            icon: const Icon(Icons.info_outline_rounded),
            label: Text(l10n.videoLibraryOverviewTab),
          ),
          ButtonSegment<int>(
            value: 1,
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(l10n.videoLibraryScanReviewTab),
          ),
          ButtonSegment<int>(
            value: 2,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text(l10n.videoLibraryAccessTab),
          ),
        ],
        selected: {_section},
        onSelectionChanged: (value) => setState(() => _section = value.first),
      ),
    );
    final content = switch (_section) {
      0 => _MediaLibraryOverviewPanel(
        source: widget.source,
        locations: widget.locations,
      ),
      1 => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MediaLibraryReviewWorkspace(source: widget.source),
      ),
      _ => MediaLibraryAccessPanel(source: widget.source),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        selector,
        Divider(
          height: 1,
          color: context.videoColors.outlineVariant.withValues(alpha: 0.28),
        ),
        if (widget.bounded) Expanded(child: content) else content,
      ],
    );
  }
}

class _MediaLibraryOverviewPanel extends StatelessWidget {
  const _MediaLibraryOverviewPanel({
    required this.source,
    required this.locations,
  });

  final VideoLibrarySource source;
  final List<VideoStorageLocation> locations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = locations.cast<VideoStorageLocation?>().firstWhere(
      (item) => item?.id == source.storageLocationId,
      orElse: () => null,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _OverviewRow(
            icon: Icons.storage_outlined,
            label: l10n.videoLibrarySourceLocationLabel,
            value: location?.name ?? l10n.videoUnknownStorageLocation,
          ),
          _OverviewRow(
            icon: Icons.folder_outlined,
            label: l10n.videoLibrarySourcePathLabel,
            value: source.relativeRoot,
          ),
          _OverviewRow(
            icon: _libraryTypeIcon(source.libraryType),
            label: l10n.videoLibrarySourceTypeLabel,
            value: _libraryTypeLabel(l10n, source.libraryType),
          ),
          _OverviewRow(
            icon: Icons.group_outlined,
            label: l10n.videoLibrarySourceVisibilityLabel,
            value: _visibilityLabel(l10n, source.visibility),
          ),
          _OverviewRow(
            icon: Icons.analytics_outlined,
            label: l10n.videoLibraryScanReviewTab,
            value: l10n.videoSourceScanSummary(
              source.lastScannedCount,
              source.lastCandidateCount,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: context.videoColors.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: context.videoColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: context.videoColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceMeta extends StatelessWidget {
  const _SourceMeta({
    required this.icon,
    required this.label,
    this.issue = false,
  });

  final IconData icon;
  final String label;
  final bool issue;

  @override
  Widget build(BuildContext context) {
    final color =
        issue
            ? Theme.of(context).colorScheme.error
            : context.videoColors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: color, fontSize: AppTypography.labelSmall),
        ),
      ],
    );
  }
}

IconData _libraryTypeIcon(VideoLibraryType type) {
  return switch (type) {
    VideoLibraryType.movie => Icons.movie_outlined,
    VideoLibraryType.tvSeries => Icons.tv_outlined,
    VideoLibraryType.anime => Icons.animation_outlined,
    VideoLibraryType.root => Icons.account_tree_outlined,
  };
}

String _visibilityLabel(
  AppLocalizations l10n,
  MediaLibraryVisibility visibility,
) {
  return switch (visibility) {
    MediaLibraryVisibility.private => l10n.videoLibraryVisibilityPrivate,
    MediaLibraryVisibility.selectedUsers => l10n.videoLibraryVisibilitySelected,
    MediaLibraryVisibility.allMembers => l10n.videoLibraryVisibilityMembers,
  };
}

String _visibilityHint(
  AppLocalizations l10n,
  MediaLibraryVisibility visibility,
) {
  return switch (visibility) {
    MediaLibraryVisibility.private => l10n.videoLibraryVisibilityPrivateHint,
    MediaLibraryVisibility.selectedUsers =>
      l10n.videoLibraryVisibilitySelectedHint,
    MediaLibraryVisibility.allMembers => l10n.videoLibraryVisibilityMembersHint,
  };
}
