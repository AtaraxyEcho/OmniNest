part of 'desktop_media_import_dialog.dart';

extension _DesktopMediaImportDialogUI on _DesktopMediaImportDialogState {
  Widget _sourceTabs(AppLocalizations l10n, DesktopSkin skin) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.raise,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sourceTab(
            label: l10n.desktopMediaImportFromFiles,
            icon: DesktopIcons.folder,
            selected: _source == _ImportSource.files,
            onPressed:
                () => applyState(() {
                  _source = _ImportSource.files;
                  _loadError = null;
                }),
          ),
          _sourceTab(
            label: l10n.desktopMediaImportFromDevice,
            icon: DesktopIcons.upload,
            selected: _source == _ImportSource.device,
            onPressed:
                () => applyState(() {
                  _source = _ImportSource.device;
                  _loadError = null;
                }),
          ),
        ],
      ),
    );
  }

  Widget _sourceTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 30,
              decoration: BoxDecoration(
                color: selected ? skin.raise2 : (hovered ? skin.raise : null),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? skin.text : skin.text2,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: DesktopType.dense(selected ? skin.text : skin.text2),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _breadcrumbsView(AppLocalizations l10n, DesktopSkin skin) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton(
            onPressed: () => _goToBreadcrumb(-1),
            child: Text(l10n.filesRootDirectory),
          ),
          for (var index = 0; index < _breadcrumbs.length; index++) ...[
            Icon(DesktopIcons.chevron, size: 14, color: skin.text3),
            TextButton(
              onPressed: () => _goToBreadcrumb(index),
              child: Text(_breadcrumbs[index].name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fileList(AppLocalizations l10n, DesktopSkin skin) {
    if (_loadError != null && _source == _ImportSource.device) {
      return _listMessage(skin, _loadError!);
    }
    if (_loadError != null && _source == _ImportSource.files) {
      return _listMessage(
        skin,
        _loadError!,
        action: l10n.coreRetry,
        onAction: () => _loadFiles(reset: true),
      );
    }
    if (_loading && _source == _ImportSource.files) {
      return const SizedBox(
        height: 126,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final deviceMode = _source == _ImportSource.device;
    final rows = deviceMode ? _visibleDeviceFiles : _visibleFiles;
    if (rows.isEmpty) {
      return _listMessage(
        skin,
        _filter.isNotEmpty
            ? l10n.desktopMediaImportNoMatches
            : deviceMode
            ? l10n.desktopMediaImportNoFiles
            : l10n.desktopMediaImportNoCompatibleFiles,
      );
    }
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: Scrollbar(
        controller: _listScroll,
        child: ListView.separated(
          controller: _listScroll,
          shrinkWrap: true,
          itemCount: rows.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            if (index >= rows.length) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (deviceMode) {
              final file = _visibleDeviceFiles[index];
              final key = _deviceKey(file);
              return _candidateRow(
                name: file.name,
                detail:
                    '${_extension(file.name).toUpperCase()} · ${_sizeText(_deviceSizes[key])}',
                selected: _selectedDeviceKeys.contains(key),
                icon: _mediaIcon,
                onPressed:
                    () => applyState(() {
                      if (!_selectedDeviceKeys.add(key)) {
                        _selectedDeviceKeys.remove(key);
                      }
                    }),
              );
            }
            final node = _visibleFiles[index];
            if (node.isFolder) {
              return _candidateRow(
                name: node.name,
                detail:
                    isZh
                        ? '${l10n.filesFolder} · 单击进入'
                        : '${l10n.filesFolder} · Click to open',
                selected: false,
                isFolder: true,
                icon: DesktopIcons.folder,
                onPressed: () => _enterFolder(node),
              );
            }
            final importable = _isImportableFile(node);
            final ext = _extension(node.name).toUpperCase();
            final extLabel = ext.isEmpty ? 'FILE' : ext;
            if (!importable) {
              final reasonText =
                  node.sizeBytes == 0
                      ? (isZh ? '空文件 (0 B)' : 'Empty file (0 B)')
                      : (isZh ? '不支持的格式' : 'Unsupported');
              return _candidateRow(
                name: node.name,
                detail:
                    '$extLabel · ${_sizeText(node.sizeBytes)} · $reasonText',
                selected: false,
                enabled: false,
                icon: DesktopIcons.file,
                onPressed: null,
              );
            }
            return _candidateRow(
              name: node.name,
              detail: '$extLabel · ${_sizeText(node.sizeBytes)}',
              selected: _selectedFileIds.contains(node.id),
              icon: _mediaIcon,
              onPressed:
                  () => applyState(() {
                    if (!_selectedFileIds.add(node.id)) {
                      _selectedFileIds.remove(node.id);
                    }
                  }),
            );
          },
        ),
      ),
    );
  }

  Widget _candidateRow({
    required String name,
    required String detail,
    required bool selected,
    required IconData icon,
    required VoidCallback? onPressed,
    VoidCallback? onDoubleTap,
    bool isFolder = false,
    bool enabled = true,
  }) {
    final skin = DesktopSkin.of(context);
    final row = DesktopHover(
      enabled: enabled && onPressed != null,
      builder:
          (context, hovered) => GestureDetector(
            onTap: enabled ? onPressed : null,
            onDoubleTap: enabled ? onDoubleTap : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    selected
                        ? skin.accent.withValues(alpha: 0.10)
                        : (hovered ? skin.raise2 : skin.raise),
                border: Border.all(
                  color:
                      selected
                          ? skin.accent.withValues(alpha: 0.45)
                          : skin.line,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (!isFolder) ...[
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color:
                            selected && enabled
                                ? skin.accent
                                : Colors.transparent,
                        border: Border.all(
                          color: selected && enabled ? skin.accent : skin.line2,
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child:
                          selected && enabled
                              ? Icon(
                                DesktopIcons.check,
                                size: 12,
                                color: skin.accentInk,
                              )
                              : null,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(icon, size: 16, color: skin.text2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.denseStrong(skin.text),
                        ),
                        Text(detail, style: DesktopType.caption(skin.text3)),
                      ],
                    ),
                  ),
                  if (isFolder)
                    Icon(DesktopIcons.chevron, size: 16, color: skin.text3),
                ],
              ),
            ),
          ),
    );
    if (!enabled) {
      return Opacity(opacity: 0.48, alwaysIncludeSemantics: true, child: row);
    }
    return row;
  }

  Widget _listMessage(
    DesktopSkin skin,
    String text, {
    String? action,
    VoidCallback? onAction,
  }) {
    return SizedBox(
      height: 110,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: DesktopType.secondary(skin.text3)),
            if (action != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _metadataSetting(AppLocalizations l10n, DesktopSkin skin) {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.desktopMediaImportMatchMetadata,
                  style: DesktopType.denseStrong(skin.text),
                ),
                Text(
                  l10n.desktopMediaImportMetadataHint,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          DesktopToggle(
            value: _matchMetadata,
            label: l10n.desktopMediaImportMatchMetadata,
            onChanged: (value) => applyState(() => _matchMetadata = value),
          ),
        ],
      ),
    );
  }

  /// 样例 `.imp-dest .sp-pick`：个人空间 / 家庭共享空间二选一。
  Widget _spacePicker(AppLocalizations l10n, DesktopSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.desktopMediaImportImportTo.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _spaceOption(
                l10n: l10n,
                skin: skin,
                title: l10n.importToPersonalSpace,
                description: l10n.desktopMediaImportPersonalDesc,
                icon: DesktopIcons.user,
                selected: _space == DesktopImportSpace.personal,
                onTap: () => unawaited(_setSpace(DesktopImportSpace.personal)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _spaceOption(
                l10n: l10n,
                skin: skin,
                title: l10n.importToSharedSpace,
                description: l10n.desktopMediaImportSharedDesc,
                icon: DesktopIcons.users,
                selected: _space == DesktopImportSpace.shared,
                onTap: () => unawaited(_setSpace(DesktopImportSpace.shared)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _spaceOption({
    required AppLocalizations l10n,
    required DesktopSkin skin,
    required String title,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    selected
                        ? skin.accent.withValues(alpha: 0.10)
                        : (hovered ? skin.raise2 : skin.raise),
                border: Border.all(
                  color:
                      selected
                          ? skin.accent.withValues(alpha: 0.45)
                          : skin.line,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 17, color: skin.text2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: DesktopType.denseStrong(skin.text)),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: DesktopType.caption(skin.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// 样例 `.imp-tools`：筛选 + 全选 + 选中计数。
  Widget _listTools(AppLocalizations l10n, DesktopSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (_sourceCount > 5 || _filter.isNotEmpty)
            SizedBox(
              width: 240,
              child: DesktopTextField(
                controller: _filterController,
                hint: l10n.desktopMediaImportFilter,
                prefixIcon: DesktopIcons.search,
                onChanged: (value) => applyState(() => _filter = value),
              ),
            ),
          const Spacer(),
          if (_selectableCount > 0) ...[
            DesktopButton(
              label:
                  _allSelected
                      ? l10n.desktopMediaImportClearSelection
                      : l10n.desktopMediaImportSelectAll,
              variant: DesktopButtonVariant.ghost,
              onPressed: _toggleAll,
            ),
            const SizedBox(width: 10),
            Text(
              '${_selectedCountText()} / $_selectableCount',
              style: DesktopType.caption(skin.text3),
            ),
          ],
        ],
      ),
    );
  }

  String _selectedCountText() =>
      (_source == _ImportSource.files
              ? _selectedFileIds.length
              : _selectedDeviceKeys.length)
          .toString();

  String _sizeText(int? bytes) {
    if (bytes == null) return '—';
    if (bytes == 0) return '0 B';
    if (bytes >= 1000000000) {
      return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    return '${(bytes / 1000).round().clamp(1, 999)} KB';
  }
}
