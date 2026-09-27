part of 'admin_operations_pages.dart';

enum _StorageStatusFilter { all, enabled, disabled, unhealthy }

/// 挂载媒体库约定目录；与后端 provision 逻辑保持一致，匹配忽略大小写。
const List<String> _mountCatalogSlots = ['movie', 'tv', 'anime'];
final Set<String> _mountCatalogRoots = _mountCatalogSlots.toSet();

String _mountCatalogLabel(AppLocalizations l10n, String root) {
  return switch (root) {
    'movie' => l10n.adminMountLibraryCatalogMovie,
    'tv' => l10n.adminMountLibraryCatalogTv,
    _ => l10n.adminMountLibraryCatalogAnime,
  };
}

bool _isMountCatalogRoot(String relativeRoot) =>
    _mountCatalogRoots.contains(relativeRoot.toLowerCase());

class _MountLibraryState {
  const _MountLibraryState({
    required this.enabled,
    required this.autoImport,
    required this.presentRoots,
    required this.provisioned,
    this.sourceIds = const <String>[],
  });

  final bool enabled;
  final bool autoImport;
  final Set<String> presentRoots;
  final bool provisioned;
  final List<String> sourceIds;

  int get sourceCount => presentRoots.length;
  bool get isPartial =>
      provisioned && presentRoots.length < _mountCatalogRoots.length;
}

_MountLibraryState _resolveMountLibraryState({
  required String mountKey,
  required List<VideoStorageLocation> locations,
  required List<VideoLibrarySource> sources,
}) {
  final location =
      locations
          .where(
            (item) => item.mountKey == mountKey && item.relativeRoot == '.',
          )
          .firstOrNull;
  if (location == null) {
    return const _MountLibraryState(
      enabled: false,
      autoImport: false,
      presentRoots: {},
      provisioned: false,
    );
  }
  final catalog =
      sources
          .where(
            (source) =>
                source.storageLocationId == location.id &&
                _isMountCatalogRoot(source.relativeRoot),
          )
          .toList();
  if (catalog.isEmpty) {
    return const _MountLibraryState(
      enabled: false,
      autoImport: false,
      presentRoots: {},
      provisioned: false,
    );
  }
  return _MountLibraryState(
    enabled: catalog.every((source) => source.enabled),
    autoImport: catalog.any((source) => source.importPolicy != 'MANUAL_REVIEW'),
    presentRoots:
        catalog.map((source) => source.relativeRoot.toLowerCase()).toSet(),
    provisioned: true,
    sourceIds: catalog.map((source) => source.id).toList(),
  );
}

bool _storageHealthy(AdminStorageLocation location) =>
    location.healthStatus.toUpperCase() == 'AVAILABLE';

class AdminStoragePage extends ConsumerStatefulWidget {
  const AdminStoragePage({required this.view, super.key});

  final AdminStorageManagementView view;

  @override
  ConsumerState<AdminStoragePage> createState() => _AdminStoragePageState();
}

/// 禁用挂载位置前确认；停用属高危操作。
Future<bool> _confirmDisableStorage(
  BuildContext context,
  AppLocalizations l10n,
  AdminStorageLocation location,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(l10n.adminStorageDisableConfirmTitle),
          content: Text(l10n.adminStorageDisableConfirmBody(location.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.adminCancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.adminStorageDisableAction),
            ),
          ],
        ),
  );
  return confirmed == true;
}

/// 删除挂载位置前确认。
Future<bool> _confirmDeleteStorage(
  BuildContext context,
  AppLocalizations l10n,
  AdminStorageLocation location,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(l10n.adminStorageDeleteConfirmTitle),
          content: Text(l10n.adminStorageDeleteConfirmBody(location.name)),
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
  return confirmed == true;
}

/// 挂载位置详情弹窗：全量字段 + 启用/停用与删除操作。
void _showStorageLocationDetail(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  AdminStorageLocation location, {
  required bool canManage,
}) {
  String fieldLabel(String label, String value) => '$label: $value';

  showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  location.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AdminStatusPill(
                label: healthStatusLabel(l10n, location.healthStatus),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fieldLabel(
                    l10n.adminStorageFieldProvider,
                    providerTypeLabel(l10n, location.providerType),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  fieldLabel(
                    l10n.adminStorageFieldManagement,
                    location.managementMode,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  fieldLabel(l10n.adminMountKey, location.mountKey),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  fieldLabel(l10n.adminStorageFieldPath, location.relativeRoot),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  fieldLabel(
                    l10n.adminStorageFieldScope,
                    scopeTypeLabel(l10n, location.scopeType),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  fieldLabel(l10n.adminStorageFieldNode, location.nodeId),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            if (canManage)
              location.enabled
                  ? OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _toggleStorageLocation(
                        context,
                        ref,
                        l10n,
                        location,
                        enabled: false,
                      );
                    },
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: Text(l10n.adminStorageDisableAction),
                  )
                  : FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _toggleStorageLocation(
                        context,
                        ref,
                        l10n,
                        location,
                        enabled: true,
                      );
                    },
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: Text(l10n.adminStorageEnableAction),
                  ),
            if (canManage)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _deleteStorageLocation(context, ref, l10n, location);
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.adminStorageDeleteAction),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.coreClose),
            ),
          ],
        ),
  );
}

/// 切换挂载位置启用状态（含禁用确认）。
Future<void> _toggleStorageLocation(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  AdminStorageLocation location, {
  required bool enabled,
}) async {
  if (!enabled && !await _confirmDisableStorage(context, l10n, location)) {
    return;
  }
  try {
    await ref
        .read(adminOperationsActionsProvider)
        .updateStorageLocation(location: location, enabled: enabled);
  } on Exception catch (error) {
    if (context.mounted) {
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

/// 删除挂载位置（含确认）。
Future<void> _deleteStorageLocation(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  AdminStorageLocation location,
) async {
  if (!await _confirmDeleteStorage(context, l10n, location)) {
    return;
  }
  try {
    await ref
        .read(adminOperationsActionsProvider)
        .deleteStorageLocation(location.id);
  } on Exception catch (error) {
    if (context.mounted) {
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

class _AdminStoragePageState extends ConsumerState<AdminStoragePage> {
  _StorageStatusFilter _statusFilter = _StorageStatusFilter.all;

  List<AdminStorageLocation> _filteredLocations(
    List<AdminStorageLocation> locations,
    String query,
  ) {
    final normalizedQuery = query.toLowerCase();
    return locations.where((location) {
      final matchesQuery =
          normalizedQuery.isEmpty ||
          location.name.toLowerCase().contains(normalizedQuery) ||
          location.mountKey.toLowerCase().contains(normalizedQuery) ||
          location.relativeRoot.toLowerCase().contains(normalizedQuery);
      if (!matchesQuery) {
        return false;
      }
      return switch (_statusFilter) {
        _StorageStatusFilter.all => true,
        _StorageStatusFilter.enabled => location.enabled,
        _StorageStatusFilter.disabled => !location.enabled,
        _StorageStatusFilter.unhealthy => !_storageHealthy(location),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 库源增删可能改变挂载位置引用关系。禁止在 build/layout 同帧直接
    // invalidate（Riverpod 3 会报同帧多次 rebuild）；仅在列表长度变化时
    // 推迟到帧末，再走合并刷新。
    ref.listen(videoLibrarySourcesProvider, (previous, next) {
      final prevCount = previous?.asData?.value.length;
      final nextCount = next.asData?.value.length;
      if (prevCount == null || nextCount == null || prevCount == nextCount) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref
            .read(adminOperationsActionsProvider)
            .scheduleStorageRelatedRefresh();
      });
    });
    final canManageStorage =
        ref
            .watch(authSessionProvider)
            .asData
            ?.value
            .user
            ?.permissions
            .contains('system:config:manage') ??
        false;
    final canManageSources =
        ref
            .watch(authSessionProvider)
            .asData
            ?.value
            .user
            ?.permissions
            .contains('media:library:manage') ??
        false;
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final locations = _filteredLocations(widget.view.locations, query);
    final listSection = AdminTableSection(
      title: l10n.adminStorageMountsSection,
      subtitle: l10n.adminLocalStorageLocationsSubtitle,
      trailing: const <Widget>[],
      filters: [
        for (final filter in _StorageStatusFilter.values)
          ChoiceChip(
            label: Text(switch (filter) {
              _StorageStatusFilter.all => l10n.adminStorageFilterAll,
              _StorageStatusFilter.enabled => l10n.adminStorageFilterEnabled,
              _StorageStatusFilter.disabled => l10n.adminStorageFilterDisabled,
              _StorageStatusFilter.unhealthy =>
                l10n.adminStorageFilterUnhealthy,
            }),
            selected: _statusFilter == filter,
            onSelected: (_) => setState(() => _statusFilter = filter),
          ),
      ],
      children: [
        AdminDataTable(
          showIndex: true,
          minTableWidth: 1120,
          rowCount: locations.length,
          emptyState: AdminListEmptyState(message: l10n.adminStorageEmptyList),
          onRowTap:
              (index) => _showStorageLocationDetail(
                context,
                ref,
                l10n,
                locations[index],
                canManage: canManageStorage,
              ),
          columns: [
            AdminListColumn(
              key: 'name',
              label: l10n.adminStorageColumnName,
              flex: 2,
            ),
            AdminListColumn(
              key: 'type',
              label: l10n.adminStorageColumnType,
              minWidth: 96,
            ),
            AdminListColumn(
              key: 'mountKey',
              label: l10n.adminStorageColumnMountKey,
              minWidth: 140,
            ),
            AdminListColumn(
              key: 'root',
              label: l10n.adminStorageColumnRoot,
              flex: 3,
            ),
            AdminListColumn(
              key: 'status',
              label: l10n.adminFilterStatus,
              minWidth: 96,
            ),
            AdminListColumn(
              key: 'health',
              label: l10n.adminStorageColumnHealth,
              minWidth: 104,
            ),
          ],
          rowCellsBuilder: (context, index) {
            final location = locations[index];
            final healthy = _storageHealthy(location);
            return [
              AdminCellText(
                location.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              AdminCellText(
                providerTypeLabel(l10n, location.providerType),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              AdminCellText(
                location.mountKey,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              AdminCellText(
                location.relativeRoot,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              AdminStatusTag(
                label:
                    location.enabled
                        ? l10n.adminStatusEnabled
                        : l10n.adminStatusDisabled,
                tone:
                    location.enabled
                        ? AdminTagTone.success
                        : AdminTagTone.neutral,
              ),
              AdminStatusTag(
                label: healthStatusLabel(l10n, location.healthStatus),
                tone: healthy ? AdminTagTone.success : AdminTagTone.warning,
              ),
            ];
          },
          actionsBuilder: (context, index) {
            final location = locations[index];
            return [
              IconButton(
                tooltip: l10n.adminStorageOpenDetail,
                icon: const Icon(Icons.info_outline_rounded, size: 20),
                onPressed:
                    () => _showStorageLocationDetail(
                      context,
                      ref,
                      l10n,
                      location,
                      canManage: canManageStorage,
                    ),
              ),
              if (canManageStorage)
                IconButton(
                  tooltip: l10n.adminStorageDeleteAction,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed:
                      () =>
                          _deleteStorageLocation(context, ref, l10n, location),
                ),
            ];
          },
        ),
      ],
    );

    return _PageEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminStorageManagement,
          subtitle: l10n.adminStorageManagementSubtitle,
          trailing: Wrap(
            spacing: 8,
            children: [
              IconButton.filledTonal(
                onPressed: () {
                  ref
                      .read(adminOperationsActionsProvider)
                      .scheduleStorageRelatedRefresh();
                },
                icon: const Icon(Icons.refresh_rounded),
                tooltip: l10n.adminRefresh,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _AdminTrustedMountsSection(
          mounts: widget.view.trustedMounts,
          canManage: canManageStorage && canManageSources,
        ),
        const SizedBox(height: 24),
        listSection,
        const SizedBox(height: 32),
        _LibrarySourcesSection(canManage: canManageSources),
      ],
    );
  }
}

/// 可信挂载点：配置即挂载，管理员只保留「启用媒体库」与「扫描后自动入库」两个开关。
/// 启用后系统在挂载根下按 Movie/TV/Anime 约定目录维护三个类型库源。
class _AdminTrustedMountsSection extends ConsumerStatefulWidget {
  const _AdminTrustedMountsSection({
    required this.mounts,
    required this.canManage,
  });

  final List<AdminTrustedMount> mounts;
  final bool canManage;

  @override
  ConsumerState<_AdminTrustedMountsSection> createState() =>
      _AdminTrustedMountsSectionState();
}

class _AdminTrustedMountsSectionState
    extends ConsumerState<_AdminTrustedMountsSection> {
  String? _busyMountKey;
  String? _scanningMountKey;

  Future<void> _provision(
    AdminTrustedMount mount, {
    required bool enabled,
    required bool autoImport,
  }) async {
    if (_busyMountKey != null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final wasEnabled =
        _resolveMountLibraryState(
          mountKey: mount.mountKey,
          locations:
              ref.read(videoStorageLocationsProvider).asData?.value ?? const [],
          sources:
              ref.read(videoLibrarySourcesProvider).asData?.value ?? const [],
        ).enabled;
    setState(() => _busyMountKey = mount.mountKey);
    try {
      await ref
          .read(videoLibrarySourceActionsProvider)
          .provisionMountLibrary(
            mountKey: mount.mountKey,
            enabled: enabled,
            autoImport: autoImport,
          );
      if (!mounted) {
        return;
      }
      ref.read(adminOperationsActionsProvider).scheduleStorageRelatedRefresh();
      if (enabled && !wasEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminMountLibraryProvisionSuccess)),
        );
      }
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.adminMountLibraryProvisionFailed}: '
            '${describeUserFacingError(error, l10n: l10n).message}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyMountKey = null);
      }
    }
  }

  Future<void> _scanAll(
    AdminTrustedMount mount,
    _MountLibraryState state,
  ) async {
    if (_scanningMountKey != null || state.sourceIds.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _scanningMountKey = mount.mountKey);
    try {
      final result = await ref
          .read(videoLibrarySourceActionsProvider)
          .scanAll(state.sourceIds);
      if (!mounted) {
        return;
      }
      if (result.failed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.adminMountLibraryScanAllSuccess(result.success)),
          ),
        );
      } else {
        final lastError =
            result.lastError == null
                ? ''
                : ' · ${describeUserFacingError(Exception(result.lastError), l10n: l10n).message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${l10n.adminMountLibraryScanAllPartial(result.success, result.failed)}$lastError',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanningMountKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locations =
        ref.watch(videoStorageLocationsProvider).asData?.value ??
        const <VideoStorageLocation>[];
    final sources =
        ref.watch(videoLibrarySourcesProvider).asData?.value ??
        const <VideoLibrarySource>[];
    return AdminTableSection(
      title: l10n.adminTrustedMountsTitle,
      subtitle: l10n.adminTrustedMountsSubtitle,
      children: [
        if (widget.mounts.isEmpty)
          _EmptyText(l10n.adminTrustedMountsEmpty)
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                for (final mount in widget.mounts)
                  _MountLibraryCard(
                    mount: mount,
                    state: _resolveMountLibraryState(
                      mountKey: mount.mountKey,
                      locations: locations,
                      sources: sources,
                    ),
                    canManage: widget.canManage,
                    busy: _busyMountKey == mount.mountKey,
                    onEnableChanged:
                        widget.canManage
                            ? (value) => _provision(
                              mount,
                              enabled: value,
                              autoImport:
                                  _resolveMountLibraryState(
                                    mountKey: mount.mountKey,
                                    locations: locations,
                                    sources: sources,
                                  ).autoImport,
                            )
                            : null,
                    onAutoImportChanged:
                        widget.canManage
                            ? (value) => _provision(
                              mount,
                              enabled: true,
                              autoImport: value,
                            )
                            : null,
                    scanning: _scanningMountKey == mount.mountKey,
                    onScanAll:
                        () => _scanAll(
                          mount,
                          _resolveMountLibraryState(
                            mountKey: mount.mountKey,
                            locations: locations,
                            sources: sources,
                          ),
                        ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MountLibraryCard extends StatelessWidget {
  const _MountLibraryCard({
    required this.mount,
    required this.state,
    required this.canManage,
    required this.busy,
    required this.onEnableChanged,
    required this.onAutoImportChanged,
    required this.scanning,
    required this.onScanAll,
  });

  final AdminTrustedMount mount;
  final _MountLibraryState state;
  final bool canManage;
  final bool busy;
  final ValueChanged<bool>? onEnableChanged;
  final ValueChanged<bool>? onAutoImportChanged;
  final bool scanning;
  final VoidCallback? onScanAll;

  String _statusLabel(AppLocalizations l10n) {
    if (state.isPartial) {
      return l10n.adminMountLibraryStatusPartial;
    }
    return state.enabled
        ? l10n.adminMountLibraryStatusOn
        : l10n.adminMountLibraryStatusOff;
  }

  AdminTagTone _statusTone() {
    if (state.isPartial) {
      return AdminTagTone.warning;
    }
    return state.enabled ? AdminTagTone.success : AdminTagTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final canToggle = canManage && mount.available && !busy;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: context.adminColors.surfaceContainerLow.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              state.isPartial
                  ? theme.colorScheme.outlineVariant
                  : context.adminColors.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.dns_outlined,
                size: 20,
                color:
                    mount.available
                        ? context.adminColors.success
                        : context.adminColors.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mount.mountKey,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AdminStatusTag(
                label: healthStatusLabel(
                  l10n,
                  mount.available ? 'AVAILABLE' : 'UNAVAILABLE',
                ),
                tone:
                    mount.available
                        ? AdminTagTone.success
                        : AdminTagTone.warning,
              ),
              const SizedBox(width: 8),
              AdminStatusTag(label: _statusLabel(l10n), tone: _statusTone()),
              if (busy) ...[
                const SizedBox(width: 12),
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.adminMountLibraryCatalogLabel,
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final root in _mountCatalogSlots)
                _CatalogChip(
                  label: _mountCatalogLabel(l10n, root),
                  present: state.presentRoots.contains(root),
                  enabled: state.provisioned,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.isPartial
                ? l10n.adminMountLibraryPartialHint(state.sourceCount)
                : state.provisioned
                ? l10n.adminMountLibraryEnableHint
                : l10n.adminMountLibraryEnableHintOff,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.adminMountLibraryEnable),
              // 库不完整时呈现为关闭，打开会补齐缺失的类型库，避免「已打开却无法补齐」。
              value: state.isPartial ? false : state.enabled,
              onChanged: canToggle ? onEnableChanged : null,
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.adminMountLibraryAutoImport),
              subtitle: Text(
                l10n.adminMountLibraryAutoImportHint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.autoImport,
              onChanged:
                  canToggle && state.enabled ? onAutoImportChanged : null,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: TextButton.icon(
                onPressed:
                    canManage &&
                            mount.available &&
                            state.provisioned &&
                            state.sourceIds.isNotEmpty &&
                            !busy &&
                            !scanning
                        ? onScanAll
                        : null,
                icon:
                    scanning
                        ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.manage_search_rounded, size: 18),
                label: Text(l10n.adminMountLibraryScanAll),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogChip extends StatelessWidget {
  const _CatalogChip({
    required this.label,
    required this.present,
    required this.enabled,
  });

  final String label;
  final bool present;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        present
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              present
                  ? theme.colorScheme.primary.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        color:
            present
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            present ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: present ? theme.colorScheme.onSurface : color,
              fontWeight: present ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
