part of 'admin_operations_pages.dart';

class AdminConfigPage extends ConsumerStatefulWidget {
  const AdminConfigPage({required this.view, super.key});

  final AdminConfigManagementView view;

  @override
  ConsumerState<AdminConfigPage> createState() => _AdminConfigPageState();
}

class _AdminConfigPageState extends ConsumerState<AdminConfigPage> {
  int _page = 0;
  int _pageSize = 10;
  String _groupFilter = 'ALL';
  AdminListSort? _configSort;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String>(adminSearchProvider, (_, _) {
      if (!mounted) return;
      setState(() => _page = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final all =
        widget.view.items
            .where((item) => !_isRemovedConfigKey(item.key))
            .toList()
          ..sort((a, b) {
            final groupOrder = _configGroupOrder(
              a,
            ).compareTo(_configGroupOrder(b));
            if (groupOrder != 0) {
              return groupOrder;
            }
            return a.key.compareTo(b.key);
          });
    final groupNames =
        all.map((item) => _configGroup(l10n, item)).toSet().toList()..sort();
    final groupFiltered =
        _groupFilter == 'ALL'
            ? all
            : all
                .where((item) => _configGroup(l10n, item) == _groupFilter)
                .toList();
    final searched =
        query.isEmpty
            ? groupFiltered
            : groupFiltered.where((item) {
              return item.key.toLowerCase().contains(query) ||
                  _configTitle(l10n, item).toLowerCase().contains(query);
            }).toList();
    final sorted = _applySort(searched, l10n);
    final totalPages = (sorted.length / _pageSize).ceil();
    final currentPage = totalPages == 0 ? 0 : _page.clamp(0, totalPages - 1);
    final pageItems =
        sorted.skip(currentPage * _pageSize).take(_pageSize).toList();

    return _PageEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminConfigCenter,
          subtitle: l10n.adminConfigCenterSubtitle,
          trailing: Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminStatusPill(
                label: l10n.adminConfigGroupItemCount(sorted.length),
              ),
              IconButton.filledTonal(
                onPressed: () => ref.invalidate(adminConfigsProvider),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: l10n.adminConfigRefresh,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            AppDropdown<String>(
              width: AppControlTokens.filterFieldWidth,
              dense: true,
              label: l10n.adminConfigGroupColumn,
              value: _groupFilter,
              items: [
                AppDropdownItem(value: 'ALL', label: l10n.adminAll),
                for (final name in groupNames)
                  AppDropdownItem(value: name, label: name),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _groupFilter = value;
                    _page = 0;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminTableSection(
          title: l10n.adminConfigItemList,
          subtitle: l10n.adminConfigItemListSubtitle,
          children: [
            AdminDataTable(
              showIndex: true,
              indexBase: currentPage * _pageSize,
              minTableWidth: 1040,
              sort: _configSort,
              onSort:
                  (key, ascending) => setState(() {
                    _configSort = AdminListSort(
                      columnKey: key,
                      ascending: ascending,
                    );
                  }),
              columns: [
                AdminListColumn(
                  key: 'group',
                  label: l10n.adminConfigGroupColumn,
                  minWidth: 120,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'name',
                  label: l10n.adminConfigItems,
                  flex: 2,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'description',
                  label: l10n.adminConfigDescription,
                  flex: 3,
                ),
                AdminListColumn(
                  key: 'value',
                  label: l10n.adminConfigValue,
                  flex: 2,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'updatedAt',
                  label: l10n.adminTaskUpdatedAt,
                  minWidth: 150,
                  sortable: true,
                ),
              ],
              rowCount: pageItems.length,
              emptyState: AdminListEmptyState(
                message:
                    query.isEmpty && _groupFilter == 'ALL'
                        ? l10n.adminNoConfigItems
                        : l10n.adminNoMatch,
              ),
              rowCellsBuilder: (context, index) {
                final item = pageItems[index];
                final summary = _configValueSummary(l10n, item);
                return [
                  Text(
                    _configGroup(l10n, item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _configTitle(l10n, item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _configDescription(l10n, item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Tooltip(
                    message: summary,
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    item.updatedAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ];
              },
              actionsBuilder: (context, index) {
                final entry = pageItems[index];
                return [
                  IconButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => _ConfigHistoryDialog(
                                configKey: entry.key,
                                configLabel: _configTitle(l10n, entry),
                              ),
                        ),
                    icon: const Icon(Icons.history_rounded, size: 20),
                    tooltip: l10n.adminConfigHistory,
                  ),
                  IconButton(
                    onPressed:
                        entry.editable
                            ? () => showDialog<void>(
                              context: context,
                              builder: (_) => _ConfigEditDialog(entry: entry),
                            )
                            : null,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: l10n.adminEdit,
                  ),
                ];
              },
            ),
            const SizedBox(height: 12),
            AdminListPaginationBar(
              currentPage: currentPage,
              totalPages: totalPages == 0 ? 1 : totalPages,
              totalElements: sorted.length,
              rowsPerPage: _pageSize,
              onPageChanged: (next) => setState(() => _page = next),
              onRowsPerPageChanged: _changePageSize,
            ),
          ],
        ),
      ],
    );
  }

  /// 客户端排序：按列键比较，平局时回退默认的模块与键顺序。
  List<AdminConfigEntry> _applySort(
    List<AdminConfigEntry> items,
    AppLocalizations l10n,
  ) {
    final sort = _configSort;
    if (sort == null) {
      return items;
    }
    int compare(AdminConfigEntry a, AdminConfigEntry b) {
      final int result = switch (sort.columnKey) {
        'group' => _configGroup(l10n, a).compareTo(_configGroup(l10n, b)),
        'name' => _configTitle(l10n, a).compareTo(_configTitle(l10n, b)),
        'value' => _configValueSummary(
          l10n,
          a,
        ).compareTo(_configValueSummary(l10n, b)),
        'updatedAt' => a.updatedAt.compareTo(b.updatedAt),
        _ => 0,
      };
      if (result != 0) {
        return result;
      }
      final groupOrder = _configGroupOrder(a).compareTo(_configGroupOrder(b));
      if (groupOrder != 0) {
        return groupOrder;
      }
      return a.key.compareTo(b.key);
    }

    return items
      ..sort((a, b) => sort.ascending ? compare(a, b) : compare(b, a));
  }

  /// 调整每页条数：重置回第一页。
  void _changePageSize(int size) {
    setState(() {
      _pageSize = size;
      _page = 0;
    });
  }
}

class _ConfigEditDialog extends ConsumerStatefulWidget {
  const _ConfigEditDialog({required this.entry});

  final AdminConfigEntry entry;

  @override
  ConsumerState<_ConfigEditDialog> createState() => _ConfigEditDialogState();
}

class _ConfigEditDialogState extends ConsumerState<_ConfigEditDialog> {
  late final TextEditingController _valueController = TextEditingController(
    text: _initialDisplayValue,
  );
  late String _boolValue = widget.entry.value;
  late bool _unlimited =
      _isQuotaConfigEntry(widget.entry) && _isUnlimitedQuota(widget.entry);
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// 需要以 GB 为单位展示/编辑的字节类配置键。
  static const _gbConfigs = {'share.max-bytes', 'shared_space.max_bytes'};
  static const _quotaSliderMaxGb = 1024.0;

  bool get _isGbConfig => _gbConfigs.contains(widget.entry.key);
  bool get _isQuotaConfig => _isQuotaConfigEntry(widget.entry);
  bool get _isBoolConfig => widget.entry.valueType == 'BOOLEAN';
  bool get _isSensitiveConfig => _isSensitiveConfigEntry(widget.entry);

  String get _initialDisplayValue {
    if (_isSensitiveConfig) return '';
    if (_isBoolConfig) return widget.entry.value;
    if (_isQuotaConfig) {
      final gb = _quotaValueInGb(widget.entry);
      return gb <= 0 ? '' : _formatQuotaInput(gb);
    }
    if (_isGbConfig) {
      final bytes = int.tryParse(widget.entry.value) ?? 0;
      return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    }
    return widget.entry.value;
  }

  /// 将 GB 输入值转换为字节字符串。
  String _gbToBytes(String gbValue) {
    final gb = double.tryParse(gbValue);
    if (gb == null || gb < 0) return '0';
    return (gb * 1024 * 1024 * 1024).round().toString();
  }

  /// 最终提交的值。
  String get _submitValue {
    if (_isBoolConfig) return _boolValue;
    final raw = _valueController.text.trim();
    if (_isQuotaConfig) {
      if (_unlimited) return '0';
      final gb = double.tryParse(raw);
      if (gb == null || gb <= 0) return raw;
      if (_isGbConfig) return _gbToBytes(raw);
      return gb.round().toString();
    }
    return _isGbConfig ? _gbToBytes(raw) : raw;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text('${l10n.adminEdit} ${_configTitle(l10n, widget.entry)}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isSensitiveConfig) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.entry.sensitiveConfigured
                      ? l10n.adminConfigSecretConfigured
                      : l10n.adminConfigNeedsSetup,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isBoolConfig)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.adminConfigValue),
                subtitle: Text(
                  _boolValue == 'true' ? l10n.adminEnabled : l10n.adminDisabled,
                ),
                value: _boolValue == 'true',
                onChanged:
                    (enabled) =>
                        setState(() => _boolValue = enabled.toString()),
              )
            else if (_isQuotaConfig)
              _QuotaEditor(
                controller: _valueController,
                unlimited: _unlimited,
                maxGb: _quotaSliderMaxGb,
                initialGb: _quotaValueInGb(widget.entry),
                onUnlimitedChanged: (value) {
                  setState(() {
                    _unlimited = value;
                    if (!value && _valueController.text.trim().isEmpty) {
                      _valueController.text = '1';
                    }
                  });
                },
                onValueChanged: (value) {
                  setState(() {
                    if (value >= _quotaSliderMaxGb) {
                      _unlimited = true;
                    } else {
                      _unlimited = false;
                      _valueController.text = _formatQuotaInput(value);
                    }
                  });
                },
                onTextChanged: (value) {
                  if (value == null || value <= 0) return;
                  setState(() => _unlimited = false);
                },
              )
            else if (widget.entry.allowedValues.isNotEmpty)
              AppDropdown<String>(
                value:
                    widget.entry.allowedValues.contains(widget.entry.value)
                        ? widget.entry.value
                        : widget.entry.allowedValues.first,
                label: l10n.adminConfigValue,
                items: [
                  for (final value in widget.entry.allowedValues)
                    AppDropdownItem(value: value, label: value),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _valueController.text = value;
                  }
                },
              )
            else
              TextField(
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: l10n.adminConfigValue,
                  hintText:
                      _isSensitiveConfig
                          ? l10n.adminSensitiveValuePlaceholder
                          : null,
                  suffixText: _isGbConfig ? 'GB' : null,
                ),
                keyboardType:
                    _isGbConfig
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                minLines: 1,
                maxLines: 4,
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(labelText: l10n.adminChangeReason),
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
        if (_isSensitiveConfig && widget.entry.sensitiveConfigured)
          TextButton.icon(
            onPressed: _submitting ? null : _clearCredential,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.adminConfigClearCredential),
            style: TextButton.styleFrom(
              foregroundColor: context.adminColors.error,
            ),
          ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(_submitting ? l10n.adminSaving : l10n.adminSave),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final quotaError = _validateQuota(l10n);
    if (quotaError != null) {
      setState(() => _error = quotaError);
      return;
    }
    if (_isSensitiveConfig && _submitValue.isEmpty) {
      setState(() => _error = l10n.adminSensitiveValuePlaceholder);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final actions = ref.read(adminOperationsActionsProvider);
    try {
      await actions.updateConfig(
        widget.entry.key,
        _submitValue,
        reason: _reasonController.text,
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

  String? _validateQuota(AppLocalizations l10n) {
    if (!_isQuotaConfig || _unlimited) {
      return null;
    }
    final value = double.tryParse(_valueController.text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      return l10n.adminConfigQuotaInvalid;
    }
    if (!_isGbConfig && value != value.roundToDouble()) {
      return l10n.adminConfigQuotaWholeGb;
    }
    return null;
  }

  Future<void> _clearCredential() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminConfigClearCredential),
            content: Text(l10n.adminConfigClearCredentialConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.adminConfigClearCredential),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    final actions = ref.read(adminOperationsActionsProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await actions.updateConfig(
        widget.entry.key,
        '',
        reason: l10n.adminConfigCredentialClearedReason,
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

double _quotaValueInGb(AdminConfigEntry entry) {
  final value = double.tryParse(entry.value) ?? 0;
  if (entry.key == 'share.max-bytes' || entry.key == 'shared_space.max_bytes') {
    return value / (1024 * 1024 * 1024);
  }
  return value;
}

String _formatQuotaInput(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class _QuotaEditor extends StatelessWidget {
  const _QuotaEditor({
    required this.controller,
    required this.unlimited,
    required this.maxGb,
    required this.initialGb,
    required this.onUnlimitedChanged,
    required this.onValueChanged,
    required this.onTextChanged,
  });

  final TextEditingController controller;
  final bool unlimited;
  final double maxGb;
  final double initialGb;
  final ValueChanged<bool> onUnlimitedChanged;
  final ValueChanged<double> onValueChanged;
  final ValueChanged<double?> onTextChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = double.tryParse(controller.text.trim());
    final sliderValue =
        unlimited
            ? maxGb
            : (parsed ?? initialGb).clamp(1.0, maxGb - 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          enabled: !unlimited,
          decoration: InputDecoration(
            labelText: l10n.adminConfigValue,
            suffixText: 'GB',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) => onTextChanged(double.tryParse(value.trim())),
        ),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.adminConfigUnlimited),
          subtitle: Text(l10n.adminConfigUnlimitedDescription),
          value: unlimited,
          onChanged: onUnlimitedChanged,
        ),
        const SizedBox(height: 2),
        AppSlider(
          value: sliderValue,
          min: 1,
          max: maxGb,
          divisions: maxGb.round() - 1,
          label:
              unlimited
                  ? l10n.adminConfigUnlimited
                  : '${_formatQuotaInput(sliderValue)} GB',
          onChanged: onValueChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.adminConfigQuotaSliderMinimum,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              l10n.adminConfigQuotaSliderUnlimited,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfigHistoryDialog extends ConsumerWidget {
  const _ConfigHistoryDialog({
    required this.configKey,
    required this.configLabel,
  });

  final String configKey;
  final String configLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final history = ref.watch(adminConfigHistoryProvider(configKey));
    return AlertDialog(
      title: Text('${l10n.adminConfigHistory} — $configLabel'),
      content: SizedBox(
        width: 560,
        child: history.when(
          loading:
              () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.adminLoadFailed('$error')),
              ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.adminNoConfigHistory),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  title: Text(
                    '${item.oldValue ?? l10n.adminNotSet}'
                    ' → ${item.newValue ?? l10n.adminNotSet}',
                    style: const TextStyle(fontSize: AppTypography.bodyMedium),
                  ),
                  subtitle: Text(
                    '${item.changeReason ?? l10n.adminNoReason}'
                    ' · ${item.createdAt}',
                    style: TextStyle(
                      fontSize: AppTypography.bodySmall,
                      color: adminColors.onSurfaceVariant,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(adminOperationsActionsProvider)
                            .rollbackConfig(item.id);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } on Exception catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.adminLoadFailed('$e'))),
                          );
                        }
                      }
                    },
                    child: Text(l10n.adminRollback),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
      ],
    );
  }
}
