part of 'admin_operations_pages.dart';

// ── 媒体库管理段区 ──────────────────────────────────────────────────────

/// 上次扫描摘要：从未扫描或全零时显示占位符。
String _lastScanSummary(AppLocalizations l10n, VideoLibrarySource source) {
  if (source.scanStatus == 'NEVER_SCANNED' ||
      (source.lastScannedCount == 0 &&
          source.lastCreatedCount == 0 &&
          source.lastCandidateCount == 0 &&
          source.lastMissingCount == 0)) {
    return '—';
  }
  return l10n.adminLibraryLastScanSummary(
    source.lastCandidateCount,
    source.lastCreatedCount,
    source.lastMissingCount,
  );
}

String _scanStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'READY' => l10n.statusScanReady,
    'QUEUED' => l10n.statusScanQueued,
    'DISCOVERING' || 'SCANNING' => l10n.statusScanDiscovering,
    'FAILED' => l10n.statusScanFailed,
    'CANCELLED' => l10n.statusScanCancelled,
    'PAUSED' => l10n.statusScanPaused,
    'NEVER_SCANNED' => l10n.adminLibraryScanNever,
    _ => status,
  };
}

AdminTagTone _scanStatusTone(String status) {
  return switch (status) {
    'READY' => AdminTagTone.success,
    'DISCOVERING' || 'SCANNING' || 'QUEUED' => AdminTagTone.info,
    'FAILED' => AdminTagTone.error,
    'PAUSED' => AdminTagTone.warning,
    _ => AdminTagTone.neutral,
  };
}

/// 库类型展示名。
String _libraryTypeLabel(AppLocalizations l10n, VideoLibraryType libraryType) {
  return switch (libraryType) {
    VideoLibraryType.movie => l10n.videoLibraryTypeMovie,
    VideoLibraryType.tvSeries => l10n.videoLibraryTypeTvSeries,
    VideoLibraryType.anime => l10n.videoLibraryTypeAnime,
    VideoLibraryType.root => l10n.videoLibraryTypeRoot,
  };
}

class _LibrarySourcesSection extends ConsumerStatefulWidget {
  const _LibrarySourcesSection({required this.canManage});

  final bool canManage;

  @override
  ConsumerState<_LibrarySourcesSection> createState() =>
      _LibrarySourcesSectionState();
}

class _LibrarySourcesSectionState
    extends ConsumerState<_LibrarySourcesSection> {
  /// 正在执行"发现更新"扫描的库源，用于行内按钮转圈与禁用。
  String? _scanningSourceId;

  bool get canManage => widget.canManage;

  Widget _buildAddButton(
    BuildContext context,
    AppLocalizations l10n,
    bool canAdd,
    List<VideoStorageLocation> locations,
  ) {
    final button = FilledButton.tonalIcon(
      onPressed:
          canAdd
              ? () => showDialog<void>(
                context: context,
                builder:
                    (dialogContext) => VideoLibrarySourceDialog(
                      source: null,
                      locations: locations,
                    ),
              )
              : null,
      icon: const Icon(Icons.add_rounded),
      label: Text(l10n.adminLibrarySourceAdd),
    );
    if (canAdd) {
      return button;
    }
    return Tooltip(
      message: l10n.videoNoAvailableStorageLocationHint,
      child: button,
    );
  }

  /// 触发库源"发现更新"扫描：入队后由后台任务继续展示真实进度。
  Future<void> _discoverUpdates(VideoLibrarySource source) async {
    if (_scanningSourceId != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _scanningSourceId = source.id);
    try {
      final task = await ref
          .read(videoLibrarySourceActionsProvider)
          .scan(source.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(task.message)));
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.adminLoadFailed(
                describeUserFacingError(error, l10n: l10n).message,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanningSourceId = null);
      }
    }
  }

  Future<void> _deleteSource(VideoLibrarySource source) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminLibraryDeleteSourceTitle),
            content: Text(l10n.adminLibraryDeleteSourceBody(source.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.adminCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.adminStorageDeleteAction),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(videoLibrarySourceActionsProvider).delete(source.id);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.adminLoadFailed(
                describeUserFacingError(error, l10n: l10n).message,
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    // 删除后刷新存储管理视图，计算已无库源引用的孤立挂载位置并提示清理；
    // 实际删除仍走存储位置删除接口，后端内容引用与业务使用双检查兜底。
    ref.invalidate(adminStorageProvider);
    List<AdminStorageLocation> orphans;
    List<VideoLibrarySource> remainingSources;
    try {
      final view = await ref.read(adminStorageProvider.future);
      if (!mounted) return;
      remainingSources = await ref.read(videoLibrarySourcesProvider.future);
      if (!mounted) return;
      final referencedIds =
          remainingSources.map((item) => item.storageLocationId).toSet();
      orphans =
          view.locations
              .where((location) => !referencedIds.contains(location.id))
              .toList();
    } on Exception {
      return;
    }
    if (!mounted || orphans.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.adminLibraryOrphanLocation(orphans.length)),
        action:
            orphans.length == 1
                ? SnackBarAction(
                  label: l10n.adminLibraryCleanupOrphan,
                  onPressed: () => _cleanupOrphanLocation(orphans.first),
                )
                : null,
      ),
    );
  }

  /// 删除单个孤立挂载位置；失败时以 snackbar 反馈。
  Future<void> _cleanupOrphanLocation(AdminStorageLocation location) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .deleteStorageLocation(location.id);
      ref.invalidate(adminStorageProvider);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.adminLoadFailed(
                describeUserFacingError(error, l10n: l10n).message,
              ),
            ),
          ),
        );
      }
    }
  }

  void _editSource(
    VideoLibrarySource source,
    List<VideoStorageLocation> locations,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) =>
              VideoLibrarySourceDialog(source: source, locations: locations),
    );
  }

  /// 打开访问管理弹窗：可见性与授权用户。
  void _openAccessDialog(VideoLibrarySource source) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminLibraryAccessTitle),
            content: SizedBox(
              width: 420,
              child: MediaLibraryAccessPanel(source: source),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.coreClose),
              ),
            ],
          ),
    );
  }

  /// 打开媒体库管理窗口：父子嵌套布局承载库源信息与审阅工作区。
  void _openManageWindow(VideoLibrarySource source, String locationName) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) =>
              _LibraryManageWindow(source: source, locationName: locationName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(videoLibrarySourcesProvider);
    final locationsAsync = ref.watch(videoStorageLocationsProvider);
    final locations =
        locationsAsync.asData?.value ?? const <VideoStorageLocation>[];
    final sources = sourcesAsync.asData?.value ?? const <VideoLibrarySource>[];
    final canAdd = locations.any((location) => location.available);
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final filtered =
        query.isEmpty
            ? sources
            : sources
                .where(
                  (source) =>
                      source.name.toLowerCase().contains(query) ||
                      source.relativeRoot.toLowerCase().contains(query),
                )
                .toList();
    String locationName(VideoLibrarySource source) =>
        locations
            .where((item) => item.id == source.storageLocationId)
            .firstOrNull
            ?.name ??
        source.storageLocationId;

    return AdminTableSection(
      title: l10n.adminLibrarySourcesSection,
      subtitle: l10n.adminLibrarySourcesSubtitle,
      trailing: [
        if (canManage) _buildAddButton(context, l10n, canAdd, locations),
      ],
      children: [
        AdminDataTable(
          showIndex: true,
          minTableWidth: 1080,
          // 4 个操作按钮在触控密度下需 4×48，默认 168 宽度会横向溢出。
          actionColumnWidth: 200,
          rowCount: filtered.length,
          onRowTap:
              (index) => _openManageWindow(
                filtered[index],
                locationName(filtered[index]),
              ),
          emptyState: AdminListEmptyState(
            message:
                query.isEmpty
                    ? l10n.adminLibrarySourcesEmpty
                    : l10n.adminNoMatch,
          ),
          columns: [
            AdminListColumn(
              key: 'name',
              label: l10n.adminLibraryColumnName,
              flex: 2,
            ),
            AdminListColumn(
              key: 'location',
              label: l10n.adminLibraryColumnLocation,
              flex: 2,
            ),
            AdminListColumn(
              key: 'type',
              label: l10n.videoLibraryType,
              minWidth: 100,
            ),
            AdminListColumn(
              key: 'scanStatus',
              label: l10n.adminLibraryColumnScanStatus,
              minWidth: 110,
            ),
            AdminListColumn(
              key: 'lastScan',
              label: l10n.adminLibraryColumnLastScan,
              minWidth: 200,
            ),
            AdminListColumn(
              key: 'status',
              label: l10n.adminFilterStatus,
              minWidth: 90,
            ),
          ],
          rowCellsBuilder: (context, index) {
            final source = filtered[index];
            return [
              Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${locationName(source)} · ${source.relativeRoot}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _libraryTypeLabel(l10n, source.libraryType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              AdminStatusTag(
                label: _scanStatusLabel(l10n, source.scanStatus),
                tone: _scanStatusTone(source.scanStatus),
              ),
              Text(
                _lastScanSummary(l10n, source),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              AdminStatusTag(
                label:
                    source.enabled
                        ? l10n.adminStatusEnabled
                        : l10n.adminStatusDisabled,
                tone:
                    source.enabled
                        ? AdminTagTone.success
                        : AdminTagTone.neutral,
              ),
            ];
          },
          actionsBuilder: (context, index) {
            final source = filtered[index];
            final scanning = _scanningSourceId == source.id;
            return [
              IconButton(
                tooltip: l10n.adminLibraryDiscoverUpdates,
                icon:
                    scanning
                        ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.manage_search_rounded, size: 20),
                onPressed:
                    canManage && source.enabled && !scanning
                        ? () => _discoverUpdates(source)
                        : null,
              ),
              IconButton(
                tooltip: l10n.adminLibraryAccessTitle,
                icon: const Icon(Icons.people_outline_rounded, size: 20),
                onPressed: canManage ? () => _openAccessDialog(source) : null,
              ),
              IconButton(
                tooltip: l10n.videoEditLibrarySource,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed:
                    canManage ? () => _editSource(source, locations) : null,
              ),
              IconButton(
                tooltip: l10n.adminLibraryDeleteSourceTitle,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: canManage ? () => _deleteSource(source) : null,
              ),
            ];
          },
        ),
      ],
    );
  }
}

/// 媒体库管理窗口：父子嵌套布局。
///
/// 顶层为"库源信息"与"发现与审阅"两个可折叠父区，子内容整体缩进；
/// 窗口内容超出最大高度时整体滚动，审阅工作区按窗口高度自适应树高，
/// 避免有界高度溢出。
class _LibraryManageWindow extends StatefulWidget {
  const _LibraryManageWindow({
    required this.source,
    required this.locationName,
  });

  final VideoLibrarySource source;
  final String locationName;

  @override
  State<_LibraryManageWindow> createState() => _LibraryManageWindowState();
}

class _LibraryManageWindowState extends State<_LibraryManageWindow> {
  bool _infoExpanded = true;
  bool _reviewExpanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = widget.source;
    // 窗口最大高 85% 屏高，扣除头部、信息区与审阅摘要后为媒体树高度，
    // 下限保证树区至少可见数行，上限避免大屏过度拉伸。
    final treeHeight = ((MediaQuery.sizeOf(context).height * 0.85) - 330).clamp(
      280.0,
      520.0,
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.videoSectionLibraryScan} · ${source.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: l10n.coreClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ManageSectionParent(
                      title: l10n.adminLibraryManageInfoSection,
                      expanded: _infoExpanded,
                      onToggle:
                          () => setState(() => _infoExpanded = !_infoExpanded),
                      trailing: [
                        AdminStatusTag(
                          label: _scanStatusLabel(l10n, source.scanStatus),
                          tone: _scanStatusTone(source.scanStatus),
                        ),
                        AdminStatusTag(
                          label:
                              source.enabled
                                  ? l10n.adminStatusEnabled
                                  : l10n.adminStatusDisabled,
                          tone:
                              source.enabled
                                  ? AdminTagTone.success
                                  : AdminTagTone.neutral,
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 4, 20, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.videoLibraryType}：${_libraryTypeLabel(l10n, source.libraryType)} · ${widget.locationName} · ${source.relativeRoot}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${l10n.adminLibraryColumnLastScan}：${_lastScanSummary(l10n, source)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    _ManageSectionParent(
                      title: l10n.adminLibraryManageReviewSection,
                      expanded: _reviewExpanded,
                      onToggle:
                          () => setState(
                            () => _reviewExpanded = !_reviewExpanded,
                          ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: MediaLibraryReviewWorkspace(
                          source: source,
                          treeHeight: treeHeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 管理窗口父子嵌套父行：展开箭头 + 标题 + 可选状态标签，子内容整体
/// 缩进展示，点击父行切换折叠。
class _ManageSectionParent extends StatelessWidget {
  const _ManageSectionParent({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.trailing = const <Widget>[],
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (var i = 0; i < trailing.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  trailing[i],
                ],
              ],
            ),
          ),
        ),
        if (expanded) child,
      ],
    );
  }
}
