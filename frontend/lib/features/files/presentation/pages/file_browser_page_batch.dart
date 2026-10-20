part of 'file_browser_page.dart';

/// 表格视图专属批量栏：勾选后出现于表格上方，与卡片一体化工具栏互斥。
class _TableBatchBar extends ConsumerWidget {
  const _TableBatchBar({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final recycle = state.section == FileManagerSection.recycleBin;
    final favorites = state.section == FileManagerSection.favorites;
    final colors = context.filesColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Text(
            l10n.filesSelectedCount(state.selectionCount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTypography.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: enabled ? controller.selectAll : null,
            child: Text(l10n.filesSelectAll),
          ),
          TextButton(
            onPressed: enabled ? controller.clearSelection : null,
            child: Text(l10n.filesDeselect),
          ),
          const Spacer(),
          Flexible(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (recycle) ...[
                  _BatchActionButton(
                    label: l10n.filesBatchRestore,
                    icon: Icons.restore_rounded,
                    enabled: enabled,
                    onTap:
                        () => _confirmAndRun(
                          context,
                          title: l10n.filesBatchRestoreTitle,
                          message: l10n.filesBatchRestoreMessage(
                            state.selectionCount,
                          ),
                          confirmLabel: l10n.filesRestore,
                          action: controller.batchRestoreFiles,
                        ),
                  ),
                  _BatchActionButton(
                    label: l10n.filesBatchPurge,
                    icon: Icons.delete_forever_outlined,
                    enabled: enabled,
                    destructive: true,
                    onTap:
                        () => _confirmTypedAndRun(
                          context,
                          title: l10n.filesBatchPurgeTitle,
                          message: l10n.filesBatchPurgeMessage(
                            state.selectionCount,
                          ),
                          confirmPhrase: state.selectionCount.toString(),
                          confirmLabel: l10n.filesPurge,
                          action: controller.batchPurgeFiles,
                        ),
                  ),
                ] else ...[
                  _BatchActionButton(
                    label: l10n.filesBatchMove,
                    icon: Icons.drive_file_move_outlined,
                    enabled: enabled,
                    onTap:
                        () => _showBatchMoveDialog(
                          context: context,
                          controller: controller,
                          count: state.selectionCount,
                          excludeIds: state.selectedFileIds,
                        ),
                  ),
                  _BatchActionButton(
                    label: l10n.filesBatchDelete,
                    icon: Icons.delete_outline_rounded,
                    enabled: enabled,
                    destructive: true,
                    onTap:
                        () => _confirmAndRun(
                          context,
                          title: l10n.filesBatchDeleteTitle,
                          message: l10n.filesBatchDeleteMessage(
                            state.selectionCount,
                          ),
                          confirmLabel: l10n.filesMoveToRecycleBin,
                          action: controller.batchDeleteFiles,
                        ),
                  ),
                  _BatchActionButton(
                    label:
                        favorites
                            ? l10n.filesBatchRemoveFavorite
                            : l10n.filesBatchAddFavorite,
                    icon:
                        favorites
                            ? Icons.star_border_rounded
                            : Icons.star_rounded,
                    enabled: enabled,
                    onTap:
                        () => unawaited(
                          _runFileAction(
                            context,
                            favorites
                                ? controller.batchRemoveFavorites
                                : controller.batchAddFavorites,
                          ),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片视图一体化工具栏：全选框与首列卡片勾选框 16px 中轴线对齐，
/// 操作按钮勾选后就地展开。
class _GridBatchToolbar extends ConsumerWidget {
  const _GridBatchToolbar({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final recycle = state.section == FileManagerSection.recycleBin;
    final favorites = state.section == FileManagerSection.favorites;
    final visible = state.visibleNodes;
    final allSelected =
        visible.isNotEmpty &&
        visible.every((node) => state.selectedFileIds.contains(node.id));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilesCheckMark(
            value: allSelected,
            onChanged:
                enabled
                    ? (_) =>
                        allSelected
                            ? controller.clearSelection()
                            : controller.selectAll()
                    : null,
          ),
          const SizedBox(width: 8),
          Text(
            state.hasSelection
                ? l10n.filesSelectedCount(state.selectionCount)
                : l10n.filesSelectAll,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTypography.bodyMedium,
              color: context.filesColors.onSurface,
            ),
          ),
          const Spacer(),
          if (state.hasSelection)
            Flexible(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (recycle) ...[
                    _BatchActionButton(
                      label: l10n.filesBatchRestore,
                      icon: Icons.restore_rounded,
                      enabled: enabled,
                      onTap:
                          () => _confirmAndRun(
                            context,
                            title: l10n.filesBatchRestoreTitle,
                            message: l10n.filesBatchRestoreMessage(
                              state.selectionCount,
                            ),
                            confirmLabel: l10n.filesRestore,
                            action: controller.batchRestoreFiles,
                          ),
                    ),
                    _BatchActionButton(
                      label: l10n.filesBatchPurge,
                      icon: Icons.delete_forever_outlined,
                      enabled: enabled,
                      destructive: true,
                      onTap:
                          () => _confirmTypedAndRun(
                            context,
                            title: l10n.filesBatchPurgeTitle,
                            message: l10n.filesBatchPurgeMessage(
                              state.selectionCount,
                            ),
                            confirmPhrase: state.selectionCount.toString(),
                            confirmLabel: l10n.filesPurge,
                            action: controller.batchPurgeFiles,
                          ),
                    ),
                  ] else ...[
                    _BatchActionButton(
                      label: l10n.filesBatchMove,
                      icon: Icons.drive_file_move_outlined,
                      enabled: enabled,
                      onTap:
                          () => _showBatchMoveDialog(
                            context: context,
                            controller: controller,
                            count: state.selectionCount,
                            excludeIds: state.selectedFileIds,
                          ),
                    ),
                    _BatchActionButton(
                      label: l10n.filesBatchDelete,
                      icon: Icons.delete_outline_rounded,
                      enabled: enabled,
                      destructive: true,
                      onTap:
                          () => _confirmAndRun(
                            context,
                            title: l10n.filesBatchDeleteTitle,
                            message: l10n.filesBatchDeleteMessage(
                              state.selectionCount,
                            ),
                            confirmLabel: l10n.filesMoveToRecycleBin,
                            action: controller.batchDeleteFiles,
                          ),
                    ),
                    _BatchActionButton(
                      label:
                          favorites
                              ? l10n.filesBatchRemoveFavorite
                              : l10n.filesBatchAddFavorite,
                      icon:
                          favorites
                              ? Icons.star_border_rounded
                              : Icons.star_rounded,
                      enabled: enabled,
                      onTap:
                          () => unawaited(
                            _runFileAction(
                              context,
                              favorites
                                  ? controller.batchRemoveFavorites
                                  : controller.batchAddFavorites,
                            ),
                          ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    // 移动壳层批量条为 lime 实底：操作钮统一深色前景（危险动作同色，
    // 语义由图标与文案承载）。
    final filesColors = context.filesColors;
    final hosted = MobileShellScope.isHosted(context);
    final base = hosted ? context.env.onSelectionBar : filesColors.onSurface;
    final color = destructive && !hosted ? filesColors.error : base;
    return TextButton.icon(
      onPressed: enabled ? onTap : null,
      style: TextButton.styleFrom(foregroundColor: color, iconColor: color),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// 窄屏贴底浮动批量操作条：移动壳层为样例单行 lime（计数 + 全选 +
/// 关键动作 + 关闭），非托管窄窗沿用原结构。
class _MobileStickyBatchBar extends ConsumerWidget {
  const _MobileStickyBatchBar({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosted = MobileShellScope.isHosted(context);
    if (!hosted) {
      return _NonHostedBatchBar(state: state);
    }
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final recycle = state.section == FileManagerSection.recycleBin;
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 57),
        padding: const EdgeInsets.only(left: 16, right: 10),
        decoration: BoxDecoration(
          color: context.env.selectionBar,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.filesSelectedCount(state.selectionCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.env.onSelectionBar,
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _SelectionIconButton(
              tooltip: l10n.filesSelectAll,
              icon: OmniIcons.check,
              onTap: enabled ? controller.selectAll : null,
            ),
            if (recycle) ...[
              _SelectionIconButton(
                tooltip: l10n.filesBatchRestore,
                icon: OmniIcons.download,
                onTap:
                    enabled
                        ? () => unawaited(controller.batchRestoreFiles())
                        : null,
              ),
              _SelectionIconButton(
                tooltip: l10n.filesBatchPurge,
                // 与右侧"取消选择"共用 × 会让用户在多选态一键粉碎文件，
                // 永久删除必须换图标并走与桌面同级的输入确认。
                icon: OmniIcons.trash,
                onTap:
                    enabled
                        ? () => unawaited(
                          _confirmTypedAndRun(
                            context,
                            title: l10n.filesBatchPurgeTitle,
                            message: l10n.filesBatchPurgeMessage(
                              state.selectionCount,
                            ),
                            confirmPhrase: state.selectionCount.toString(),
                            confirmLabel: l10n.filesPurge,
                            action: controller.batchPurgeFiles,
                          ),
                        )
                        : null,
              ),
            ] else ...[
              _SelectionIconButton(
                tooltip: l10n.filesBatchMove,
                icon: OmniIcons.share,
                onTap:
                    enabled
                        ? () => unawaited(
                          _showBatchMoveDialog(
                            context: context,
                            controller: controller,
                            count: state.selectionCount,
                            excludeIds: state.selectedFileIds,
                          ),
                        )
                        : null,
              ),
              _SelectionIconButton(
                tooltip: l10n.filesBatchDelete,
                icon: OmniIcons.close,
                onTap:
                    enabled
                        ? () => unawaited(
                          _confirmAndRun(
                            context,
                            title: l10n.filesBatchDeleteTitle,
                            message: l10n.filesBatchDeleteMessage(
                              state.selectionCount,
                            ),
                            confirmLabel: l10n.filesMoveToRecycleBin,
                            action: controller.batchDeleteFiles,
                          ),
                        )
                        : null,
              ),
            ],
            _SelectionIconButton(
              tooltip: l10n.coreClear,
              icon: OmniIcons.close,
              onTap: controller.clearSelection,
            ),
          ],
        ),
      ),
    );
  }
}

/// 样例批量条图标钮（43×43 深色前景）。
class _SelectionIconButton extends StatelessWidget {
  const _SelectionIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final OmniIconsData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: OmniIcon(icon: icon, size: 19, color: context.env.onSelectionBar),
      style: IconButton.styleFrom(
        foregroundColor: context.env.onSelectionBar,
        minimumSize: const Size.square(43),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 非托管窄窗（桌面收缩/测试路径）：原两行结构。
class _NonHostedBatchBar extends ConsumerWidget {
  const _NonHostedBatchBar({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final recycle = state.section == FileManagerSection.recycleBin;
    final favorites = state.section == FileManagerSection.favorites;
    final colors = context.filesColors;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          border: Border.all(color: colors.selectedBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.filesSelectedCount(state.selectionCount),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTypography.bodyMedium,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: enabled ? controller.selectAll : null,
                  child: Text(l10n.filesSelectAll),
                ),
                TextButton(
                  onPressed: enabled ? controller.clearSelection : null,
                  child: Text(l10n.filesDeselect),
                ),
              ],
            ),
            SizedBox(
              height: 44,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (recycle) ...[
                      _BatchActionButton(
                        label: l10n.filesBatchRestore,
                        icon: Icons.restore_rounded,
                        enabled: enabled,
                        onTap: () => unawaited(controller.batchRestoreFiles()),
                      ),
                      _BatchActionButton(
                        label: l10n.filesBatchPurge,
                        icon: Icons.delete_outline_rounded,
                        enabled: enabled,
                        destructive: true,
                        onTap:
                            () => _confirmAndRun(
                              context,
                              title: l10n.filesBatchPurgeTitle,
                              message: l10n.filesBatchPurgeMessage(
                                state.selectionCount,
                              ),
                              confirmLabel: l10n.filesBatchPurge,
                              action: controller.batchPurgeFiles,
                            ),
                      ),
                    ] else ...[
                      _BatchActionButton(
                        label: l10n.filesBatchMove,
                        icon: Icons.drive_file_move_outlined,
                        enabled: enabled,
                        onTap:
                            () => _showBatchMoveDialog(
                              context: context,
                              controller: controller,
                              count: state.selectionCount,
                              excludeIds: state.selectedFileIds,
                            ),
                      ),
                      _BatchActionButton(
                        label: l10n.filesBatchDelete,
                        icon: Icons.delete_outline_rounded,
                        enabled: enabled,
                        destructive: true,
                        onTap:
                            () => _confirmAndRun(
                              context,
                              title: l10n.filesBatchDeleteTitle,
                              message: l10n.filesBatchDeleteMessage(
                                state.selectionCount,
                              ),
                              confirmLabel: l10n.filesMoveToRecycleBin,
                              action: controller.batchDeleteFiles,
                            ),
                      ),
                      _BatchActionButton(
                        label:
                            favorites
                                ? l10n.filesBatchRemoveFavorite
                                : l10n.filesBatchAddFavorite,
                        icon:
                            favorites
                                ? Icons.star_border_rounded
                                : Icons.star_rounded,
                        enabled: enabled,
                        onTap:
                            () => unawaited(
                              _runFileAction(
                                context,
                                favorites
                                    ? controller.batchRemoveFavorites
                                    : controller.batchAddFavorites,
                              ),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
