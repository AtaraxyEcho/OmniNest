part of 'admin_operations_pages.dart';

class AdminExternalStoragePage extends ConsumerWidget {
  const AdminExternalStoragePage({required this.view, super.key});

  final AdminExternalStorageView view;

  /// 管理端只展示所有者短标识，避免整段 UUID 撑破信息行。
  String _shortId(String id) {
    if (id.length <= 8) {
      return id.isEmpty ? '-' : id;
    }
    return id.substring(0, 8);
  }

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
                                      // clientId 为长技术标识：mono 展示，
                                      // 截断时悬停可见完整值。
                                      middleChild: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AdminCellText(
                                            app.clientId,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTypography.monoFamily,
                                              fontFamilyFallback:
                                                  AppTypography
                                                      .monoFamilyFallback,
                                              fontSize: AppTypography.bodySmall,
                                              height: 16 / 12,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            app.redirectUri,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall?.copyWith(
                                              color:
                                                  context
                                                      .adminColors
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
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
                        // Provider 编码上浮为标题行 mono 徽标，与样板实例行一致。
                        codeBadge: item.provider,
                        // 所有者 ID 以 mono 短码呈现，与列表类页面的
                        // 技术标识展示形态一致。
                        middleChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                text: '${l10n.adminExternalStorageOwner} ',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: context.adminColors.onSurfaceVariant,
                                ),
                                children: [
                                  TextSpan(
                                    text: _shortId(item.ownerUserId),
                                    style: TextStyle(
                                      fontFamily: AppTypography.monoFamily,
                                      fontFamilyFallback:
                                          AppTypography.monoFamilyFallback,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.updatedAt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: context.adminColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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
  return showWorkstationDialog<void>(
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
  String? _lastGeneratedRedirect;

  @override
  void initState() {
    super.initState();
    // 回调地址预填属于一次性副作用，避开 build 与 initState 的 ref 限制。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(_syncRedirectPrefill);
      }
    });
  }

  /// 根据当前 API 基地址推导该连接器的 OAuth 回调地址。
  String? _callbackUri() {
    final base = ref.read(appEnvironmentProvider)?.apiBaseUrl;
    if (base == null || base.isEmpty) {
      return null;
    }
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalized/external-connectors/$_connectorCode/oauth/callback';
  }

  /// 空值或仍是上次自动生成值时刷新预填；用户手动改写过则不覆盖。
  void _syncRedirectPrefill() {
    final generated = _callbackUri();
    if (generated == null) {
      return;
    }
    final current = _redirectController.text.trim();
    if (current.isEmpty || current == _lastGeneratedRedirect) {
      _lastGeneratedRedirect = generated;
      _redirectController.text = generated;
    }
  }

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
    return WorkstationDialogFrame(
      title: l10n.adminOAuthAppsTitle,
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDropdown<String>(
            value: _connectorCode,
            items: _oauthConnectorItems,
            onChanged:
                (value) => setState(() {
                  _connectorCode = value ?? 'ONEDRIVE';
                  _syncRedirectPrefill();
                }),
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
              helperText: l10n.adminOAuthRedirectHint,
              helperMaxLines: 2,
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          // 工位开关行：label 左、开关右，整行可点，替代 Material 胶囊开关。
          WorkstationToggle(
            label: l10n.adminEnabled,
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.adminColors.error),
            ),
          ],
        ],
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
  const _MetricGrid({
    required this.children,
    this.maxColumns = 3,
    this.cardExtent = 128,
  });

  final List<Widget> children;

  /// 列数上限：默认 3 列（>=560 断点）；传 4 时宽屏走 4 列、中屏 2 列。
  final int maxColumns;

  /// 单卡固定高度；内容较多的页面（如含 supporting 行的分布卡）可调大。

  final double cardExtent;

  @override
  Widget build(BuildContext context) {
    // 单卡高度随字体档位放大，115%/130% 下标题、数值与 supporting 行不溢出。
    final textScale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            maxColumns >= 4
                ? (width >= 1080 ? 4 : (width >= 560 ? 2 : 1))
                : (width >= 560 ? 3 : 1);
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: cardExtent * textScale,
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
    required this.trailing,
    this.middle,
    this.codeBadge,
    this.titleTrailing,
    this.middleChild,
  });

  final String leading;

  /// 中部说明文本；传入 [middleChild] 时忽略。
  final String? middle;
  final Widget trailing;

  /// 标题右侧的等宽代码徽标（如角色编码、Provider 编码）。
  final String? codeBadge;

  /// 标题行内追加的徽标/统计区（紧跟 codeBadge，窄屏自动换行）。
  final Widget? titleTrailing;

  /// 自定义中部内容；传入时忽略 [middle] 文本。
  final Widget? middleChild;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              // 标题行改为 Wrap：名称、code 徽标与统计同行排布，窄屏自然换行。
              final titleRow = Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    leading,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (codeBadge != null) _MonoCodeBadge(codeBadge!),
                  if (titleTrailing != null) titleTrailing!,
                ],
              );
              final middleContent =
                  middleChild ??
                  Text(
                    middle ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.adminColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  );
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [titleRow, const SizedBox(height: 5), middleContent],
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

/// 需要以 GB 为单位展示的字节类配置键。
const _gbValueConfigs = {'storage.quota.default', 'storage.quota.default.gb'};

const _byteToGbDisplayConfigs = {'share.max-bytes', 'shared_space.max_bytes'};

/// 需要以 MB 为单位展示的字节类配置键；存储值仍是字节。
const _byteToMbDisplayConfigs = {
  'backdrop.max-image-bytes',
  'backdrop.max-video-bytes',
};

/// 将配置值格式化。
String _formatConfigValue(String key, String value) {
  if (_gbValueConfigs.contains(key)) {
    final gb = double.tryParse(value);
    return gb == null ? value : '${gb.toStringAsFixed(1)} GB';
  }
  if (_byteToMbDisplayConfigs.contains(key)) {
    final bytes = int.tryParse(value) ?? 0;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (!_byteToGbDisplayConfigs.contains(key)) return value;
  final bytes = int.tryParse(value) ?? 0;
  final gb = bytes / (1024 * 1024 * 1024);
  return '${gb.toStringAsFixed(1)} GB';
}
