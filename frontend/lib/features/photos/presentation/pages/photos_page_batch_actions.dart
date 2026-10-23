part of 'photos_page.dart';

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({required this.state, required this.ref});

  final PhotoCenterState state;
  final WidgetRef ref;

  /// 当前视图可见照片是否已全部选中。
  bool get _allVisibleSelected {
    final visibleIds = state.visiblePhotos.map((photo) => photo.id);
    return visibleIds.isNotEmpty &&
        visibleIds.every(state.selectedPhotoIds.contains);
  }

  @override
  Widget build(BuildContext context) {
    // 托管移动态：样例 .selection-bar（酸绿实底胶囊、计数 + 纯图标钮）。
    if (MobileShellScope.isHosted(context)) {
      return _buildHostedBar(context);
    }
    // 壳层底栏隐藏后批量条贴底渲染；装饰铺满手势区，SafeArea 只避让内容。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.photosColors.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // 取消选择
                IconButton(
                  tooltip: AppLocalizations.of(context).photosDeselect,
                  onPressed: () {
                    ref
                        .read(photoCenterControllerProvider.notifier)
                        .toggleSelectionMode();
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.photosColors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  AppLocalizations.of(
                    context,
                  ).photosSelectedCount(state.selectedPhotoIds.length),
                  style: TextStyle(
                    color: context.photosColors.onSurface,
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                _BatchAction(
                  icon:
                      _allVisibleSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                  label:
                      _allVisibleSelected
                          ? AppLocalizations.of(context).photosDeselectAll
                          : AppLocalizations.of(context).photosSelectAll,
                  onTap: () {
                    ref
                        .read(photoCenterControllerProvider.notifier)
                        .toggleSelectAllVisible();
                  },
                ),
                const SizedBox(width: 8),
                // 批量操作区：窄宽度下横向滚动，避免溢出。
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // 批量标签
                        _BatchAction(
                          icon: Icons.label_outline,
                          label: AppLocalizations.of(context).photosTag,
                          onTap: () => _showBatchTagDialog(context),
                        ),
                        const SizedBox(width: 8),
                        // 批量移动到相册
                        _BatchAction(
                          icon: Icons.photo_album_outlined,
                          label: AppLocalizations.of(context).photosMove,
                          onTap: () => _showBatchMoveDialog(context),
                        ),
                        const SizedBox(width: 8),
                        _BatchAction(
                          icon: Icons.archive_outlined,
                          label: AppLocalizations.of(context).photosExportZip,
                          onTap: () => _startBatchDownload(context),
                        ),
                        const SizedBox(width: 8),
                        // 批量删除
                        _BatchAction(
                          icon: Icons.delete_outline,
                          label: AppLocalizations.of(context).photosDeleteShort,
                          onTap: () => _confirmBatchTrash(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 样例 selection-bar：酸绿实底、r18、投影、左侧计数（11px 粗体深墨）
  /// + 右侧 43px 纯图标动作钮（标签/移动到相册/导出/删除/清除选择）。
  Widget _buildHostedBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        constraints: const BoxConstraints(minHeight: 57),
        padding: const EdgeInsets.only(left: 16, right: 10),
        decoration: BoxDecoration(
          color: context.env.selectionBar,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: FramePalette.batchScrim,
              offset: Offset(0, 12),
              blurRadius: 28,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.photosSelectedCount(state.selectedPhotoIds.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11, // ignore: font_size_whitelist
                  fontWeight: FontWeight.w700,
                  color: context.env.onSelectionBar,
                ),
              ),
            ),
            _SelectionBarIconButton(
              icon: Icons.label_outline,
              tooltip: l10n.photosTag,
              onTap: () => _showBatchTagDialog(context),
            ),
            _SelectionBarIconButton(
              icon: Icons.photo_album_outlined,
              tooltip: l10n.photosMove,
              onTap: () => _showBatchMoveDialog(context),
            ),
            _SelectionBarIconButton(
              icon: Icons.archive_outlined,
              tooltip: l10n.photosExportZip,
              onTap: () => _startBatchDownload(context),
            ),
            _SelectionBarIconButton(
              icon: Icons.delete_outline,
              tooltip: l10n.photosDeleteShort,
              onTap: () => _confirmBatchTrash(context),
            ),
            _SelectionBarIconButton(
              icon: Icons.close_rounded,
              tooltip: l10n.photosDeselect,
              onTap: () {
                ref
                    .read(photoCenterControllerProvider.notifier)
                    .toggleSelectionMode();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBatchTagDialog(BuildContext context) async {
    final tag = await showFramePromptDialog(
      context,
      title: AppLocalizations.of(context).photosBatchAddTag,
      hint: AppLocalizations.of(context).photosTagNameHint,
      confirmLabel: AppLocalizations.of(context).photosAdd,
    );
    if (tag != null && tag.trim().isNotEmpty && context.mounted) {
      try {
        final task = await ref
            .read(photoCenterControllerProvider.notifier)
            .createBatchTask(taskType: 'TAG', params: {'tag': tag});
        if (context.mounted) {
          _showProgressDialog(context, task.id);
        }
      } on Exception {
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosTaskCreateFailed,
            severity: OmniFeedbackSeverity.error,
          );
        }
      }
    }
  }

  Future<void> _showBatchMoveDialog(BuildContext context) async {
    final albums =
        await ref.read(photoCenterControllerProvider.notifier).listAlbums();
    if (!context.mounted) return;
    final selected = await showFrameChoiceDialog<String>(
      context,
      title: AppLocalizations.of(context).photosSelectAlbum,
      choices: [
        for (final album in albums)
          FrameChoice(
            value: album.id,
            title: album.name,
            subtitle: AppLocalizations.of(
              context,
            ).photosAlbumPhotoCountLabel(album.photoCount),
          ),
      ],
      emptyMessage: AppLocalizations.of(context).photosNoAlbumsCreateFirst,
    );
    if (selected != null && context.mounted) {
      try {
        final task = await ref
            .read(photoCenterControllerProvider.notifier)
            .createBatchTask(taskType: 'MOVE', params: {'albumId': selected});
        if (context.mounted) {
          _showProgressDialog(context, task.id);
        }
      } on Exception {
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosTaskCreateFailed,
            severity: OmniFeedbackSeverity.error,
          );
        }
      }
    }
  }

  /// 两步删除：确认后将所选照片移入回收站。
  Future<void> _confirmBatchTrash(BuildContext context) async {
    final count = state.selectedPhotoIds.length;
    final photoIds = state.selectedPhotoIds.toList(growable: false);
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosMoveToTrashTitle,
      body: l10n.photosMoveToTrashBody(count),
      confirmLabel: l10n.photosMoveToTrashAction,
    );
    if (confirmed && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .movePhotosToTrash(photoIds);
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosTrashMoved,
            severity: OmniFeedbackSeverity.success,
          );
        }
      } on Exception {
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosDeleteFailed,
            severity: OmniFeedbackSeverity.error,
          );
        }
      }
    }
  }

  Future<void> _startBatchDownload(BuildContext context) async {
    try {
      final task = await ref
          .read(photoCenterControllerProvider.notifier)
          .createBatchTask(taskType: 'DOWNLOAD');
      if (context.mounted) {
        _showProgressDialog(context, task.id);
      }
    } on Exception {
      if (context.mounted) {
        showOmniFeedback(
          context,
          AppLocalizations.of(context).photosTaskCreateFailed,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  void _showProgressDialog(BuildContext context, String taskId) {
    ref.read(photoCenterControllerProvider.notifier).toggleSelectionMode();
    showWorkstationDialog<void>(
      context: context,
      dismissible: false,
      builder: (ctx) => BatchProgressDialog(taskId: taskId),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: context.photosColors.onSurfaceVariant,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: context.photosColors.onSurfaceVariant,
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例 selection-bar 的 43px 纯图标动作钮（透明底、深墨前景）。
class _SelectionBarIconButton extends StatelessWidget {
  const _SelectionBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 21, color: context.env.onSelectionBar),
        style: IconButton.styleFrom(
          foregroundColor: context.env.onSelectionBar,
          minimumSize: const Size.square(43),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
