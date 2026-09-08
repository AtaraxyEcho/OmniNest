part of 'movie_management.dart';

class VideoLibrarySourceDialog extends ConsumerStatefulWidget {
  const VideoLibrarySourceDialog({
    required this.locations,
    this.source,
    super.key,
  });

  final List<VideoStorageLocation> locations;
  final VideoLibrarySource? source;

  @override
  ConsumerState<VideoLibrarySourceDialog> createState() =>
      _VideoLibrarySourceDialogState();
}

class _VideoLibrarySourceDialogState
    extends ConsumerState<VideoLibrarySourceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late String _locationId;
  late VideoLibraryType _libraryType;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _nameController = TextEditingController(text: source?.name ?? '');
    _pathController = TextEditingController(text: source?.relativeRoot ?? '.');
    final firstAvailable =
        widget.locations.where((location) => location.available).firstOrNull;
    _locationId = source?.storageLocationId ?? (firstAvailable?.id ?? '');
    _libraryType = source?.libraryType ?? VideoLibraryType.movie;
    _enabled = source?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_locationId.isEmpty || widget.locations.isEmpty) {
      return AlertDialog(
        title: Text(l10n.videoNoAvailableStorageLocation),
        content: Text(l10n.videoNoAvailableStorageLocationHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.coreClose),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(
        widget.source == null
            ? l10n.videoAddLibrarySource
            : l10n.videoEditLibrarySource,
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.videoSourceName),
            ),
            const SizedBox(height: 14),
            AppDropdown<String>(
              value: _locationId,
              label: l10n.videoStorageLocation,
              items: [
                for (final location in widget.locations)
                  AppDropdownItem(
                    value: location.id,
                    label:
                        '${location.name} · ${_storageHealthLabel(l10n, location.healthStatus)}',
                    enabled: location.available,
                  ),
              ],
              onChanged:
                  widget.source == null
                      ? (value) {
                        if (value != null) {
                          setState(() {
                            _locationId = value;
                            _pathController.text = '.';
                          });
                        }
                      }
                      : null,
            ),
            const SizedBox(height: 14),
            AppDropdown<VideoLibraryType>(
              value: _libraryType,
              label: l10n.videoLibraryType,
              helperText: l10n.videoLibraryTypeHint,
              items: [
                for (final type in VideoLibraryType.values)
                  AppDropdownItem(
                    value: type,
                    label: _libraryTypeLabel(l10n, type),
                  ),
              ],
              onChanged:
                  widget.source == null
                      ? (value) {
                        if (value != null) {
                          setState(() => _libraryType = value);
                        }
                      }
                      : null,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: l10n.videoRelativeDirectory,
                      helperText: l10n.videoRelativeDirectoryHint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _browseDirectory,
                  tooltip: l10n.videoBrowseRelativeDirectory,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ],
            ),
            if (widget.source != null)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                title: Text(l10n.videoSourceEnabled),
                onChanged: (value) => setState(() => _enabled = value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.videoCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child:
              _saving
                  ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(l10n.coreSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final path = _pathController.text.trim();
    if (name.isEmpty || path.isEmpty) {
      showMovieFeedback(context, l10n.videoSourceRequiredFields, isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final actions = ref.read(videoLibrarySourceActionsProvider);
      if (widget.source == null) {
        await actions.create(
          name: name,
          storageLocationId: _locationId,
          relativeRoot: path,
          libraryType: _libraryType,
        );
      } else {
        await actions.update(
          source: widget.source!,
          name: name,
          relativeRoot: path,
          libraryType: _libraryType,
          enabled: _enabled,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _browseDirectory() async {
    final selected = await showDialog<String>(
      context: context,
      builder:
          (context) => _VideoStorageDirectoryDialog(
            locationId: _locationId,
            initialPath: _pathController.text,
          ),
    );
    if (!mounted || selected == null) {
      return;
    }
    _pathController.text = selected;
    if (_nameController.text.trim().isEmpty) {
      final location =
          widget.locations.where((item) => item.id == _locationId).firstOrNull;
      if (location == null) {
        return;
      }
      final name =
          selected == '.'
              ? (location.rootName.trim().isEmpty
                  ? location.name
                  : location.rootName)
              : selected.split('/').last;
      if (name.trim().isNotEmpty) {
        _nameController.text = name.trim();
      }
    }
  }
}

class _VideoStorageDirectoryDialog extends ConsumerStatefulWidget {
  const _VideoStorageDirectoryDialog({
    required this.locationId,
    required this.initialPath,
  });

  final String locationId;
  final String initialPath;

  @override
  ConsumerState<_VideoStorageDirectoryDialog> createState() =>
      _VideoStorageDirectoryDialogState();
}

class _VideoStorageDirectoryDialogState
    extends ConsumerState<_VideoStorageDirectoryDialog> {
  final List<String> _ancestors = [];
  late String _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = _normalizePath(widget.initialPath);
    var parent = _parentPath(_currentPath);
    while (parent != null) {
      _ancestors.insert(0, parent);
      parent = _parentPath(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final directories = ref.watch(
      videoStorageDirectoriesProvider((
        locationId: widget.locationId,
        parent: _currentPath == '.' ? null : _currentPath,
      )),
    );
    return AlertDialog(
      title: Text(l10n.videoBrowseRelativeDirectory),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed:
                      _currentPath == '.'
                          ? null
                          : () {
                            setState(() {
                              _currentPath = _parentPath(_currentPath) ?? '.';
                              if (_ancestors.isNotEmpty) {
                                _ancestors.removeLast();
                              }
                            });
                          },
                  tooltip: l10n.videoBackToParentNode,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    _currentPath == '.'
                        ? l10n.videoDirectoryRoot
                        : _currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: directories.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => MovieNoticePanel(
                      icon: Icons.error_outline_rounded,
                      title: l10n.videoStorageLocationUnavailable,
                      message: movieErrorMessage(error),
                    ),
                data:
                    (page) => ListView.builder(
                      itemCount: page.items.length,
                      itemBuilder: (context, index) {
                        final directory = page.items[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(directory.name),
                          trailing:
                              directory.hasChildren
                                  ? const Icon(Icons.chevron_right_rounded)
                                  : null,
                          onTap: () {
                            setState(() {
                              if (_currentPath != '.') {
                                _ancestors.add(_currentPath);
                              }
                              _currentPath = directory.relativePath;
                            });
                          },
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.videoCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentPath),
          child: Text(l10n.videoChooseThisDirectory),
        ),
      ],
    );
  }

  String _normalizePath(String value) {
    final trimmed = value.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty || trimmed == '.') return '.';
    final segments = trimmed.split('/')
      ..removeWhere((segment) => segment.isEmpty || segment == '.');
    return segments.isEmpty ? '.' : segments.join('/');
  }

  String? _parentPath(String value) {
    if (value == '.') return null;
    final separator = value.lastIndexOf('/');
    return separator < 0 ? '.' : value.substring(0, separator);
  }
}

String _libraryTypeLabel(AppLocalizations l10n, VideoLibraryType libraryType) {
  return switch (libraryType) {
    VideoLibraryType.movie => l10n.videoLibraryTypeMovie,
    VideoLibraryType.tvSeries => l10n.videoLibraryTypeTvSeries,
    VideoLibraryType.anime => l10n.videoLibraryTypeAnime,
    VideoLibraryType.root => l10n.videoLibraryTypeRoot,
  };
}

String _storageHealthLabel(AppLocalizations l10n, String healthStatus) =>
    healthStatusLabel(l10n, healthStatus);

String _sourceStatusLabel(AppLocalizations l10n, String status) =>
    scanStatusLabel(l10n, status);

class _CandidateStatusBadge extends StatelessWidget {
  const _CandidateStatusBadge({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (status) {
      'EXISTING' => l10n.videoCandidateExisting,
      'CHANGED' => l10n.videoCandidateChanged,
      'UNMATCHED' || 'AMBIGUOUS' => l10n.videoCandidateUnmatched,
      _ => l10n.videoCandidateNew,
    };
    final colorScheme = Theme.of(context).colorScheme;
    final issue = status == 'UNMATCHED' || status == 'AMBIGUOUS';
    final changed = status == 'CHANGED';
    final existing = status == 'EXISTING';
    final background =
        issue
            ? colorScheme.errorContainer
            : changed
            ? colorScheme.tertiaryContainer
            : existing
            ? colorScheme.secondaryContainer
            : colorScheme.primaryContainer;
    final foreground =
        issue
            ? colorScheme.onErrorContainer
            : changed
            ? colorScheme.onTertiaryContainer
            : existing
            ? colorScheme.onSecondaryContainer
            : colorScheme.onPrimaryContainer;
    final icon =
        issue
            ? Icons.help_outline_rounded
            : changed
            ? Icons.change_circle_outlined
            : existing
            ? Icons.library_add_check_outlined
            : Icons.fiber_new_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaLibraryTaskProgress extends StatelessWidget {
  const _MediaLibraryTaskProgress({
    required this.run,
    required this.mutating,
    required this.onPause,
    required this.onCancel,
  });

  final MediaScanRun run;
  final bool mutating;
  final VoidCallback? onPause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.videoColors.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: context.videoColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sourceStatusLabel(l10n, run.status),
                      style: TextStyle(
                        color: context.videoColors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.videoDiscoveryRunning,
                      style: TextStyle(
                        color: context.videoColors.onSurfaceVariant,
                        fontSize: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            minHeight: 5,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _ReviewMetric(
                icon: Icons.manage_search_outlined,
                label: l10n.videoDiscoveryCandidates(run.discoveredCount),
              ),
              if (run.appliedCount > 0)
                _ReviewMetric(
                  icon: Icons.library_add_check_outlined,
                  label: l10n.videoDiscoverySelected(run.appliedCount),
                  emphasized: true,
                ),
              if (run.failedCount > 0)
                _ReviewMetric(
                  icon: Icons.error_outline_rounded,
                  label: l10n.videoDiscoveryIssues(run.failedCount),
                  issue: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onPause != null)
                OutlinedButton.icon(
                  onPressed: mutating ? null : onPause,
                  icon: const Icon(Icons.pause_rounded),
                  label: Text(l10n.videoPauseImport),
                ),
              TextButton.icon(
                onPressed: mutating ? null : onCancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.videoCancelDiscovery),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaLibraryLoadingSkeleton extends StatelessWidget {
  const _MediaLibraryLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget bar(double width, double height) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.videoColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return Semantics(
      label: l10n.videoLibraryLoading,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.videoColors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(180, 18),
            const SizedBox(height: 12),
            bar(double.infinity, 52),
            const SizedBox(height: 8),
            bar(double.infinity, 52),
            const SizedBox(height: 8),
            bar(double.infinity, 52),
          ],
        ),
      ),
    );
  }
}

IconData _mediaTreeNodeIcon(String nodeType) {
  return switch (nodeType) {
    'MOVIE' => Icons.movie_outlined,
    'SERIES' => Icons.video_collection_outlined,
    'SEASON' => Icons.folder_copy_outlined,
    'EPISODE' => Icons.playlist_play_rounded,
    'DIRECTORY' => Icons.folder_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _UnavailableLocalMediaPanel extends ConsumerWidget {
  const _UnavailableLocalMediaPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unavailable = ref.watch(unavailableLocalMediaProvider);
    final count = unavailable.asData?.value.totalElements;
    return Material(
      color: context.videoColors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('mediaLibraryUnavailablePanel'),
          leading: Icon(
            count == null || count == 0
                ? Icons.verified_outlined
                : Icons.link_off_rounded,
            color:
                count == null || count == 0
                    ? context.videoColors.primary
                    : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            l10n.videoUnavailableTitle,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            count == null || count == 0
                ? l10n.videoUnavailableEmpty
                : l10n.videoUnavailableCount(count),
          ),
          children: [
            unavailable.when(
              loading: () => const LinearProgressIndicator(),
              error:
                  (error, _) => ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(l10n.videoUnavailableLoadFailed),
                    subtitle: Text(movieErrorMessage(error)),
                  ),
              data:
                  (page) =>
                      page.items.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: page.items.length,
                            separatorBuilder:
                                (_, _) => Divider(
                                  height: 1,
                                  indent: 56,
                                  color: context.videoColors.outlineVariant
                                      .withValues(alpha: 0.22),
                                ),
                            itemBuilder: (context, index) {
                              final item = page.items[index];
                              final pending =
                                  item.availabilityStatus == 'MISSING_PENDING';
                              return ListTile(
                                leading: Icon(
                                  pending
                                      ? Icons.schedule_rounded
                                      : Icons.broken_image_outlined,
                                  color:
                                      pending
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.tertiary
                                          : Theme.of(context).colorScheme.error,
                                ),
                                title: Text(item.title),
                                subtitle: Text(
                                  pending
                                      ? l10n.videoMissingPending
                                      : l10n.videoMissingConfirmed,
                                ),
                              );
                            },
                          ),
            ),
          ],
        ),
      ),
    );
  }
}
