part of 'admin_operations_pages.dart';

/// 桌面存储台按样例的「用量 / 本地位置 / 外部账号」组织真实后端数据。
class AdminDesktopStorageDashboard extends ConsumerWidget {
  const AdminDesktopStorageDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final storage = ref.watch(adminStorageProvider);
    final external = ref.watch(adminExternalStorageProvider);
    final summary = ref.watch(adminConsoleControllerProvider);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final canManageStorage = permissions.contains('system:config:manage');
    final canManageSources = permissions.contains('media:library:manage');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(
          title: l10n.adminStorageUsageTitle,
          child: summary.when(
            data: (value) => _DesktopStorageUsage(value.storage),
            error:
                (error, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      errorReason(error, l10n),
                      style: DesktopType.caption(DesktopSkin.of(context).bad),
                    ),
                    const SizedBox(height: 8),
                    DesktopLink(
                      label: l10n.coreRetry,
                      onPressed:
                          () => ref.invalidate(adminConsoleControllerProvider),
                    ),
                  ],
                ),
            loading: () => const _DesktopStorageUsageSkeleton(),
          ),
        ),
        const SizedBox(height: 16),
        storage.when(
          data:
              (view) => AdminCard(
                title: l10n.adminLocalStorageLocations,
                subtitle: l10n.adminLocalStorageLocationsSubtitle,
                action: DesktopButton(
                  label: l10n.adminStorageAddAction,
                  icon: DesktopIcons.plus,
                  variant: DesktopButtonVariant.soft,
                  onPressed:
                      canManageStorage
                          ? () => showDesktopDrawer<void>(
                            context,
                            width: 460,
                            builder:
                                (_) => _DesktopStorageLocationDrawer(
                                  mounts: view.trustedMounts,
                                ),
                          )
                          : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (view.locations.isEmpty)
                      _DesktopStorageEmpty(l10n.adminStorageEmptyList),
                    for (var i = 0; i < view.locations.length; i++)
                      _DesktopStorageLocationRow(
                        location: view.locations[i],
                        first: i == 0,
                        canManage: canManageStorage,
                      ),
                    if (canManageSources) ...[
                      const SizedBox(height: 14),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(top: 8),
                        title: Text(
                          l10n.adminStorageAdvancedLibraries,
                          style: DesktopType.rowTitle(
                            DesktopSkin.of(context).text,
                          ),
                        ),
                        children: [
                          _AdminTrustedMountsSection(
                            mounts: view.trustedMounts,
                            canManage: canManageStorage && canManageSources,
                          ),
                          const SizedBox(height: 14),
                          _LibrarySourcesSection(canManage: canManageSources),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          error:
              (error, _) => AdminCard(
                title: l10n.adminLocalStorageLocations,
                child: Text(
                  errorReason(error, l10n),
                  style: DesktopType.caption(DesktopSkin.of(context).bad),
                ),
              ),
          loading:
              () => AdminCard(
                title: l10n.adminLocalStorageLocations,
                child: const AdminListSkeleton(),
              ),
        ),
        const SizedBox(height: 16),
        _DesktopExternalAccountsCard(
          external: external,
          canManage: permissions.contains('system:config:manage'),
        ),
      ],
    );
  }
}

class _DesktopStorageUsageSkeleton extends StatelessWidget {
  const _DesktopStorageUsageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DesktopSkeletonBox(width: 180, height: 54, radius: 10),
        const SizedBox(height: 14),
        const DesktopSkeletonBox(height: 14, radius: 7),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (var index = 0; index < 4; index++)
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    DesktopSkeletonBox(width: 8, height: 8, index: index),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DesktopSkeletonBox(width: 96, index: index + 1),
                    ),
                    const SizedBox(width: 18),
                    DesktopSkeletonBox(width: 52, index: index + 2),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DesktopStorageUsage extends StatefulWidget {
  const _DesktopStorageUsage(this.stats);

  final AdminStorageStats? stats;

  @override
  State<_DesktopStorageUsage> createState() => _DesktopStorageUsageState();
}

class _DesktopStorageUsageState extends State<_DesktopStorageUsage> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final value = widget.stats;
    final breakdown =
        value?.categoryBreakdown
            .where((item) => item.usedBytes > 0)
            .toList(growable: false) ??
        const <AdminStorageCategoryMetric>[];
    final breakdownBytes = breakdown.fold<int>(
      0,
      (total, item) => total + item.usedBytes,
    );
    final scale = breakdownBytes <= 0 ? 1 : breakdownBytes;
    final segments = <DesktopChartSegment>[
      for (final item in breakdown)
        DesktopChartSegment(
          flex:
              ((item.usedBytes / scale) * 10000)
                  .round()
                  .clamp(1, 10000)
                  .toInt(),
          color: _categoryColor(item.category),
          label: _categoryLabel(l10n, item.category),
          valueLabel: formatFileSize(item.usedBytes),
          percentLabel: '${(item.usedBytes / scale * 100).toStringAsFixed(1)}%',
        ),
    ];
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final usedParts = formatFileSize(value?.usedBytes ?? 0).split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value == null ? '—' : usedParts.first,
              style: DesktopType.adminStatValue(skin.text),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                value == null
                    ? l10n.adminStorageUsageTotal
                    : '${usedParts.skip(1).join(' ')} · ${l10n.adminStorageUsageTotal}',
                style: DesktopType.caption(skin.text3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        DesktopInteractiveSegmentedBar(
          segments: segments,
          trackColor: skin.raise3,
          height: 14,
          borderRadius: 8,
          hoveredIndex: _hoveredIndex,
          onHoverChanged: (index) {
            if (_hoveredIndex != index) {
              setState(() => _hoveredIndex = index);
            }
          },
        ),
        if (breakdown.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n.desktopStorageNoBreakdown,
            style: DesktopType.caption(skin.text3),
          ),
        ] else ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth - 24) / 2;
              return Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < breakdown.length; i++)
                    SizedBox(
                      width: cellWidth,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.basic,
                        onEnter: (_) {
                          if (_hoveredIndex != i) {
                            setState(() => _hoveredIndex = i);
                          }
                        },
                        onExit: (_) {
                          if (_hoveredIndex == i) {
                            setState(() => _hoveredIndex = null);
                          }
                        },
                        child: AnimatedOpacity(
                          opacity:
                              _hoveredIndex == null || _hoveredIndex == i
                                  ? 1.0
                                  : 0.4,
                          duration:
                              animationsDisabled
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                          child: _StorageUsageCount(
                            label: _categoryLabel(l10n, breakdown[i].category),
                            amount: formatFileSize(breakdown[i].usedBytes),
                            color: _categoryColor(breakdown[i].category),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Color _categoryColor(String category) => switch (category) {
    'video' => DesktopPalette.storageVideo,
    'photos' => DesktopPalette.storagePhotos,
    'music' => DesktopPalette.storageMusic,
    'docs' => DesktopPalette.storageDocuments,
    _ => DesktopPalette.kindText,
  };

  String _categoryLabel(AppLocalizations l10n, String category) =>
      switch (category) {
        'video' => l10n.desktopStorageVideo,
        'photos' => l10n.desktopStoragePhotos,
        'music' => l10n.desktopStorageMusic,
        'docs' => l10n.desktopStorageDocuments,
        _ => l10n.filesCategoryOther,
      };
}

class _StorageUsageCount extends StatelessWidget {
  const _StorageUsageCount({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: DesktopType.caption(skin.text2))),
        const SizedBox(width: 8),
        Text(amount, style: DesktopType.numeric(skin.text3)),
      ],
    );
  }
}

class _DesktopStorageEmpty extends StatelessWidget {
  const _DesktopStorageEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(message, style: DesktopType.caption(skin.text3)),
      ),
    );
  }
}

class _DesktopStorageLocationRow extends ConsumerWidget {
  const _DesktopStorageLocationRow({
    required this.location,
    required this.first,
    required this.canManage,
  });

  final AdminStorageLocation location;
  final bool first;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final healthy = _storageHealthy(location);
    return DesktopHover(
      builder:
          (context, hovered) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: hovered ? skin.raise2 : null,
              border: first ? null : Border(top: BorderSide(color: skin.line)),
            ),
            child: Row(
              children: [
                Icon(Icons.dns_outlined, size: 16, color: skin.text3),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.name,
                        style: DesktopType.rowTitle(skin.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${location.mountKey}:${location.relativeRoot}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.mono(skin.text3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _DesktopStorageTag(
                  label: scopeTypeLabel(l10n, location.scopeType),
                  tone: skin.text2,
                ),
                const SizedBox(width: 6),
                _DesktopStorageTag(
                  label: healthStatusLabel(l10n, location.healthStatus),
                  tone: healthy ? skin.ok : skin.warn,
                ),
                const SizedBox(width: 6),
                DesktopIconButton(
                  icon: DesktopIcons.info,
                  tooltip: l10n.adminStorageOpenDetail,
                  onPressed:
                      () => _showStorageLocationDetail(
                        context,
                        ref,
                        l10n,
                        location,
                        canManage: canManage,
                      ),
                ),
              ],
            ),
          ),
    );
  }
}

class _DesktopStorageTag extends StatelessWidget {
  const _DesktopStorageTag({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
      ),
      child: Text(label, style: DesktopType.chip(skin.text2)),
    );
  }
}

class _DesktopExternalAccountsCard extends ConsumerWidget {
  const _DesktopExternalAccountsCard({
    required this.external,
    required this.canManage,
  });

  final AsyncValue<AdminExternalStorageView> external;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final apps = ref.watch(adminConnectorOAuthAppsProvider);
    return AdminCard(
      title: l10n.adminExternalStorageIntegration,
      subtitle: l10n.adminOAuthAppsSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.adminOAuthAppsTitle,
            style: DesktopType.rowTitle(skin.text),
          ),
          const SizedBox(height: 8),
          apps.when(
            data: (items) {
              return Column(
                children: [
                  for (var i = 0; i < _desktopOAuthProviders.length; i++)
                    _DesktopOAuthProviderRow(
                      connectorCode: _desktopOAuthProviders[i].$1,
                      providerName: _desktopOAuthProviders[i].$2,
                      app:
                          items
                              .where(
                                (item) =>
                                    item.connectorCode ==
                                    _desktopOAuthProviders[i].$1,
                              )
                              .firstOrNull,
                      first: i == 0,
                      canManage: canManage,
                    ),
                ],
              );
            },
            error:
                (error, _) => Text(
                  errorReason(error, l10n),
                  style: DesktopType.caption(skin.bad),
                ),
            loading: () => const AdminListSkeleton(),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.adminConnectionList,
            style: DesktopType.rowTitle(skin.text),
          ),
          const SizedBox(height: 8),
          external.when(
            data: (view) {
              if (view.items.isEmpty) {
                return _DesktopStorageEmpty(l10n.adminNoExternalStorage);
              }
              return Column(
                children: [
                  for (var i = 0; i < view.items.length; i++)
                    _DesktopExternalStorageRow(
                      item: view.items[i],
                      first: i == 0,
                      canManage: canManage,
                    ),
                ],
              );
            },
            error:
                (error, _) => Text(
                  errorReason(error, l10n),
                  style: DesktopType.caption(skin.bad),
                ),
            loading: () => const AdminListSkeleton(),
          ),
        ],
      ),
    );
  }
}

class _DesktopOAuthProviderRow extends StatelessWidget {
  const _DesktopOAuthProviderRow({
    required this.connectorCode,
    required this.providerName,
    required this.app,
    required this.first,
    required this.canManage,
  });

  final String connectorCode;
  final String providerName;
  final AdminConnectorOAuthApp? app;
  final bool first;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, size: 16, color: skin.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(providerName, style: DesktopType.rowTitle(skin.text)),
                Text(
                  app?.clientId ?? l10n.adminOAuthNotConfigured,
                  style:
                      app == null
                          ? DesktopType.caption(skin.text3)
                          : DesktopType.mono(skin.text3),
                ),
              ],
            ),
          ),
          _DesktopStorageTag(
            label:
                app == null
                    ? l10n.adminOAuthNotConfigured
                    : app?.enabled == true
                    ? l10n.adminEnabled
                    : l10n.adminDisabled,
            tone: app?.enabled == true ? skin.ok : skin.text3,
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label: app == null ? l10n.adminConfigure : l10n.adminEdit,
            variant: DesktopButtonVariant.soft,
            onPressed:
                canManage
                    ? () => _showOAuthAppDialog(
                      context,
                      connectorCode: connectorCode,
                      existingApp: app,
                    )
                    : null,
          ),
        ],
      ),
    );
  }
}

class _DesktopExternalStorageRow extends ConsumerWidget {
  const _DesktopExternalStorageRow({
    required this.item,
    required this.first,
    required this.canManage,
  });

  final AdminExternalStorageItem item;
  final bool first;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final active = item.status == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_queue_outlined, size: 16, color: skin.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName, style: DesktopType.rowTitle(skin.text)),
                Text(item.provider, style: DesktopType.caption(skin.text3)),
              ],
            ),
          ),
          _DesktopStorageTag(
            label: active ? l10n.adminEnabled : l10n.adminDisabled,
            tone: active ? skin.ok : skin.text3,
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label: active ? l10n.adminDeactivate : l10n.adminActivate,
            variant: DesktopButtonVariant.ghost,
            onPressed:
                canManage
                    ? () => ref
                        .read(adminOperationsActionsProvider)
                        .updateExternalStorageStatus(
                          item.id,
                          active ? 'DISABLED' : 'ACTIVE',
                        )
                    : null,
          ),
        ],
      ),
    );
  }
}

class _DesktopStorageLocationDrawer extends ConsumerStatefulWidget {
  const _DesktopStorageLocationDrawer({required this.mounts});

  final List<AdminTrustedMount> mounts;

  @override
  ConsumerState<_DesktopStorageLocationDrawer> createState() =>
      _DesktopStorageLocationDrawerState();
}

class _DesktopStorageLocationDrawerState
    extends ConsumerState<_DesktopStorageLocationDrawer> {
  final _nameController = TextEditingController();
  String? _mountKey;
  String _scopeType = 'SYSTEM';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final mountKey = _mountKey;
    if (mountKey == null || _nameController.text.trim().isEmpty) return;
    final scopeId =
        _scopeType == 'USER'
            ? ref.read(authSessionProvider).value?.user?.id
            : null;
    if (_scopeType == 'USER' && scopeId == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .createStorageLocation(
            name: _nameController.text.trim(),
            mountKey: mountKey,
            relativeRoot: '.',
            scopeType: _scopeType,
            scopeId: scopeId,
          );
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).adminStorageCreated,
        severity: OmniFeedbackSeverity.success,
      );
      closeDesktopModal(context, true);
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        errorReason(error, AppLocalizations.of(context)),
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final availableMounts = widget.mounts
        .where((mount) => mount.available)
        .toList(growable: false);
    final mountKey = _mountKey ?? availableMounts.firstOrNull?.mountKey;
    final userId = ref.watch(authSessionProvider).value?.user?.id;
    return DesktopDrawerFrame(
      title: l10n.adminStorageAddLocation,
      eyebrow: l10n.adminStorageSectionLabel,
      footer: Wrap(
        spacing: 8,
        children: [
          DesktopButton(
            label: l10n.coreCancel,
            onPressed: _saving ? null : () => closeDesktopModal(context),
          ),
          DesktopButton(
            label: l10n.adminStorageMountAction,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed:
                _saving ||
                        mountKey == null ||
                        _nameController.text.trim().isEmpty ||
                        (_scopeType == 'USER' && userId == null)
                    ? null
                    : _save,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: skin.raise,
              border: Border.all(color: skin.line),
              borderRadius: BorderRadius.circular(DesktopMetrics.radius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(DesktopIcons.info, size: 15, color: skin.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.adminStorageAddLocationHint,
                    style: DesktopType.caption(skin.text2),
                  ),
                ),
              ],
            ),
          ),
          DesktopTextField(
            controller: _nameController,
            label: l10n.adminStorageDisplayName,
            hint: l10n.adminStorageNameHint,
            required: true,
            autofocus: true,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.adminStorageColumnMountKey,
            style: DesktopType.fieldLabel(skin.text2),
          ),
          const SizedBox(height: 6),
          if (availableMounts.isEmpty)
            Text(
              l10n.adminTrustedMountsEmpty,
              style: DesktopType.caption(skin.text3),
            )
          else
            DesktopSelect<String>(
              value: mountKey!,
              options: [
                for (final mount in availableMounts)
                  DesktopSelectOption(
                    value: mount.mountKey,
                    label: mount.displayName,
                    hint: mount.mountKey,
                  ),
              ],
              onChanged: (value) => setState(() => _mountKey = value),
            ),
          const SizedBox(height: 14),
          Text(
            l10n.adminStorageVisibleTo,
            style: DesktopType.fieldLabel(skin.text2),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopChipButton(
                label: l10n.adminStorageScopeEveryone,
                selected: _scopeType == 'SYSTEM',
                onTap: () => setState(() => _scopeType = 'SYSTEM'),
              ),
              DesktopChipButton(
                label: l10n.adminStorageScopeOneUser,
                selected: _scopeType == 'USER',
                onTap: () => setState(() => _scopeType = 'USER'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
