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
    final color =
        destructive ? context.filesColors.error : context.filesColors.onSurface;
    return TextButton.icon(
      onPressed: enabled ? onTap : null,
      style: TextButton.styleFrom(foregroundColor: color, iconColor: color),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// 窄屏贴底浮动批量操作条：避开系统手势区，操作钮 44px。
class _MobileStickyBatchBar extends ConsumerWidget {
  const _MobileStickyBatchBar({required this.state});

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
            ),
          ],
        ),
      ),
    );
  }
}
