part of 'file_browser_page.dart';

// ───────────────────────── 子页共享构建块（模板 Header/Metric/Chips/Table） ─────────────────────────

/// 子页页头：标题 + 描述 + 右侧操作钮。
class _SubHeader extends StatelessWidget {
  const _SubHeader({
    required this.title,
    required this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTypography.titleLarge,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

/// 指标卡条（四卡）。
class _SubMetricStrip extends StatelessWidget {
  const _SubMetricStrip({required this.cards});

  final List<_MetricCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920 ? 4 : 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                child: card,
              ),
          ],
        );
      },
    );
  }
}

/// 状态筛选 chips 条（底部细线收束）。
class _SubChipsBar extends StatelessWidget {
  const _SubChipsBar({required this.chips});

  final List<_SubChip> chips;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            // 窄窗口下 chips 溢出：悬停区域时纵向滚轮驱动横向滚动。
            child: HoverHorizontalScroll(
              child: Row(
                children: [
                  for (final chip in chips) ...[
                    _CategoryCapsule(
                      label: chip.label,
                      icon: Icons.circle,
                      isActive: chip.active,
                      enabled: true,
                      onTap: chip.onTap,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubChip {
  const _SubChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
}

/// 表格外壳：hairline 容器 + 表头行 + 行列表。
///
/// 列 spec 单一来源：表头与全部数据行共用 [columns]，行声明只给单元格，
/// 杜绝表头与行各自维护列清单造成的错位与列数漂移。
///
/// 横向滚动视口给子级无界宽度约束，表头行的 Expanded 弹性列会直接触发
/// unbounded flex 断言；内容以 max(视口宽, 自然最小宽) 定宽承载，视口
/// 不足时按自然最小宽横向滚动。富余宽度按 flex 权重分摊到各弹性列，
/// 不由单列独吞；宽屏封顶 [_maxTableWidth]，超宽视口下表格收束留白。
class _SubTable extends StatelessWidget {
  const _SubTable({required this.columns, required this.rows});

  final List<_SubColumn> columns;
  final List<_SubRow> rows;

  /// 宽屏封顶：视口超过此宽时表格收束、右侧自然留白，
  /// 对齐 Portal 内容区 1560 的工位上限度量。
  static const double _maxTableWidth = 1560;

  /// 固定列宽总和 + 弹性列按权重的最低可读空间（每 1 flex 保 100px）。
  double _naturalMinWidth() {
    var total = 0.0;
    var flexTotal = 0;
    for (final column in columns) {
      if (column.width != null) {
        total += column.width!;
      } else {
        flexTotal += column.flex ?? 1;
      }
    }
    return total + flexTotal * 100;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final naturalMin = _naturalMinWidth();
        var contentWidth =
            viewport.isFinite && viewport > naturalMin ? viewport : naturalMin;
        if (contentWidth > _maxTableWidth) {
          contentWidth = _maxTableWidth;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  Container(
                    height: 36,
                    color: colors.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (final column in columns)
                          column.flex != null
                              ? Expanded(
                                flex: column.flex!,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _SubThLabel(column.label),
                                ),
                              )
                              : SizedBox(
                                width: column.width,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _SubThLabel(column.label),
                                ),
                              ),
                      ],
                    ),
                  ),
                  for (final row in rows)
                    _SubRowShell(columns: columns, row: row),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubColumn {
  const _SubColumn(this.label, {this.width, this.flex});

  final String label;
  final double? width;
  final int? flex;
}

class _SubThLabel extends StatelessWidget {
  const _SubThLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        letterSpacing: 1.2,
        color: context.filesColors.onSurfaceVariant,
      ),
    );
  }
}

/// 数据行声明：只携带单元格与点击回调，列骨架由 [_SubTable] 按同一份
/// 列 spec 构建，行内不再重复声明列宽。
class _SubRow {
  const _SubRow({required this.cells, this.onTap});

  final List<Widget> cells;
  final VoidCallback? onTap;
}

/// 数据行渲染：与表头同构的单元格行容器。
class _SubRowShell extends StatelessWidget {
  const _SubRowShell({required this.columns, required this.row});

  final List<_SubColumn> columns;
  final _SubRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    assert(
      row.cells.length == columns.length,
      '单元格数量 ${row.cells.length} 与列 spec 数量 ${columns.length} 不一致',
    );
    return _SubHover(
      onTap: row.onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              columns[i].flex != null
                  ? Expanded(flex: columns[i].flex!, child: row.cells[i])
                  : SizedBox(width: columns[i].width, child: row.cells[i]),
          ],
        ),
      ),
    );
  }
}

class _SubHover extends StatefulWidget {
  const _SubHover({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_SubHover> createState() => _SubHoverState();
}

class _SubHoverState extends State<_SubHover> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ColoredBox(
          color:
              _hovering
                  ? context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.4,
                  )
                  : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 状态徽章：语义色小面积（前景 + 深底 + 边框）。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label, {this.tone = _BadgeTone.neutral});

  final String label;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (fg, bg, border) = switch (tone) {
      _BadgeTone.good => (
        FilesWorkstationPalette.emerald,
        FilesWorkstationPalette.emeraldBgDark,
        Color(0xFF047857),
      ),
      _BadgeTone.warn => (
        FilesWorkstationPalette.amber,
        FilesWorkstationPalette.amberBgDark,
        Color(0xFFB45309),
      ),
      _BadgeTone.bad => (
        FilesWorkstationPalette.rose,
        FilesWorkstationPalette.roseBgDark,
        Color(0xFFB91C1C),
      ),
      _BadgeTone.neutral => (
        context.filesColors.onSurfaceVariant,
        context.filesColors.surfaceContainerHigh,
        context.filesColors.outlineVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? bg : context.filesColors.surfaceContainerHigh,
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.labelMicro,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

enum _BadgeTone { good, warn, bad, neutral }

/// mono 单元格文本。
class _SubMono extends StatelessWidget {
  const _SubMono(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelMedium,
          fontWeight: FontWeight.w400,
          color: context.filesColors.onSurface,
        ),
      ),
    );
  }
}

/// 名称单元格：类型图标 + 名称 + 次级说明行。
class _SubNameCell extends StatelessWidget {
  const _SubNameCell({
    required this.name,
    required this.detail,
    required this.isFolder,
  });

  final String name;
  final String detail;
  final bool isFolder;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Row(
      children: [
        Icon(
          isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
          size: 16,
          color:
              isFolder
                  ? FilesWorkstationPalette.amber
                  : colors.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.labelSmall,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 2px 进度条单元格（翡翠填充 / hairline 轨道）。
class _SubProgressCell extends StatelessWidget {
  const _SubProgressCell({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        ClipRect(
          child: SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: value,
              minHeight: 2,
              color: FilesWorkstationPalette.emerald,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    );
  }
}

/// 子页操作小钮（28px 直角）。
class _SubAction extends StatefulWidget {
  const _SubAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  State<_SubAction> createState() => _SubActionState();
}

class _SubActionState extends State<_SubAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final enabled = widget.onTap != null;
    final fg = widget.destructive ? colors.error : colors.onSurface;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(
              color:
                  widget.destructive
                      ? colors.error.withValues(alpha: 0.55)
                      : colors.outlineVariant,
            ),
          ),
          foregroundDecoration:
              _hovering && enabled
                  ? BoxDecoration(color: colors.surfaceContainerHigh)
                  : null,
          child: Text(
            widget.label,
            style: TextStyle(fontSize: AppTypography.labelSmall, color: fg),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 共享给我（05） ─────────────────────────
