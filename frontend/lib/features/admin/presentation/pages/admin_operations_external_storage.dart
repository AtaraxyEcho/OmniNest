part of 'admin_operations_pages.dart';

class AdminExternalStoragePage extends ConsumerWidget {
  const AdminExternalStoragePage({required this.view, super.key});

  final AdminExternalStorageView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final filtered =
        query.isEmpty
            ? view.items
            : view.items
                .where(
                  (item) =>
                      item.displayName.toLowerCase().contains(query) ||
                      item.provider.toLowerCase().contains(query),
                )
                .toList();
    return _PageEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminExternalStorageIntegration,
          subtitle: l10n.adminExternalStorageSubtitle,
          trailing: FilledButton.icon(
            onPressed:
                () => showDialog<void>(
                  context: context,
                  builder: (context) => const _ExternalStorageDialog(),
                ),
            icon: const Icon(Icons.add_link_rounded),
            label: Text(l10n.adminNewConnection),
          ),
        ),
        const SizedBox(height: 24),
        _MetricGrid(
          children: [
            AdminMetricCard(
              title: l10n.adminConnections,
              value: view.items.length.toString(),
              detail: l10n.adminExternalSources,
              icon: Icons.add_to_drive_outlined,
            ),
            AdminMetricCard(
              title: l10n.adminEnabled,
              value:
                  view.items
                      .where((item) => item.status == 'ACTIVE')
                      .length
                      .toString(),
              detail: l10n.adminSyncable,
              icon: Icons.link_rounded,
              accent: adminColors.success,
            ),
            AdminMetricCard(
              title: l10n.adminDisabled,
              value:
                  view.items
                      .where((item) => item.status == 'DISABLED')
                      .length
                      .toString(),
              detail: l10n.adminPausedSync,
              icon: Icons.link_off_rounded,
              accent: context.adminColors.tertiary,
            ),
          ],
        ),
        const SizedBox(height: 24),
        AdminInfoPanel(
          title: l10n.adminConnectionList,
          subtitle: l10n.adminConnectionListSubtitle,
          children:
              filtered.isEmpty
                  ? [
                    _EmptyText(
                      query.isEmpty
                          ? l10n.adminNoExternalStorage
                          : l10n.adminNoMatch,
                    ),
                  ]
                  : [
                    for (final item in filtered)
                      _InfoRow(
                        leading: item.displayName,
                        middle: '${item.provider}\n${item.updatedAt}',
                        trailing: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AdminStatusPill(
                              label: item.status,
                              color:
                                  item.status == 'ACTIVE'
                                      ? adminColors.success
                                      : context.adminColors.tertiary,
                            ),
                            FilledButton.tonalIcon(
                              onPressed:
                                  () => ref
                                      .read(adminOperationsActionsProvider)
                                      .updateExternalStorageStatus(
                                        item.id,
                                        item.status == 'ACTIVE'
                                            ? 'DISABLED'
                                            : 'ACTIVE',
                                      ),
                              icon: Icon(
                                item.status == 'ACTIVE'
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                item.status == 'ACTIVE'
                                    ? l10n.adminDeactivate
                                    : l10n.adminActivate,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children, this.mainAxisExtent = 128});

  final List<Widget> children;

  /// 单卡固定高度；内容较多的页面（如监控页含 supporting 行）可调大。
  final double mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    // 单卡高度随字体档位放大，115%/130% 下标题、数值与 supporting 行不溢出。
    final textScale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: mainAxisExtent * textScale,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.leading,
    required this.middle,
    required this.trailing,
  });

  final String leading;
  final String middle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.adminColors.surfaceContainerLow.withValues(
            alpha: 0.42,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.adminColors.outlineVariant.withValues(alpha: 0.18),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    leading,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    middle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.adminColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 18),
                  trailing,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ExternalStorageDialog extends ConsumerStatefulWidget {
  const _ExternalStorageDialog();

  @override
  ConsumerState<_ExternalStorageDialog> createState() =>
      _ExternalStorageDialogState();
}

class _ExternalStorageDialogState
    extends ConsumerState<_ExternalStorageDialog> {
  final _displayNameController = TextEditingController();
  final _credentialsController = TextEditingController(text: '{}');
  String _provider = 'S3';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _credentialsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminNewExternalStorage),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDropdown<String>(
              value: _provider,
              label: l10n.adminType,
              items: [
                const AppDropdownItem(value: 'S3', label: 'S3'),
                const AppDropdownItem(value: 'WEBDAV', label: 'WebDAV'),
                const AppDropdownItem(value: 'SMB', label: 'SMB'),
                AppDropdownItem(value: 'LOCAL', label: l10n.adminLocalMount),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _provider = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: l10n.adminDisplayNameLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _credentialsController,
              decoration: InputDecoration(labelText: l10n.adminCredentialsJson),
              minLines: 3,
              maxLines: 5,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.adminColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.add_link_rounded),
          label: Text(_submitting ? l10n.adminCreatingLabel : l10n.adminCreate),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_displayNameController.text.trim().isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).adminEnterDisplayName,
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .createExternalStorage(
            provider: _provider,
            displayName: _displayNameController.text.trim(),
            credentials: _credentialsController.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.adminColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _detailText(Map<String, dynamic> detail, AppLocalizations l10n) {
  if (detail.isEmpty) {
    return l10n.adminNoDetailDiagnostics;
  }
  return detail.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .take(5)
      .join('\n');
}

Color _usageColor(double value, AdminColors adminColors) {
  if (value >= 85) {
    return adminColors.error;
  }
  if (value >= 70) {
    return adminColors.tertiary;
  }
  return adminColors.success;
}

Color _seriesColor(String metric, AdminColors adminColors) {
  return switch (metric) {
    'cpu' => adminColors.tertiary,
    'memory' => adminColors.info,
    'jvmHeap' => adminColors.primary,
    'tasks' => adminColors.success,
    _ => adminColors.onSurfaceVariant,
  };
}

/// 需要以 GB 为单位展示的字节类配置键。
const _gbValueConfigs = {'storage.quota.default', 'storage.quota.default.gb'};

const _byteToGbDisplayConfigs = {'share.max-bytes', 'shared_space.max_bytes'};

/// 将配置值格式化。
String _formatConfigValue(String key, String value) {
  if (_gbValueConfigs.contains(key)) {
    final gb = double.tryParse(value);
    return gb == null ? value : '${gb.toStringAsFixed(1)} GB';
  }
  if (!_byteToGbDisplayConfigs.contains(key)) return value;
  final bytes = int.tryParse(value) ?? 0;
  final gb = bytes / (1024 * 1024 * 1024);
  return '${gb.toStringAsFixed(1)} GB';
}

Color _statusColor(String status, AdminColors adminColors) {
  return switch (status) {
    'UP' || 'ACTIVE' || 'COMPLETED' => adminColors.success,
    'WARN' || 'FAILED' || 'DLQ' || 'DISABLED' => adminColors.error,
    'RUNNING' => adminColors.info,
    _ => adminColors.tertiary,
  };
}
