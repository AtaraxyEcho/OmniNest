part of 'admin_operations_pages.dart';

/// 配置筛选口径（样例 `AdminConfig.tsx` 的四枚 chip）。
enum _ConfigFilter { all, modified, restart, secrets }

/// 本会话内的一次改动：保存时记录，回滚时把旧值写回服务端。
class _ConfigChange {
  const _ConfigChange({
    required this.id,
    required this.key,
    required this.label,
    required this.from,
    required this.to,
    required this.at,
    this.sensitive = false,
  });

  final int id;
  final String key;
  final String label;

  /// 原始旧值：回滚要把它原样写回服务端，不能存掩码。
  final String from;

  /// 原始新值。
  final String to;
  final DateTime at;
  final bool sensitive;

  /// 展示值：敏感项与空值都换成不可回写的占位。
  String display(String value) {
    if (sensitive) {
      return value.isEmpty ? '—' : '••••••••';
    }
    return value.isEmpty ? '—' : value;
  }
}

/// 配置控制台（样例 `AdminConfig.tsx`）：左侧分组轨 + 右侧行式编辑器，
/// 修改先落本地草稿，底部浮动保存条统一提交。保存前可开复核 diff，
/// 保存后把本次改动记进会话历史，可逐条回滚。
class _DesktopConfigPanel extends ConsumerStatefulWidget {
  const _DesktopConfigPanel({required this.view});

  final AdminConfigManagementView view;

  @override
  ConsumerState<_DesktopConfigPanel> createState() =>
      _DesktopConfigPanelState();
}

class _DesktopConfigPanelState extends ConsumerState<_DesktopConfigPanel> {
  static const _historyPageSize = 5;

  String _group = 'ALL';
  final Map<String, String> _draft = {};
  final TextEditingController _search = TextEditingController();
  _ConfigFilter _filter = _ConfigFilter.all;
  final List<_ConfigChange> _history = [];
  int _historyPage = 0;
  int _nextChangeId = 0;
  bool _saving = false;
  bool _rollingBack = false;

  /// 拆到 part 里的面板片段没有 `setState` 权限（受保护成员），统一走这里。
  void _rebuild(VoidCallback update) => setState(update);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _valueOf(AdminConfigEntry entry) => _draft[entry.key] ?? entry.value;

  bool _isDirty(AdminConfigEntry entry) =>
      _draft.containsKey(entry.key) && _draft[entry.key] != entry.value;

  int get _dirtyCount => widget.view.items.where(_isDirty).length;

  bool _passesFilter(AdminConfigEntry entry) => switch (_filter) {
    _ConfigFilter.all => true,
    _ConfigFilter.modified => _isDirty(entry),
    _ConfigFilter.restart => entry.refreshScope == 'RESTART_REQUIRED',
    _ConfigFilter.secrets => _isSensitiveConfigEntry(entry),
  };

  /// 表格与历史里展示的取值：敏感项只给掩码，避免把密钥写进界面或导出物。
  String _display(AdminConfigEntry entry, String value) {
    if (_isSensitiveConfigEntry(entry)) {
      return value.isEmpty ? '—' : '••••••••';
    }
    return value.isEmpty ? '—' : value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final all =
        widget.view.items
            .where((item) => !_isRemovedConfigKey(item.key))
            .toList();
    final query = _search.text.trim().toLowerCase();
    final base =
        query.isEmpty
            ? all
            : all.where((item) {
              return item.key.toLowerCase().contains(query) ||
                  _configTitle(l10n, item).toLowerCase().contains(query) ||
                  item.description.toLowerCase().contains(query);
            }).toList();
    final groups = <String, List<AdminConfigEntry>>{};
    for (final item in base) {
      groups.putIfAbsent(_configGroup(l10n, item), () => []).add(item);
    }
    final names = groups.keys.toList()..sort();
    final visible =
        base.where((item) {
          return (_group == 'ALL' || _configGroup(l10n, item) == _group) &&
              _passesFilter(item);
        }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(
          title: l10n.adminConfigCenter,
          count: visible.length,
          subtitle: l10n.adminConfigCenterSubtitle,
          childGap: 14,
          action: DesktopButton(
            label: l10n.desktopConfigExport,
            icon: DesktopIcons.download,
            onPressed: all.isEmpty ? null : () => _export(all),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    child: DesktopTextField(
                      controller: _search,
                      hint: l10n.desktopConfigSearchHint,
                      prefixIcon: DesktopIcons.search,
                      keyName: 'desktopConfigSearch',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _filterChip(
                    l10n.desktopFilterAll,
                    _ConfigFilter.all,
                    all.length,
                  ),
                  _filterChip(
                    l10n.desktopConfigFilterModified,
                    _ConfigFilter.modified,
                    all.where(_isDirty).length,
                  ),
                  _filterChip(
                    l10n.adminRestartRequired,
                    _ConfigFilter.restart,
                    all
                        .where(
                          (item) => item.refreshScope == 'RESTART_REQUIRED',
                        )
                        .length,
                  ),
                  _filterChip(
                    l10n.desktopConfigFilterSecrets,
                    _ConfigFilter.secrets,
                    all.where(_isSensitiveConfigEntry).length,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                _emptyState(l10n, skin)
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final list = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in groups.entries)
                          if ((_group == 'ALL' || entry.key == _group) &&
                              entry.value.any(_passesFilter)) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                              child: Text(
                                entry.key.toUpperCase(),
                                style: DesktopType.eyebrow(skin.text3),
                              ),
                            ),
                            for (final item in entry.value)
                              if (_passesFilter(item))
                                _row(context, l10n, skin, item),
                          ],
                      ],
                    );
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _railButton(
                                  l10n.desktopFilterAll,
                                  'ALL',
                                  all.length,
                                ),
                                for (final name in names) ...[
                                  const SizedBox(width: 6),
                                  _chipButton(
                                    name,
                                    groups[name]!.length,
                                    dirty: groups[name]!.any(_isDirty),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          list,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 210,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _railButton(
                                l10n.desktopFilterAll,
                                'ALL',
                                all.length,
                              ),
                              for (final name in names)
                                _railButton(
                                  name,
                                  name,
                                  groups[name]!.length,
                                  dirty: groups[name]!.any(_isDirty),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: list),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _historyCard(l10n, skin),
        if (_dirtyCount > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            decoration: BoxDecoration(
              color: skin.pop,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
              border: Border.all(color: skin.line2),
              boxShadow: skin.shadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: skin.warm,
                    boxShadow: [
                      BoxShadow(
                        color: skin.warm.withValues(alpha: 0.25),
                        blurRadius: 0,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.desktopConfigUnsaved(_dirtyCount),
                    style: DesktopType.denseStrong(skin.text),
                  ),
                ),
                DesktopButton(
                  label: l10n.desktopConfigDiscard,
                  variant: DesktopButtonVariant.ghost,
                  onPressed: _saving ? null : () => setState(_draft.clear),
                ),
                const SizedBox(width: 8),
                DesktopButton(
                  label: l10n.desktopConfigReview,
                  variant: DesktopButtonVariant.soft,
                  onPressed: _saving ? null : () => _review(all),
                ),
                const SizedBox(width: 8),
                DesktopButton(
                  label: l10n.desktopConfigSaveChanges,
                  variant: DesktopButtonVariant.primary,
                  busy: _saving,
                  onPressed: _saving ? null : () => _save(all),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _filterChip(String label, _ConfigFilter filter, int count) {
    return DesktopChipButton(
      label: '$label · $count',
      selected: _filter == filter,
      onTap: () => setState(() => _filter = filter),
    );
  }

  Widget _emptyState(AppLocalizations l10n, DesktopSkin skin) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radius),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        children: [
          Icon(DesktopIcons.search, size: 22, color: skin.text3),
          const SizedBox(height: 10),
          Text(l10n.desktopConfigNoMatch, style: DesktopType.dense(skin.text2)),
          const SizedBox(height: 8),
          DesktopButton(
            label: l10n.adminClearFilters,
            variant: DesktopButtonVariant.ghost,
            onPressed:
                () => setState(() {
                  _search.clear();
                  _filter = _ConfigFilter.all;
                  _group = 'ALL';
                }),
          ),
        ],
      ),
    );
  }

  Widget _railButton(
    String label,
    String value,
    int count, {
    bool dirty = false,
  }) {
    final skin = DesktopSkin.of(context);
    final active = _group == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: () => setState(() => _group = value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? skin.raise2 : Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
          ),
          child: Row(
            children: [
              if (dirty)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: skin.warm,
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.dense(
                    active ? skin.text : skin.text2,
                  ).copyWith(
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text('$count', style: DesktopType.nano(skin.text3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipButton(String label, int count, {bool dirty = false}) {
    return DesktopChipButton(
      label: dirty ? '$label · $count •' : '$label · $count',
      selected: _group == label,
      onTap: () => setState(() => _group = label),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    DesktopSkin skin,
    AdminConfigEntry entry,
  ) {
    final dirty = _isDirty(entry);
    final canEdit = entry.editable;
    final value = _valueOf(entry);
    final isBool = entry.valueType.toUpperCase() == 'BOOLEAN';
    final choices = entry.allowedValues;
    final restart = entry.refreshScope == 'RESTART_REQUIRED';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: dirty ? Color.lerp(skin.panel, skin.warm, 0.07) : skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radius),
        border: Border.all(
          color: dirty ? skin.warm.withValues(alpha: 0.6) : skin.line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _configTitle(l10n, entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.denseStrong(skin.text),
                      ),
                    ),
                    if (restart) ...[
                      const SizedBox(width: 8),
                      DesktopChip(l10n.adminRestartRequired),
                    ],
                    if (_isSensitiveConfigEntry(entry)) ...[
                      const SizedBox(width: 8),
                      DesktopChip(l10n.desktopConfigSensitiveTag),
                    ],
                    if (!canEdit) ...[
                      const SizedBox(width: 8),
                      DesktopChip(l10n.adminConfigReadOnly),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  entry.description.isEmpty
                      ? entry.key
                      : '${entry.key} · ${entry.description}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 250,
            child:
                !canEdit
                    ? Text(
                      isBool
                          ? (value == 'true'
                              ? l10n.adminConfigOn
                              : l10n.adminConfigOff)
                          : _configValueSummary(l10n, entry),
                      textAlign: TextAlign.right,
                      style: DesktopType.dense(skin.text2),
                    )
                    : isBool
                    ? Align(
                      alignment: Alignment.centerRight,
                      child: DesktopToggle(
                        value: value == 'true',
                        label: entry.key,
                        onChanged:
                            (next) => setState(
                              () => _draft[entry.key] = next ? 'true' : 'false',
                            ),
                      ),
                    )
                    : choices.isNotEmpty && choices.length <= 6
                    ? Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        alignment: WrapAlignment.end,
                        children: [
                          for (final choice in choices)
                            DesktopChipButton(
                              label: choice,
                              selected: value == choice,
                              onTap:
                                  () => setState(
                                    () => _draft[entry.key] = choice,
                                  ),
                            ),
                        ],
                      ),
                    )
                    : _ConfigField(
                      value: value,
                      obscure: _isSensitiveConfigEntry(entry),
                      onChanged:
                          (next) => setState(() => _draft[entry.key] = next),
                    ),
          ),
          const SizedBox(width: 4),
          DesktopIconButton(
            icon: Icons.undo_rounded,
            size: 30,
            iconSize: 15,
            tooltip: l10n.desktopConfigResetRow,
            onPressed:
                dirty ? () => setState(() => _draft.remove(entry.key)) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _save(List<AdminConfigEntry> items) async {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(adminOperationsActionsProvider);
    final changes = items.where(_isDirty).toList();
    if (changes.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final rows = <_ConfigChange>[];
    var saved = 0;
    try {
      for (final entry in changes) {
        final next = _draft[entry.key]!;
        await actions.updateConfig(entry.key, next);
        rows.add(
          _ConfigChange(
            id: _nextChangeId++,
            key: entry.key,
            label: _configTitle(l10n, entry),
            from: entry.value,
            to: next,
            at: DateTime.now(),
            sensitive: _isSensitiveConfigEntry(entry),
          ),
        );
        saved++;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _draft.clear();
        _history.insertAll(0, rows.reversed);
        _historyPage = 0;
      });
      ref.invalidate(adminConfigsProvider);
      showOmniFeedback(
        context,
        l10n.adminConfigSaved('$saved'),
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showOmniFeedback(
          context,
          errorReason(error, l10n),
          severity: OmniFeedbackSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _rollback(_ConfigChange change) async {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(adminOperationsActionsProvider);
    setState(() => _rollingBack = true);
    try {
      await actions.updateConfig(change.key, change.from);
      if (!mounted) {
        return;
      }
      setState(() {
        _history.removeWhere((item) => item.id == change.id);
        _historyPage = 0;
      });
      ref.invalidate(adminConfigsProvider);
      showOmniFeedback(
        context,
        l10n.desktopConfigRolledBack,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showOmniFeedback(
          context,
          errorReason(error, l10n),
          severity: OmniFeedbackSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _rollingBack = false);
      }
    }
  }

  Future<void> _export(List<AdminConfigEntry> items) async {
    final l10n = AppLocalizations.of(context);
    final payload = <String, String>{
      for (final entry in items)
        entry.key: _isSensitiveConfigEntry(entry) ? '***' : entry.value,
    };
    final text = const JsonEncoder.withIndent('  ').convert(payload);
    try {
      final path = await saveAdminCsvBytes(
        suggestedName: 'omninest-config.json',
        bytes: utf8.encode(text),
      );
      if (!mounted || path == null) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.desktopConfigExported,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showOmniFeedback(
          context,
          errorReason(error, l10n),
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}

/// 行内文本框：外部值变化且未聚焦时回灌，避免覆盖正在输入的内容。
class _ConfigField extends StatefulWidget {
  const _ConfigField({
    required this.value,
    required this.obscure,
    required this.onChanged,
  });

  final String value;
  final bool obscure;
  final ValueChanged<String> onChanged;

  @override
  State<_ConfigField> createState() => _ConfigFieldState();
}

class _ConfigFieldState extends State<_ConfigField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_ConfigField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DesktopTextField(
      controller: _controller,
      height: 32,
      obscure: widget.obscure,
      onChanged: widget.onChanged,
    );
  }
}
