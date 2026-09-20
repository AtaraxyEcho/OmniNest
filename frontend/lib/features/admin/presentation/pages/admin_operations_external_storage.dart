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
    final activeCount =
        view.items.where((item) => item.status == 'ACTIVE').length;
    return AdminSectionEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminExternalStorageIntegration,
          subtitle: l10n.adminExternalStorageSubtitle,
          // 统计内联到标题行，替代冗余的指标卡网格。
          trailing: Wrap(
            spacing: 8,
            children: [
              AdminMetricMiniStat(
                label: l10n.adminConnections,
                value: view.items.length.toString(),
              ),
              AdminMetricMiniStat(
                label: l10n.adminEnabled,
                value: activeCount.toString(),
                color: adminColors.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AdminInfoPanel(
          title: l10n.adminOAuthAppsTitle,
          subtitle: l10n.adminOAuthAppsSubtitle,
          trailing: FilledButton.tonalIcon(
            onPressed: () => _showOAuthAppDialog(context),
            icon: const Icon(Icons.vpn_key_outlined),
            label: Text(l10n.adminSave),
          ),
          children: [
            Consumer(
              builder: (context, ref, _) {
                final apps = ref.watch(adminConnectorOAuthAppsProvider);
                return apps.when(
                  loading: () => const _EmptyText('…'),
                  error:
                      (error, _) => _EmptyText(
                        describeUserFacingError(error, l10n: l10n).message,
                      ),
                  data:
                      (items) =>
                          items.isEmpty
                              ? _EmptyText(l10n.adminNoOAuthApps)
                              : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final app in items)
                                    _InfoRow(
                                      leading: app.connectorCode,
                                      middle:
                                          '${app.clientId}\n${app.redirectUri}',
                                      trailing: AdminStatusPill(
                                        label:
                                            app.enabled
                                                ? l10n.adminEnabled
                                                : l10n.adminDisabled,
                                        color:
                                            app.enabled
                                                ? adminColors.success
                                                : adminColors.tertiary,
                                      ),
                                    ),
                                ],
                              ),
                );
              },
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

/// 后端已实现 OAuth 授权流的连接器类型；编码与账号侧外部存储对话框保持一致。
const List<AppDropdownItem<String>> _oauthConnectorItems = [
  AppDropdownItem<String>(value: 'ONEDRIVE', label: 'OneDrive'),
  AppDropdownItem<String>(value: 'GDRIVE', label: 'Google Drive'),
  AppDropdownItem<String>(value: 'DROPBOX', label: 'Dropbox'),
];

Future<void> _showOAuthAppDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _OAuthAppDialog(),
  );
}

/// OAuth 应用编辑对话框。
///
/// 控制器由 Dialog State 持有并在 dispose 释放。旧实现把控制器留在函数
/// 作用域内、await showDialog 返回后立即 dispose，而对话框退场动画期间
/// TextField 仍会访问控制器，触发 used after disposed 断言并连带布局溢出。
class _OAuthAppDialog extends ConsumerStatefulWidget {
  const _OAuthAppDialog();

  @override
  ConsumerState<_OAuthAppDialog> createState() => _OAuthAppDialogState();
}

class _OAuthAppDialogState extends ConsumerState<_OAuthAppDialog> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _redirectController = TextEditingController();
  String _connectorCode = 'ONEDRIVE';
  bool _enabled = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _redirectController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .saveConnectorOAuthApp(
            connectorCode: _connectorCode,
            clientId: _clientIdController.text.trim(),
            clientSecret: _clientSecretController.text.trim(),
            redirectUri: _redirectController.text.trim(),
            enabled: _enabled,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = describeUserFacingError(error, l10n: l10n).message;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminOAuthAppsTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDropdown<String>(
                value: _connectorCode,
                items: _oauthConnectorItems,
                onChanged:
                    (value) =>
                        setState(() => _connectorCode = value ?? 'ONEDRIVE'),
                label: l10n.adminType,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientIdController,
                decoration: InputDecoration(
                  labelText: l10n.adminExternalStorageClientId,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientSecretController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.adminExternalStorageClientSecret,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _redirectController,
                decoration: InputDecoration(
                  labelText: l10n.adminExternalStorageRedirectUri,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              // 紧凑单行开关，避免 SwitchListTile 在宽对话框中把标签与开关拉开。
              Row(
                children: [
                  Expanded(child: Text(l10n.adminEnabled)),
                  Switch(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.adminColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? l10n.adminSaving : l10n.adminSave),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  /// 单卡固定高度；内容较多的页面（如监控页含 supporting 行）可调大。

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
          mainAxisExtent: 128 * textScale,
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
    'WARN' => adminColors.warning,
    'DOWN' || 'FAILED' || 'DLQ' || 'DISABLED' => adminColors.error,
    'RUNNING' => adminColors.info,
    _ => adminColors.tertiary,
  };
}
