part of 'admin_operations_pages.dart';

/// 配置中心编辑/配额编辑器与历史回滚弹窗，
/// 自 admin_operations_roles_config 拆出。

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

  /// 需要以 MB 为单位展示/编辑的字节类配置键；存储与后端契约仍是字节。
  static const _mbConfigs = {
    'backdrop.max-image-bytes',
    'backdrop.max-video-bytes',
  };
  static const _quotaSliderMaxGb = 1024.0;

  bool get _isGbConfig => _gbConfigs.contains(widget.entry.key);
  bool get _isMbConfig => _mbConfigs.contains(widget.entry.key);
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
    if (_isMbConfig) {
      final bytes = int.tryParse(widget.entry.value) ?? 0;
      return (bytes / (1024 * 1024)).toStringAsFixed(1);
    }
    return widget.entry.value;
  }

  /// 将 GB 输入值转换为字节字符串。
  String _gbToBytes(String gbValue) {
    final gb = double.tryParse(gbValue);
    if (gb == null || gb < 0) return '0';
    return (gb * 1024 * 1024 * 1024).round().toString();
  }

  /// 将 MB 输入值转换为字节字符串。
  String _mbToBytes(String mbValue) {
    final mb = double.tryParse(mbValue);
    if (mb == null || mb < 0) return '0';
    return (mb * 1024 * 1024).round().toString();
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
    if (_isMbConfig) return _mbToBytes(raw);
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
    return WorkstationDialogFrame(
      title: '${l10n.adminEdit} ${_configTitle(l10n, widget.entry)}',
      headerLabel: widget.entry.key,
      width: 560,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
            WorkstationToggle(
              label: l10n.adminConfigValue,
              subtitle:
                  _boolValue == 'true' ? l10n.adminEnabled : l10n.adminDisabled,
              value: _boolValue == 'true',
              onChanged:
                  (enabled) => setState(() => _boolValue = enabled.toString()),
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
                suffixText: _isGbConfig ? 'GB' : (_isMbConfig ? 'MB' : null),
              ),
              keyboardType:
                  _isGbConfig || _isMbConfig
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.adminColors.error),
            ),
          ],
        ],
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
    final mbError = _validateMegabytes(l10n);
    if (mbError != null) {
      setState(() => _error = mbError);
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
        setState(
          () => _error = describeUserFacingError(error, l10n: l10n).message,
        );
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

  /// MB 单位配置的入参校验；上限由配置中心目录按字节判定，前端不重复维护。
  String? _validateMegabytes(AppLocalizations l10n) {
    if (!_isMbConfig) {
      return null;
    }
    final value = double.tryParse(_valueController.text.trim());
    if (value == null || !value.isFinite || value < 1) {
      return l10n.adminConfigMbInvalid;
    }
    return null;
  }

  Future<void> _clearCredential() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminConfigClearCredential,
      message: l10n.adminConfigClearCredentialConfirm,
      confirmLabel: l10n.adminConfigClearCredential,
      destructive: true,
    );
    if (!mounted || !confirmed) {
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
        setState(
          () => _error = describeUserFacingError(error, l10n: l10n).message,
        );
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
        WorkstationToggle(
          label: l10n.adminConfigUnlimited,
          subtitle: l10n.adminConfigUnlimitedDescription,
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
    return WorkstationDialogFrame(
      title: '${l10n.adminConfigHistory} — $configLabel',
      headerLabel: configKey,
      width: 680,
      body: history.when(
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
                        showOmniFeedback(
                          context,
                          l10n.adminLoadFailed('$e'),
                          severity: OmniFeedbackSeverity.error,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreClose),
        ),
      ],
    );
  }
}
