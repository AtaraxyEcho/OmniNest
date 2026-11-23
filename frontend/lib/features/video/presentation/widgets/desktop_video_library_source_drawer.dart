part of 'movie_management.dart';

/// 桌面端新增/编辑媒体库来源抽屉：统一采用 `DesktopDrawerFrame` + 桌面控件，
/// 编辑态支持变更媒体库类型并调用 `/reclassify` 原地重新归类已入库条目。
class DesktopVideoLibrarySourceDrawer extends ConsumerStatefulWidget {
  const DesktopVideoLibrarySourceDrawer({
    required this.locations,
    this.source,
    super.key,
  });

  final List<VideoStorageLocation> locations;
  final VideoLibrarySource? source;

  @override
  ConsumerState<DesktopVideoLibrarySourceDrawer> createState() =>
      _DesktopVideoLibrarySourceDrawerState();
}

class _DesktopVideoLibrarySourceDrawerState
    extends ConsumerState<DesktopVideoLibrarySourceDrawer> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late String _locationId;
  String? _mountKey;
  bool _mountMode = true;
  late VideoLibraryType _libraryType;
  late bool _enabled;
  bool _saving = false;
  bool _reclassifying = false;

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
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>[];
    return _mountDirectPermissions.every(permissions.contains);
  }

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  bool get _typeChanged =>
      widget.source != null && _libraryType != widget.source!.libraryType;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final mountAllowed = widget.source == null && _hasMountDirectPermission();
    final effectiveMountMode = mountAllowed && _mountMode;
    final mountsAsync = ref.watch(videoTrustedMountsProvider);
    final mounts = mountsAsync.asData?.value ?? const <VideoTrustedMount>[];
    final availableMounts = mounts.where((mount) => mount.available).toList();
    final effectiveMountKey =
        _mountKey ?? availableMounts.firstOrNull?.mountKey;

    if (!effectiveMountMode &&
        (_locationId.isEmpty || widget.locations.isEmpty)) {
      return DesktopDrawerFrame(
        eyebrow: _libraryType.apiValue,
        title: l10n.videoNoAvailableStorageLocation,
        footer: DesktopButton(
          label: l10n.coreClose,
          variant: DesktopButtonVariant.ghost,
          onPressed: () => closeDesktopModal(context),
        ),
        child: Text(
          l10n.videoNoAvailableStorageLocationHint,
          style: DesktopType.body(skin.text2),
        ),
      );
    }

    final busy = _saving || _reclassifying;
    final canSubmit =
        !busy && !(effectiveMountMode && effectiveMountKey == null);

    return DesktopDrawerFrame(
      eyebrow: _libraryType.apiValue,
      title:
          widget.source == null
              ? l10n.videoAddLibrarySource
              : l10n.videoEditLibrarySource,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DesktopButton(
            label: l10n.videoCancel,
            variant: DesktopButtonVariant.ghost,
            onPressed: busy ? null : () => closeDesktopModal(context),
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label:
                _typeChanged
                    ? (_isZh ? '变更类型并重新归类' : 'Change type & reclassify')
                    : l10n.coreSave,
            variant: DesktopButtonVariant.primary,
            busy: busy,
            onPressed: canSubmit ? _save : null,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mountAllowed) ...[
            DesktopSeg<bool>(
              options: const [true, false],
              value: _mountMode,
              labelOf:
                  (isMount) =>
                      isMount
                          ? l10n.videoSourceFromMount
                          : l10n.videoStorageLocation,
              onChanged: (value) {
                if (!busy) {
                  setState(() => _mountMode = value);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
          DesktopTextField(
            controller: _nameController,
            label: l10n.videoSourceName,
            enabled: !busy,
          ),
          const SizedBox(height: 14),
          if (effectiveMountMode) ...[
            _DrawerFieldLabel(l10n.videoTrustedMountLabel),
            const SizedBox(height: 6),
            DesktopSelect<String>(
              value: effectiveMountKey ?? '',
              options: [
                for (final mount in availableMounts)
                  DesktopSelectOption(
                    value: mount.mountKey,
                    label: mount.displayName,
                  ),
              ],
              placeholder: l10n.videoNoTrustedMount,
              onChanged: (value) {
                if (!busy) {
                  setState(() {
                    _mountKey = value;
                    _pathController.text = '.';
                  });
                }
              },
            ),
          ] else ...[
            _DrawerFieldLabel(l10n.videoStorageLocation),
            const SizedBox(height: 6),
            if (widget.source == null)
              DesktopSelect<String>(
                value: _locationId,
                options: [
                  for (final location in widget.locations.where(
                    (loc) => loc.available,
                  ))
                    DesktopSelectOption(
                      value: location.id,
                      label:
                          '${location.name} · ${_storageHealthLabel(l10n, location.healthStatus)}',
                    ),
                ],
                onChanged: (value) {
                  if (!busy) {
                    setState(() {
                      _locationId = value;
                      _pathController.text = '.';
                    });
                  }
                },
              )
            else
              _ReadOnlyFieldBox(
                text:
                    widget.locations
                        .where((loc) => loc.id == _locationId)
                        .firstOrNull
                        ?.name ??
                    _locationId,
              ),
          ],
          const SizedBox(height: 14),
          _DrawerFieldLabel(l10n.videoLibraryType),
          const SizedBox(height: 6),
          DesktopSelect<VideoLibraryType>(
            value: _libraryType,
            options: [
              for (final type in VideoLibraryType.values)
                DesktopSelectOption(
                  value: type,
                  label: _libraryTypeLabel(l10n, type),
                ),
            ],
            onChanged: (value) {
              if (!busy) {
                setState(() => _libraryType = value);
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            l10n.videoLibraryTypeHint,
            style: DesktopType.caption(skin.text3),
          ),
          if (_typeChanged) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: skin.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: skin.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(DesktopIcons.sparkle, size: 16, color: skin.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isZh
                          ? '保存时将按新类型重新归类该来源下已入库的影片/剧集，保留现有播放进度与字幕并清理孤儿电影条目。'
                          : 'Saving will reclassify existing items under this source using the new type, keeping playback progress and subtitles while cleaning orphaned movie records.',
                      style: DesktopType.caption(skin.text2),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: DesktopTextField(
                  controller: _pathController,
                  label: l10n.videoRelativeDirectory,
                  enabled: false,
                ),
              ),
              const SizedBox(width: 8),
              DesktopButton(
                label: l10n.videoBrowseRelativeDirectory,
                icon: DesktopIcons.folder,
                variant: DesktopButtonVariant.soft,
                onPressed:
                    busy || (effectiveMountMode && effectiveMountKey == null)
                        ? null
                        : _browseDirectory,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            effectiveMountMode
                ? l10n.videoNoTrustedMountHint
                : l10n.videoRelativeDirectoryHint,
            style: DesktopType.caption(skin.text3),
          ),
          if (effectiveMountMode && effectiveMountKey == null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.videoNoTrustedMount,
              style: DesktopType.caption(skin.bad),
            ),
          ],
          if (widget.source != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.videoSourceEnabled,
                    style: DesktopType.body(skin.text),
                  ),
                ),
                DesktopToggle(
                  value: _enabled,
                  label: l10n.videoSourceEnabled,
                  onChanged: (value) {
                    if (!busy) {
                      setState(() => _enabled = value);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
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
    final mounts =
        ref.read(videoTrustedMountsProvider).asData?.value ??
        const <VideoTrustedMount>[];
    final mountKey =
        _mountKey ??
        mounts.where((mount) => mount.available).firstOrNull?.mountKey;
    if (mountMode && mountKey == null) {
      showMovieFeedback(context, l10n.videoNoTrustedMount, isError: true);
      return;
    }

    final editingSource = widget.source;
    if (editingSource != null && _typeChanged) {
      final confirmed = await showDesktopConfirm(
        context,
        title: _isZh ? '变更类型并重新归类' : 'Change type & reclassify',
        message:
            _isZh
                ? '确认将「$name」的类型变更为「${_libraryTypeLabel(l10n, _libraryType)}」并重新归类已入库内容？'
                : 'Change "$name" to "${_libraryTypeLabel(l10n, _libraryType)}" and reclassify imported items?',
        confirmLabel: _isZh ? '确认重新归类' : 'Reclassify',
        cancelLabel: l10n.videoCancel,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      _saving = true;
      _reclassifying = editingSource != null && _typeChanged;
    });
    try {
      final actions = ref.read(videoLibrarySourceActionsProvider);
      if (editingSource != null) {
        final needsMetaUpdate =
            name != editingSource.name ||
            path != editingSource.relativeRoot ||
            _enabled != editingSource.enabled;
        if (needsMetaUpdate || !_typeChanged) {
          await actions.update(
            source: editingSource,
            name: name,
            relativeRoot: path,
            libraryType: editingSource.libraryType,
            enabled: _enabled,
          );
        }
        if (_typeChanged) {
          await ref
              .read(movieApiProvider)
              .reclassifyLibrarySource(
                sourceId: editingSource.id,
                libraryType: _libraryType,
              );
          if (!mounted) return;
          ref.invalidate(videoLibrarySourcesProvider);
          ref.invalidate(latestMediaScanRunProvider(editingSource.id));
          ref.invalidate(movieDashboardProvider);
          ref.invalidate(movieCenterControllerProvider);
          showMovieFeedback(
            context,
            _isZh ? '媒体库类型已变更并完成重新归类' : 'Library type updated and reclassified',
          );
        }
      } else if (mountMode) {
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
      if (mounted) closeDesktopModal(context);
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(
          context,
          movieErrorMessage(error, AppLocalizations.of(context)),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _reclassifying = false;
        });
      }
    }
  }

  Future<void> _browseDirectory() async {
    final mountAllowed = widget.source == null && _hasMountDirectPermission();
    final mountMode = mountAllowed && _mountMode;
    final mounts =
        ref.read(videoTrustedMountsProvider).asData?.value ??
        const <VideoTrustedMount>[];
    final mountKey =
        _mountKey ??
        mounts.where((mount) => mount.available).firstOrNull?.mountKey;
    final selected = await showDesktopDialog<String>(
      context,
      builder:
          (context) => _DesktopStorageDirectoryDialog(
            locationId: _locationId,
            mountKey: mountMode ? mountKey : null,
            initialPath: _pathController.text,
          ),
    );
    if (!mounted || selected == null) {
      return;
    }
    _pathController.text = selected;
    if (widget.source == null) {
      final inferred = _inferLibraryTypeFromPath(selected);
      if (inferred != null) {
        setState(() => _libraryType = inferred);
      }
    }
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

class _DrawerFieldLabel extends StatelessWidget {
  const _DrawerFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Text(text, style: DesktopType.fieldLabel(skin.text2));
  }
}

class _ReadOnlyFieldBox extends StatelessWidget {
  const _ReadOnlyFieldBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.line),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DesktopType.body(skin.text2),
      ),
    );
  }
}

/// 桌面端目录选择弹窗：基于 `DesktopDialog`，替代旧 `WorkstationDialogFrame`。
class _DesktopStorageDirectoryDialog extends ConsumerStatefulWidget {
  const _DesktopStorageDirectoryDialog({
    required this.locationId,
    this.mountKey,
    required this.initialPath,
  });

  final String locationId;
  final String? mountKey;
  final String initialPath;

  @override
  ConsumerState<_DesktopStorageDirectoryDialog> createState() =>
      _DesktopStorageDirectoryDialogState();
}

class _DesktopStorageDirectoryDialogState
    extends ConsumerState<_DesktopStorageDirectoryDialog> {
  late String _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = _normalizePath(widget.initialPath);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
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
    return DesktopDialog(
      title:
          widget.mountKey != null
              ? l10n.videoBrowseMountDirectory
              : l10n.videoBrowseRelativeDirectory,
      width: 520,
      content: SizedBox(
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DesktopIconButton(
                  icon: DesktopIcons.left,
                  tooltip: l10n.videoBackToParentNode,
                  onPressed:
                      _currentPath == '.'
                          ? null
                          : () => setState(
                            () =>
                                _currentPath = _parentPath(_currentPath) ?? '.',
                          ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentPath == '.'
                        ? l10n.videoDirectoryRoot
                        : _currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.body(skin.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: skin.line),
            const SizedBox(height: 6),
            Expanded(
              child: directories.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => MovieNoticePanel(
                      icon: Icons.error_outline_rounded,
                      title: l10n.videoStorageLocationUnavailable,
                      message: movieErrorMessage(
                        error,
                        AppLocalizations.of(context),
                      ),
                    ),
                data:
                    (page) => ListView.builder(
                      itemCount: page.items.length,
                      itemBuilder: (context, index) {
                        final directory = page.items[index];
                        return DesktopHover(
                          builder:
                              (context, hovered) => GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap:
                                    () => setState(
                                      () =>
                                          _currentPath = directory.relativePath,
                                    ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        hovered
                                            ? skin.raise
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        DesktopIcons.folder,
                                        size: 16,
                                        color: skin.accent,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          directory.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopType.body(skin.text),
                                        ),
                                      ),
                                      if (directory.hasChildren)
                                        Icon(
                                          DesktopIcons.chevron,
                                          size: 16,
                                          color: skin.text3,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        DesktopButton(
          label: l10n.videoCancel,
          variant: DesktopButtonVariant.ghost,
          onPressed: () => closeDesktopModal(context),
        ),
        DesktopButton(
          label: l10n.videoChooseThisDirectory,
          variant: DesktopButtonVariant.primary,
          onPressed: () => closeDesktopModal(context, _currentPath),
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

VideoLibraryType? _inferLibraryTypeFromPath(String relativePath) {
  final normalized = relativePath.trim().replaceAll('\\', '/');
  if (normalized.isEmpty || normalized == '.') {
    return VideoLibraryType.root;
  }
  final segments =
      normalized
          .split('/')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty && s != '.')
          .toList();
  for (final seg in segments.reversed) {
    if (seg == 'anime' ||
        seg == '动漫' ||
        seg == '动画' ||
        seg == '番剧' ||
        seg == '国漫' ||
        seg == '日漫') {
      return VideoLibraryType.anime;
    }
    if (seg == 'tv' ||
        seg == 'tv series' ||
        seg == 'tv_series' ||
        seg == 'tv-series' ||
        seg == 'series' ||
        seg == '剧集' ||
        seg == '电视剧' ||
        seg == '美剧' ||
        seg == '日剧' ||
        seg == '韩剧' ||
        seg == '英剧') {
      return VideoLibraryType.tvSeries;
    }
    if (seg == 'movie' ||
        seg == 'movies' ||
        seg == 'film' ||
        seg == 'films' ||
        seg == '电影') {
      return VideoLibraryType.movie;
    }
  }
  return null;
}
