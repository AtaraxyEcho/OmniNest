part of 'admin_operations_pages.dart';

/// 维护与审计页：全站分享、照片地理库维护与不可用影视源。
///
/// 三个面板分别依赖 `system:user:manage`、`photo:admin`、`media:library:manage`，
/// 无对应权限的面板不渲染；分区本身只要具备任一权限即可进入。
class AdminMaintenancePage extends ConsumerWidget {
  const AdminMaintenancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final panels = <Widget>[
      if (permissions.contains('system:user:manage')) const _ShareAuditPanel(),
      if (permissions.contains('photo:admin')) const _PhotoGeoPanel(),
      if (permissions.contains('media:library:manage'))
        const _UnavailableMediaPanel(),
    ];
    return _PageEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminMaintenanceTitle,
          subtitle: l10n.adminMaintenanceSubtitle,
        ),
        const SizedBox(height: 24),
        if (panels.isEmpty)
          AdminInfoPanel(
            title: l10n.adminMaintenanceTitle,
            subtitle: l10n.adminMaintenanceSubtitle,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(l10n.adminMaintenanceNoPermission),
              ),
            ],
          )
        else
          for (var index = 0; index < panels.length; index++) ...[
            if (index > 0) const SizedBox(height: 20),
            panels[index],
          ],
      ],
    );
  }
}

/// 全站分享链接审计：只读分页列表。
class _ShareAuditPanel extends ConsumerStatefulWidget {
  const _ShareAuditPanel();

  @override
  ConsumerState<_ShareAuditPanel> createState() => _ShareAuditPanelState();
}

class _ShareAuditPanelState extends ConsumerState<_ShareAuditPanel> {
  int _page = 0;
  int _size = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = (page: _page, size: _size);
    final pageAsync = ref.watch(adminShareLinksProvider(query));
    return AdminInfoPanel(
      title: l10n.adminMaintenanceSharesTitle,
      subtitle: l10n.adminMaintenanceSharesSubtitle,
      headerDivider: true,
      trailing: IconButton(
        tooltip: l10n.adminRefresh,
        onPressed: () => ref.invalidate(adminShareLinksProvider(query)),
        icon: const Icon(Icons.refresh_rounded, size: 20),
      ),
      children: [
        pageAsync.when(
          loading: () => const _MaintenanceLoading(rows: 4),
          error:
              (error, _) => AppErrorView(
                message:
                    describeUserFacingError(error, l10n: l10n).displayMessage,
                onRetry: () => ref.invalidate(adminShareLinksProvider(query)),
              ),
          data: (page) {
            if (page.items.isEmpty) {
              return _MaintenanceEmpty(
                message: l10n.adminMaintenanceSharesEmpty,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns:
                        [
                              l10n.adminMaintenanceSharesResource,
                              l10n.adminMaintenanceSharesOwner,
                              l10n.adminMaintenanceSharesStatus,
                              l10n.adminMaintenanceSharesAccess,
                              l10n.adminMaintenanceSharesCreated,
                              l10n.adminMaintenanceSharesExpires,
                            ]
                            .map((label) => DataColumn(label: Text(label)))
                            .toList(),
                    rows: [
                      for (final item in page.items)
                        DataRow(
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                child: Text(
                                  item.resourceName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(item.ownerUsername)),
                            DataCell(
                              Text(_shareStatusLabel(l10n, item.status)),
                            ),
                            DataCell(
                              Text(
                                item.maxAccessCount == null
                                    ? '${item.accessCount}'
                                    : '${item.accessCount}/${item.maxAccessCount}',
                              ),
                            ),
                            DataCell(
                              Text(_maintenanceDate(context, item.createdAt)),
                            ),
                            DataCell(
                              Text(_maintenanceDate(context, item.expiresAt)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                WorkstationPaginationBar(
                  currentPage: page.page,
                  totalPages: page.totalPages,
                  totalElements: page.totalElements,
                  rowsPerPage: _size,
                  onPageChanged: (value) => setState(() => _page = value),
                  onRowsPerPageChanged:
                      (value) => setState(() {
                        _size = value;
                        _page = 0;
                      }),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 照片地理库维护：导入、重载、回填与动态照片回扫。
class _PhotoGeoPanel extends ConsumerStatefulWidget {
  const _PhotoGeoPanel();

  @override
  ConsumerState<_PhotoGeoPanel> createState() => _PhotoGeoPanelState();
}

class _PhotoGeoPanelState extends ConsumerState<_PhotoGeoPanel> {
  bool _busy = false;

  Future<void> _importDataset() async {
    final l10n = AppLocalizations.of(context);
    final input =
        await showWorkstationDialog<({String dumpDate, String sourceHash})>(
          context: context,
          builder: (_) => const _GeoImportDialog(),
        );
    if (input == null || !mounted) {
      return;
    }
    final confirmed = await _confirmMaintenanceAction(
      context,
      title: l10n.adminMaintenanceGeoImport,
      message: l10n.adminMaintenanceGeoConfirmImport,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      () => ref
          .read(adminOperationsActionsProvider)
          .importGeoDataset(
            dumpDate: input.dumpDate,
            sourceHash: input.sourceHash,
          )
          .then((result) => l10n.adminMaintenanceGeoTaskCreated(result.taskId)),
    );
  }

  Future<void> _reloadIndex() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmMaintenanceAction(
      context,
      title: l10n.adminMaintenanceGeoReload,
      message: l10n.adminMaintenanceGeoConfirmReload,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      () => ref
          .read(adminOperationsActionsProvider)
          .reloadGeoIndex()
          .then(
            (version) =>
                version == null
                    ? l10n.adminMaintenanceGeoReloadedEmpty
                    : l10n.adminMaintenanceGeoReloaded(version),
          ),
    );
  }

  Future<void> _backfill() async {
    final l10n = AppLocalizations.of(context);
    final input = await showWorkstationDialog<({int? batchSize})>(
      context: context,
      builder: (_) => const _GeoBackfillDialog(),
    );
    if (input == null || !mounted) {
      return;
    }
    final confirmed = await _confirmMaintenanceAction(
      context,
      title: l10n.adminMaintenanceGeoBackfill,
      message: l10n.adminMaintenanceGeoConfirmBackfill,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      () => ref
          .read(adminOperationsActionsProvider)
          .backfillGeo(batchSize: input.batchSize)
          .then(
            (result) =>
                result.reused
                    ? l10n.adminMaintenanceGeoTaskReused(result.taskId)
                    : l10n.adminMaintenanceGeoTaskCreated(result.taskId),
          ),
    );
  }

  Future<void> _rescanMotion() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmMaintenanceAction(
      context,
      title: l10n.adminMaintenanceMotionRescan,
      message: l10n.adminMaintenanceMotionConfirm,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      () => ref
          .read(adminOperationsActionsProvider)
          .reanalyzeMotionPhotos()
          .then((taskId) => l10n.adminMaintenanceGeoTaskCreated(taskId)),
    );
  }

  Future<void> _run(Future<String> Function() action) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        message,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        describeUserFacingError(error, l10n: l10n).displayMessage,
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminInfoPanel(
      title: l10n.adminMaintenancePhotoTitle,
      subtitle: l10n.adminMaintenancePhotoSubtitle,
      headerDivider: true,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _importDataset,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(l10n.adminMaintenanceGeoImport),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reloadIndex,
              icon: const Icon(Icons.sync_outlined, size: 18),
              label: Text(l10n.adminMaintenanceGeoReload),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _backfill,
              icon: const Icon(Icons.place_outlined, size: 18),
              label: Text(l10n.adminMaintenanceGeoBackfill),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _rescanMotion,
              icon: const Icon(Icons.motion_photos_on_outlined, size: 18),
              label: Text(l10n.adminMaintenanceMotionRescan),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }
}

/// 不可用影视源：只读分页列表。
class _UnavailableMediaPanel extends ConsumerStatefulWidget {
  const _UnavailableMediaPanel();

  @override
  ConsumerState<_UnavailableMediaPanel> createState() =>
      _UnavailableMediaPanelState();
}

class _UnavailableMediaPanelState
    extends ConsumerState<_UnavailableMediaPanel> {
  int _page = 0;
  int _size = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = (page: _page, size: _size);
    final pageAsync = ref.watch(adminUnavailableMediaProvider(query));
    return AdminInfoPanel(
      title: l10n.adminMaintenanceUnavailableTitle,
      subtitle: l10n.adminMaintenanceUnavailableSubtitle,
      headerDivider: true,
      trailing: IconButton(
        tooltip: l10n.adminRefresh,
        onPressed: () => ref.invalidate(adminUnavailableMediaProvider(query)),
        icon: const Icon(Icons.refresh_rounded, size: 20),
      ),
      children: [
        pageAsync.when(
          loading: () => const _MaintenanceLoading(rows: 4),
          error:
              (error, _) => AppErrorView(
                message:
                    describeUserFacingError(error, l10n: l10n).displayMessage,
                onRetry:
                    () => ref.invalidate(adminUnavailableMediaProvider(query)),
              ),
          data: (page) {
            if (page.items.isEmpty) {
              return _MaintenanceEmpty(
                message: l10n.adminMaintenanceUnavailableEmpty,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns:
                        [
                              l10n.adminMaintenanceUnavailableName,
                              l10n.adminMaintenanceUnavailableStatus,
                              l10n.adminMaintenanceUnavailableSince,
                              l10n.adminMaintenanceUnavailableConfirmations,
                            ]
                            .map((label) => DataColumn(label: Text(label)))
                            .toList(),
                    rows: [
                      for (final item in page.items)
                        DataRow(
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(item.availabilityStatus)),
                            DataCell(
                              Text(
                                _maintenanceDate(context, item.missingSince),
                              ),
                            ),
                            DataCell(Text('${item.missingConfirmations}')),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                WorkstationPaginationBar(
                  currentPage: page.page,
                  totalPages: page.totalPages,
                  totalElements: page.totalElements,
                  rowsPerPage: _size,
                  onPageChanged: (value) => setState(() => _page = value),
                  onRowsPerPageChanged:
                      (value) => setState(() {
                        _size = value;
                        _page = 0;
                      }),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 静态占位：维护页可能同屏出现多块面板，加载态不能各挂一个转圈。
class _MaintenanceLoading extends StatelessWidget {
  const _MaintenanceLoading({this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          for (var index = 0; index < rows; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MaintenanceEmpty extends StatelessWidget {
  const _MaintenanceEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmMaintenanceAction(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showWorkstationDialog<bool>(
    context: context,
    dismissible: false,
    builder:
        (dialogContext) => WorkstationDialogFrame(
          title: title,
          body: Text(
            message,
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.coreCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.adminMaintenanceConfirm),
            ),
          ],
        ),
  );
  return confirmed == true;
}

class _GeoImportDialog extends StatefulWidget {
  const _GeoImportDialog();

  @override
  State<_GeoImportDialog> createState() => _GeoImportDialogState();
}

class _GeoImportDialogState extends State<_GeoImportDialog> {
  final TextEditingController _dumpDate = TextEditingController();
  final TextEditingController _sourceHash = TextEditingController();
  bool _showRequired = false;

  @override
  void dispose() {
    _dumpDate.dispose();
    _sourceHash.dispose();
    super.dispose();
  }

  void _submit() {
    final dumpDate = _dumpDate.text.trim();
    if (dumpDate.isEmpty) {
      setState(() => _showRequired = true);
      return;
    }
    Navigator.of(
      context,
    ).pop((dumpDate: dumpDate, sourceHash: _sourceHash.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkstationDialogFrame(
      title: l10n.adminMaintenanceGeoImport,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _dumpDate,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.adminMaintenanceGeoDumpDate,
              hintText: l10n.adminMaintenanceGeoDumpDateHint,
              errorText:
                  _showRequired
                      ? l10n.adminMaintenanceGeoDumpDateRequired
                      : null,
            ),
            onChanged: (_) {
              if (_showRequired) {
                setState(() => _showRequired = false);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sourceHash,
            decoration: InputDecoration(
              labelText: l10n.adminMaintenanceGeoSourceHash,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.adminMaintenanceGeoImport),
        ),
      ],
    );
  }
}

class _GeoBackfillDialog extends StatefulWidget {
  const _GeoBackfillDialog();

  @override
  State<_GeoBackfillDialog> createState() => _GeoBackfillDialogState();
}

class _GeoBackfillDialogState extends State<_GeoBackfillDialog> {
  final TextEditingController _batchSize = TextEditingController();

  @override
  void dispose() {
    _batchSize.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _batchSize.text.trim();
    final parsed = raw.isEmpty ? null : int.tryParse(raw);
    Navigator.of(context).pop((batchSize: parsed?.clamp(1, 1000)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkstationDialogFrame(
      title: l10n.adminMaintenanceGeoBackfill,
      body: TextField(
        controller: _batchSize,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l10n.adminMaintenanceGeoBatchSize,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.adminMaintenanceGeoBackfill),
        ),
      ],
    );
  }
}

String _maintenanceDate(BuildContext context, DateTime? value) {
  if (value == null) {
    return '—';
  }
  return MaterialLocalizations.of(context).formatShortDate(value);
}

String _shareStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'ACTIVE' => l10n.adminMaintenanceShareStatusActive,
    'DISABLED' => l10n.adminMaintenanceShareStatusDisabled,
    'EXPIRED' => l10n.adminMaintenanceShareStatusExpired,
    _ => status,
  };
}
