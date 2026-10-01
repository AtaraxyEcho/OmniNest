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
  return showWorkstationConfirmDialog(
    context,
    title: l10n.adminStorageDisableConfirmTitle,
    message: l10n.adminStorageDisableConfirmBody(location.name),
    confirmLabel: l10n.adminStorageDisableAction,
  );
}

/// 删除挂载位置前确认。
Future<bool> _confirmDeleteStorage(
  BuildContext context,
  AppLocalizations l10n,
  AdminStorageLocation location,
) async {
  return showWorkstationConfirmDialog(
    context,
    title: l10n.adminStorageDeleteConfirmTitle,
    message: l10n.adminStorageDeleteConfirmBody(location.name),
    confirmLabel: l10n.adminStorageDeleteAction,
    destructive: true,
  );
}

/// 挂载位置详情弹窗：全量字段 + 启用/停用与删除操作。
void _showStorageLocationDetail(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  AdminStorageLocation location, {
  required bool canManage,
}) {
  showWorkstationDialog<void>(
    context: context,
    builder:
        (dialogContext) => WorkstationDialogFrame(
          title: location.name,
          headerLabel: location.healthStatus,
          width: 500,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailKeyValueRow(
                label: l10n.adminStorageFieldProvider,
                value: providerTypeLabel(l10n, location.providerType),
              ),
              _DetailKeyValueRow(
                label: l10n.adminStorageFieldManagement,
                value: location.managementMode,
                mono: true,
              ),
              _DetailKeyValueRow(
                label: l10n.adminMountKey,
                value: location.mountKey,
                mono: true,
              ),
              _DetailKeyValueRow(
                label: l10n.adminStorageFieldPath,
                value: location.relativeRoot,
                mono: true,
              ),
              _DetailKeyValueRow(
                label: l10n.adminStorageFieldScope,
                value: scopeTypeLabel(l10n, location.scopeType),
              ),
              _DetailKeyValueRow(
                label: l10n.adminStorageFieldNode,
                value: location.nodeId,
                mono: true,
              ),
            ],
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
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
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
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(
          describeUserFacingError(error, l10n: l10n).message,
        ),
        severity: OmniFeedbackSeverity.error,
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
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(
          describeUserFacingError(error, l10n: l10n).message,
        ),
        severity: OmniFeedbackSeverity.error,
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
          minTableWidth: 1240,
          // 两个 48px 图标按钮需 2×48 加余量，默认 168 偏宽。
          actionColumnWidth: 112,
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
              minWidth: 150,
            ),
            AdminListColumn(
              key: 'type',
              label: l10n.adminStorageColumnType,
              minWidth: 96,
            ),
            AdminListColumn(
              key: 'scopeType',
              label: l10n.adminStorageFieldScope,
              minWidth: 100,
            ),
            AdminListColumn(
              key: 'mountKey',
              label: l10n.adminStorageColumnMountKey,
              minWidth: 140,
            ),
            AdminListColumn(
              key: 'nodeId',
              label: l10n.adminStorageFieldNode,
              minWidth: 120,
            ),
            AdminListColumn(
              key: 'root',
              label: l10n.adminStorageColumnRoot,
              flex: 3,
            ),
            AdminListColumn(
              key: 'status',
              label: l10n.adminFilterStatus,
              minWidth: 100,
            ),
            AdminListColumn(
              key: 'health',
              label: l10n.adminStorageColumnHealth,
              minWidth: 100,
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
                scopeTypeLabel(l10n, location.scopeType),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              AdminCellText(
                location.mountKey,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // 节点 ID 短码：mono 前 8 位，悬停展示完整值；单节点部署
              // 亦保留该列，便于与多节点拓扑对齐。
              AdminCellText(
                location.nodeId.length >= 8
                    ? location.nodeId.substring(0, 8)
                    : location.nodeId,
                tooltipMessage:
                    location.nodeId.isEmpty ? null : location.nodeId,
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelSmall,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
              AdminRowIconAction(
                tooltip: l10n.adminStorageOpenDetail,
                icon: Icons.info_outlined,
                onTap:
                    () => _showStorageLocationDetail(
                      context,
                      ref,
                      l10n,
                      location,
                      canManage: canManageStorage,
                    ),
              ),
              if (canManageStorage)
                AdminRowIconAction(
                  tooltip: l10n.adminStorageDeleteAction,
                  icon: Icons.delete_outline,
                  color: context.adminColors.error,
                  onTap:
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
