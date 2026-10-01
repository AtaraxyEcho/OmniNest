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
    // 分组计数必须是全量数据的纯函数：从 widget.view.items 现算，
    // 不得取筛选或搜索后的中间列表，否则选中分组或检索时其余 chip
    // 会显示 0，只有点选后才恢复真实计数。
    final groupCounts = <String, int>{};
    for (final item in all) {
      final group = _configGroup(l10n, item);
      groupCounts[group] = (groupCounts[group] ?? 0) + 1;
    }
    final groupNames = groupCounts.keys.toList()..sort();
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
    final canManageConfigs =
        ref
            .watch(authSessionProvider)
            .asData
            ?.value
            .user
            ?.permissions
            .contains('system:config:manage') ??
        false;
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
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: _groupFilter == 'ALL',
              label: Text('${l10n.adminAll} (${all.length})'),
              onSelected:
                  (_) => setState(() {
                    _groupFilter = 'ALL';
                    _page = 0;
                  }),
            ),
            for (final name in groupNames)
              FilterChip(
                selected: _groupFilter == name,
                label: Text('$name (${groupCounts[name] ?? 0})'),
                onSelected:
                    (_) => setState(() {
                      _groupFilter = name;
                      _page = 0;
                    }),
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
              // 两个 48px 图标按钮需 2×48 加余量，默认 168 偏宽。
              actionColumnWidth: 112,
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
                  // 分组名较短：收窄到 100，把宽度让给配置项列。
                  minWidth: 100,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'name',
                  label: l10n.adminConfigItems,
                  flex: 3,
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
                final scheme = Theme.of(context).colorScheme;
                // 配置值属数据：统一 mono；敏感项只展示掩码圆点，
                // 完整语义（已配置/值不回显）悬停提示承载。
                final valueStyle = TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.bodySmall,
                  color: scheme.onSurface,
                );
                final Widget valueCell;
                if (_isSensitiveConfigEntry(item) && item.sensitiveConfigured) {
                  valueCell = AdminCellText(
                    '••••••••',
                    style: valueStyle,
                    tooltipMessage: l10n.adminConfigSecretConfigured,
                  );
                } else {
                  valueCell = AdminCellText(summary, style: valueStyle);
                }
                return [
                  AdminCellText(
                    _configGroup(l10n, item),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  AdminCellText(
                    _configTitle(l10n, item),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  AdminCellText(
                    _configDescription(l10n, item),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  valueCell,
                  AdminCellText(
                    item.updatedAt,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ];
              },
              actionsBuilder: (context, index) {
                final entry = pageItems[index];
                return [
                  AdminRowIconAction(
                    tooltip: l10n.adminConfigHistory,
                    icon: Icons.history_outlined,
                    onTap:
                        () => showWorkstationDialog<void>(
                          context: context,
                          builder:
                              (_) => _ConfigHistoryDialog(
                                configKey: entry.key,
                                configLabel: _configTitle(l10n, entry),
                              ),
                        ),
                  ),
                  AdminRowIconAction(
                    tooltip: l10n.adminEdit,
                    icon: Icons.edit_outlined,
                    onTap:
                        entry.editable && canManageConfigs
                            ? () => showWorkstationDialog<void>(
                              context: context,
                              builder: (_) => _ConfigEditDialog(entry: entry),
                            )
                            : null,
                  ),
                ];
              },
            ),
            const SizedBox(height: 12),
            WorkstationPaginationBar(
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
