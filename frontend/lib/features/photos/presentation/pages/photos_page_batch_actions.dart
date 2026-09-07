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
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: context.photosColors.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
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
              fontSize: 14,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).photosTaskCreateFailed,
              ),
            ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).photosTaskCreateFailed,
              ),
            ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosTrashMoved),
            ),
          );
        }
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosDeleteFailed),
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).photosTaskCreateFailed),
          ),
        );
      }
    }
  }

  void _showProgressDialog(BuildContext context, String taskId) {
    ref.read(photoCenterControllerProvider.notifier).toggleSelectionMode();
    showDialog(
      context: context,
      barrierDismissible: false,
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
                  fontSize: 13,
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
