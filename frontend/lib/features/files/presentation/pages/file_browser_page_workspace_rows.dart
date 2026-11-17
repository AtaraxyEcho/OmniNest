part of 'file_browser_page.dart';

/// 指标卡条：模板四卡形态（label 10px mono / 值 24px headline / 说明行）。
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state, required this.maxWidth});

  final FileBrowserState state;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.filesColors;
    final stats = state.stats;
    final cards = [
      _MetricCard(
        label: l10n.filesFolders,
        value: stats.folderCount.toString(),
        detail: l10n.filesCurrentView,
        color: colors.onSurface,
      ),
      _MetricCard(
        label: l10n.filesFiles,
        value: stats.fileCount.toString(),
        detail: l10n.filesCurrentView,
        color: colors.onSurface,
      ),
      _MetricCard(
        label: l10n.filesCapacity,
        value: formatFileSize(stats.totalSizeBytes),
        detail: l10n.filesCurrentViewTotal,
        color: colors.onSurface,
      ),
      _MetricCard(
        label: l10n.filesRecycleBin,
        value: state.recycleBin.length.toString(),
        detail: l10n.filesSoftDeleted,
        color: colors.error,
      ),
    ];
    final columns = maxWidth >= 920 ? 4 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
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

/// 构造三视图与 Inspector 共用的节点操作回调集合。
FileNodeActionCallbacks _buildFileNodeActions(
  BuildContext context,
  WidgetRef ref,
  FileBrowserController controller, {
  required bool recycle,
  required bool favorites,
}) {
  final l10n = AppLocalizations.of(context);
  final isShared =
      ref.read(fileBrowserControllerProvider).asData?.value.spaceType ==
      'SHARED';
  final canManageActivity =
      ref.watch(userCapabilitiesProvider).canManageOwnActivity;
  final favoriteIds =
      ref.read(fileBrowserControllerProvider).asData?.value.favoriteIdSet ??
      const <String>{};
  return FileNodeActionCallbacks(
    onOpen:
        (file) => unawaited(
          _runFileAction(context, () => controller.openFolder(file)),
        ),
    onRename:
        (file) => _showNameDialog(
          context: context,
          title: l10n.filesRename,
          actionLabel: l10n.filesSave,
          labelText: l10n.filesFileName,
          initialValue: file.name,
          onSubmit: (name) => controller.renameFile(file, name),
        ),
    onDelete:
        (file) => _confirmAndRun(
          context,
          title: l10n.filesDeleteConfirmTitle(file.name),
          message: l10n.filesDeleteConfirmMessage(file.name),
          confirmLabel: l10n.filesMoveToRecycleBin,
          action: () => controller.deleteFile(file),
        ),
    onPurge:
        (file) => _confirmTypedAndRun(
          context,
          title: l10n.filesPurgeConfirmTitle(file.name),
          message: l10n.filesPurgeConfirmMessage(file.name),
          confirmPhrase: file.name,
          confirmLabel: l10n.filesPurge,
          action: () => controller.purgeFile(file),
        ),
    onRestore:
        (file) => unawaited(
          _runFileAction(context, () => controller.restoreFile(file)),
        ),
    onCopy:
        recycle || isShared
            ? null
            : (file) => _showCopyDialog(
              context: context,
              controller: controller,
              file: file,
            ),
    onShowVersions:
        recycle || isShared
            ? null
            : (file) => _showVersionsDialog(
              context: context,
              controller: controller,
              file: file,
            ),
    onMove:
        recycle
            ? null
            : (file) => _showMoveDialog(
              context: context,
              controller: controller,
              file: file,
            ),
    onMoveToSharedSpace:
        recycle || isShared
            ? null
            : (file) => _confirmAndRun(
              context,
              title: l10n.filesMoveToSharedConfirm,
              message: l10n.filesMoveToSharedMessage(file.name),
              confirmLabel: l10n.filesMoveToShared,
              action: () => controller.moveToSharedSpace(file),
            ),
    onMoveToPersonalSpace:
        recycle || !isShared
            ? null
            : (file) => _confirmAndRun(
              context,
              title: l10n.filesMoveToPersonalConfirm,
              message: l10n.filesMoveToPersonalMessage(file.name),
              confirmLabel: l10n.filesMoveToPersonalLabel,
              action: () => controller.moveToPersonalSpace(file),
            ),
    onDownload:
        recycle
            ? null
            : (file) => unawaited(_downloadFile(context, controller, file)),
    onShare:
        recycle ? null : (file) => ShareLinkSheet.show(context, file: file),
    onToggleFavorite:
        recycle || !canManageActivity
            ? null
            : (file) => unawaited(() async {
              // 按实际收藏态切换，而非分区：全部文件里已收藏的行再点
              // 必须走取消收藏，分区判断会让二次点击永远重复收藏。
              final removing = favoriteIds.contains(file.id);
              final ok = await _runFileAction(
                context,
                removing
                    ? () => controller.removeFavorite(file)
                    : () => controller.addFavorite(file),
              );
              if (!ok || !context.mounted) {
                return;
              }
              showOmniFeedback(
                context,
                removing ? l10n.favoriteRemoved : l10n.favoriteAdded,
                severity: OmniFeedbackSeverity.success,
              );
            }()),
    onPreview: recycle ? null : (file) => _openFilePreview(context, file),
    onToggleSelection: controller.toggleSelection,
    onInspect: controller.inspectNode,
  );
}

/// 桌面端文件预览以大尺寸居中弹窗呈现（模板弹窗形态）；
