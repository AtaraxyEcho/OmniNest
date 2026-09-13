part of 'movie_management.dart';

/// 挂载直达模式所需的权限集合：媒体库管理 + 系统配置读/管。
/// 挂载列表端点是只读门控，权限独立授予，三项必须齐全。
const _mountDirectPermissions = [
  'media:library:manage',
  'system:config:read',
  'system:config:manage',
];

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
  String? _mountKey;
  bool _mountMode = true;
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

  bool _hasMountDirectPermission() {
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>[];
    return _mountDirectPermissions.every(permissions.contains);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 编辑态固定走位置模式；创建态在持有挂载直达权限时默认进入挂载模式。
    final mountAllowed = widget.source == null && _hasMountDirectPermission();
    final effectiveMountMode = mountAllowed && _mountMode;
    if (!effectiveMountMode &&
        (_locationId.isEmpty || widget.locations.isEmpty)) {
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
    final mountsAsync = ref.watch(videoTrustedMountsProvider);
    final mounts = mountsAsync.asData?.value ?? const <VideoTrustedMount>[];
    final availableMounts = mounts.where((mount) => mount.available).toList();
    final effectiveMountKey =
        _mountKey ?? availableMounts.firstOrNull?.mountKey;
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
            if (mountAllowed) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.videoSourceFromMount),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.videoStorageLocation),
                  ),
                ],
                selected: {_mountMode},
                onSelectionChanged: (selection) {
                  setState(() => _mountMode = selection.first);
                },
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.videoSourceName),
            ),
            const SizedBox(height: 14),
            if (effectiveMountMode)
              AppDropdown<String>(
                value: effectiveMountKey ?? '',
                label: l10n.videoTrustedMountLabel,
                items: [
                  for (final mount in mounts)
                    AppDropdownItem(
                      value: mount.mountKey,
                      label: mount.displayName,
                      enabled: mount.available,
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _mountKey = value;
                      _pathController.text = '.';
                    });
                  }
                },
              )
            else
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
                      helperText:
                          effectiveMountMode
                              ? l10n.videoNoTrustedMountHint
                              : l10n.videoRelativeDirectoryHint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed:
                      effectiveMountMode && effectiveMountKey == null
                          ? null
                          : _browseDirectory,
                  tooltip: l10n.videoBrowseRelativeDirectory,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ],
            ),
            if (effectiveMountMode && effectiveMountKey == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.videoNoTrustedMount,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
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
          onPressed:
              _saving || (effectiveMountMode && effectiveMountKey == null)
                  ? null
                  : _save,
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
    final mountAllowed = widget.source == null && _hasMountDirectPermission();
    final mountMode = mountAllowed && _mountMode;
    final mountsAsync = ref.read(videoTrustedMountsProvider);
    final mounts = mountsAsync.asData?.value ?? const <VideoTrustedMount>[];
    final mountKey =
        _mountKey ??
        mounts.where((mount) => mount.available).firstOrNull?.mountKey;
    if (mountMode && mountKey == null) {
      showMovieFeedback(context, l10n.videoNoTrustedMount, isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final actions = ref.read(videoLibrarySourceActionsProvider);
      if (mountMode) {
        await actions.create(
          name: name,
          mountKey: mountKey,
          relativeRoot: path,
          libraryType: _libraryType,
        );
      } else {
        await actions.create(
          name: name,
          storageLocationId: _locationId,
          relativeRoot: path,
          libraryType: _libraryType,
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
    final mountAllowed = widget.source == null && _hasMountDirectPermission();
    final mountMode = mountAllowed && _mountMode;
    final mountsAsync = ref.read(videoTrustedMountsProvider);
    final mounts = mountsAsync.asData?.value ?? const <VideoTrustedMount>[];
    final mountKey =
        _mountKey ??
        mounts.where((mount) => mount.available).firstOrNull?.mountKey;
    final selected = await showDialog<String>(
      context: context,
      builder:
          (context) => _VideoStorageDirectoryDialog(
            locationId: _locationId,
            mountKey: mountMode ? mountKey : null,
            initialPath: _pathController.text,
          ),
    );
    if (!mounted || selected == null) {
      return;
    }
    _pathController.text = selected;
    if (_nameController.text.trim().isEmpty) {
      final String? name;
      if (mountMode) {
        name = selected == '.' ? mountKey : selected.split('/').last;
      } else {
        final location =
            widget.locations
                .where((item) => item.id == _locationId)
                .firstOrNull;
        if (location == null) {
          return;
        }
        name =
            selected == '.'
                ? (location.rootName.trim().isEmpty
                    ? location.name
                    : location.rootName)
                : selected.split('/').last;
      }
      if (name != null && name.trim().isNotEmpty) {
        _nameController.text = name.trim();
      }
    }
  }
}

class _VideoStorageDirectoryDialog extends ConsumerStatefulWidget {
  const _VideoStorageDirectoryDialog({
    required this.locationId,
    this.mountKey,
    required this.initialPath,
  });

  final String locationId;

  /// 非空时按可信挂载浏览（挂载直达模式），忽略 locationId。
  final String? mountKey;

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
    final parent = _currentPath == '.' ? null : _currentPath;
    final directories = ref.watch(
      widget.mountKey != null
          ? videoMountDirectoriesProvider((
            mountKey: widget.mountKey!,
            parent: parent,
          ))
          : videoStorageDirectoriesProvider((
            locationId: widget.locationId,
            parent: parent,
          )),
    );
    return AlertDialog(
      title: Text(
        widget.mountKey != null
            ? l10n.videoBrowseMountDirectory
            : l10n.videoBrowseRelativeDirectory,
      ),
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
    return Semantics(
      label: l10n.videoLibraryLoading,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
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
