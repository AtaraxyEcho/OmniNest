part of 'admin_operations_pages.dart';

enum _StorageStatusFilter { all, enabled, disabled, unhealthy }

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
        SnackBar(content: Text(l10n.adminLoadFailed(error.toString()))),
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
        SnackBar(content: Text(l10n.adminLoadFailed(error.toString()))),
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
    // 库源变化（含挂载直达新建/删除）可能新增或移除挂载位置引用，
    // 同步刷新存储管理视图，避免非 autoDispose 的 adminStorageProvider 陈旧。
    ref.listen(videoLibrarySourcesProvider, (previous, next) {
      ref.invalidate(adminStorageProvider);
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
      trailing: [
        if (canManageStorage)
          FilledButton.tonalIcon(
            onPressed:
                () => showDialog<void>(
                  context: context,
                  builder:
                      (context) => _StorageLocationWizard(
                        mounts: widget.view.trustedMounts,
                      ),
                ),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.adminAddLocalStorageLocation),
          ),
      ],
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
              Text(
                location.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                providerTypeLabel(l10n, location.providerType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                location.mountKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                location.relativeRoot,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  tooltip:
                      location.enabled
                          ? l10n.adminStorageDisableAction
                          : l10n.adminStatusEnabled,
                  icon: Icon(
                    location.enabled
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 20,
                  ),
                  onPressed:
                      () => _toggleStorageLocation(
                        context,
                        ref,
                        l10n,
                        location,
                        enabled: !location.enabled,
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
                onPressed: () => ref.invalidate(adminStorageProvider),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: l10n.adminRefresh,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _AdminTrustedMountsSection(mounts: widget.view.trustedMounts),
        const SizedBox(height: 24),
        listSection,
        const SizedBox(height: 32),
        _LibrarySourcesSection(canManage: canManageSources),
      ],
    );
  }
}

/// 可信挂载点健康卡：展示部署白名单层的挂载键与当前节点可用性，
/// 使四层链路（部署配置→位置→库源→扫描）最底层的状态可观测。
class _AdminTrustedMountsSection extends StatelessWidget {
  const _AdminTrustedMountsSection({required this.mounts});

  final List<AdminTrustedMount> mounts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminTableSection(
      title: l10n.adminTrustedMountsTitle,
      subtitle: l10n.adminTrustedMountsSubtitle,
      children: [
        if (mounts.isEmpty)
          _EmptyText(l10n.adminTrustedMountsEmpty)
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final mount in mounts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.adminColors.surfaceContainerLow.withValues(
                        alpha: 0.42,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.adminColors.outlineVariant.withValues(
                          alpha: 0.18,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          mount.available
                              ? Icons.dns_outlined
                              : Icons.dns_outlined,
                          size: 18,
                          color:
                              mount.available
                                  ? context.adminColors.success
                                  : context.adminColors.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mount.mountKey,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
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
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StorageLocationWizard extends ConsumerStatefulWidget {
  const _StorageLocationWizard({required this.mounts});

  final List<AdminTrustedMount> mounts;

  @override
  ConsumerState<_StorageLocationWizard> createState() =>
      _StorageLocationWizardState();
}

class _StorageLocationWizardState
    extends ConsumerState<_StorageLocationWizard> {
  final _nameController = TextEditingController();
  String? _mountKey;
  String? _parent;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mountKey =
        widget.mounts.where((mount) => mount.available).firstOrNull?.mountKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final mountKey = _mountKey;
    final relativeRoot = _parent ?? '.';
    if (name.isEmpty || mountKey == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .createStorageLocation(
            name: name,
            mountKey: mountKey,
            relativeRoot: relativeRoot,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminLoadFailed(error.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = _parent ?? '.';
    return AlertDialog(
      title: Text(l10n.adminAddLocalStorageLocation),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.adminDisplayNameLabel,
              ),
            ),
            const SizedBox(height: 14),
            AppDropdown<String>(
              value: _mountKey ?? '',
              items: [
                for (final mount in widget.mounts)
                  AppDropdownItem(
                    value: mount.mountKey,
                    label:
                        mount.available
                            ? mount.displayName
                            : '${mount.displayName} (${mount.mountKey})',
                    enabled: mount.available,
                  ),
              ],
              onChanged:
                  _saving
                      ? null
                      : (value) {
                        setState(() {
                          _mountKey = value!;
                          _parent = null;
                        });
                      },
              label: l10n.adminMountKey,
              helperText: l10n.adminMountKeyHint,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  l10n.adminStorageFieldPath,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: l10n.coreBack,
                  onPressed:
                      current != '.' && !_saving
                          ? () => setState(() {
                            final separator = current.lastIndexOf('/');
                            _parent =
                                separator < 0
                                    ? null
                                    : current.substring(0, separator);
                          })
                          : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Builder(
                  builder: (context) {
                    final directoryAsync = ref.watch(
                      adminMountDirectoriesProvider((
                        mountKey: _mountKey ?? '',
                        parent: _parent,
                      )),
                    );
                    return directoryAsync.when(
                      loading:
                          () => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      error:
                          (error, _) => Center(
                            child: Text(l10n.adminLoadFailed(error.toString())),
                          ),
                      data:
                          (directories) =>
                              directories.isEmpty
                                  ? Center(child: Text(l10n.adminNoSubfolders))
                                  : ListView.builder(
                                    itemCount: directories.length,
                                    itemBuilder: (context, index) {
                                      final directory = directories[index];
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.folder_outlined,
                                          size: 20,
                                        ),
                                        title: Text(
                                          directory.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          directory.relativePath,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap:
                                            _saving
                                                ? null
                                                : () => setState(
                                                  () =>
                                                      _parent =
                                                          directory
                                                              .relativePath,
                                                ),
                                      );
                                    },
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
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.adminUseCurrentFolder),
        ),
      ],
    );
  }
}
