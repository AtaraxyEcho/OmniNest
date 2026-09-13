import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_thumbnail.dart';

class FileGrid extends StatelessWidget {
  const FileGrid({
    required this.files,
    required this.showingRecycleBin,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    required this.onPurge,
    required this.onRestore,
    required this.onOpen,
    this.onCopy,
    this.onMove,
    this.onMoveToSharedSpace,
    this.onMoveToPersonalSpace,
    this.onDownload,
    this.onShare,
    this.onPreview,
    this.onToggleFavorite,
    this.onShowVersions,
    this.selectedFileIds = const {},
    this.onToggleSelection,
    this.selectionActive = false,
    this.showingFavorites = false,
    super.key,
  });

  final List<FileNode> files;
  final bool showingRecycleBin;
  final bool enabled;
  final ValueChanged<FileNode> onRename;
  final ValueChanged<FileNode> onDelete;
  final ValueChanged<FileNode> onPurge;
  final ValueChanged<FileNode> onRestore;
  final ValueChanged<FileNode> onOpen;
  final ValueChanged<FileNode>? onCopy;
  final ValueChanged<FileNode>? onMove;
  final ValueChanged<FileNode>? onMoveToSharedSpace;
  final ValueChanged<FileNode>? onMoveToPersonalSpace;
  final ValueChanged<FileNode>? onDownload;
  final ValueChanged<FileNode>? onShare;
  final ValueChanged<FileNode>? onPreview;
  final ValueChanged<FileNode>? onToggleFavorite;
  final ValueChanged<FileNode>? onShowVersions;
  final Set<String> selectedFileIds;
  final ValueChanged<String>? onToggleSelection;

  /// 多选模式是否激活：激活时才显示 Checkbox，卡片点击切换选中。
  final bool selectionActive;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 64),
        decoration: BoxDecoration(
          border: Border.all(
            color: context.filesColors.outlineVariant.withValues(alpha: 0.32),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              showingRecycleBin
                  ? Icons.delete_sweep_outlined
                  : Icons.folder_open_outlined,
              color: context.filesColors.primary,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              showingRecycleBin
                  ? AppLocalizations.of(context).filesRecycleBinEmpty
                  : AppLocalizations.of(context).filesEmpty,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount =
            width >= 1160
                ? 5
                : width >= 900
                ? 4
                : width >= 640
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: files.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.34,
          ),
          itemBuilder:
              (context, index) => _FileTile(
                file: files[index],
                showingRecycleBin: showingRecycleBin,
                enabled: enabled,
                onRename: onRename,
                onDelete: onDelete,
                onPurge: onPurge,
                onRestore: onRestore,
                onOpen: onOpen,
                onCopy: onCopy,
                onShowVersions: onShowVersions,
                onMove: onMove,
                onMoveToSharedSpace: onMoveToSharedSpace,
                onMoveToPersonalSpace: onMoveToPersonalSpace,
                onDownload: onDownload,
                onShare: onShare,
                onPreview: onPreview,
                onToggleFavorite: onToggleFavorite,
                showingFavorites: showingFavorites,
                selected: selectedFileIds.contains(files[index].id),
                selectionMode: selectionActive,
                onToggleSelection:
                    onToggleSelection != null
                        ? () => onToggleSelection!(files[index].id)
                        : null,
              ),
        );
      },
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({
    required this.file,
    required this.showingRecycleBin,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    required this.onPurge,
    required this.onRestore,
    required this.onOpen,
    this.onCopy,
    this.onMove,
    this.onMoveToSharedSpace,
    this.onMoveToPersonalSpace,
    this.onDownload,
    this.onShare,
    this.onPreview,
    this.onToggleFavorite,
    this.onShowVersions,
    this.showingFavorites = false,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelection,
  });

  final FileNode file;
  final bool showingRecycleBin;
  final bool enabled;
  final ValueChanged<FileNode> onRename;
  final ValueChanged<FileNode> onDelete;
  final ValueChanged<FileNode> onPurge;
  final ValueChanged<FileNode> onRestore;
  final ValueChanged<FileNode> onOpen;
  final ValueChanged<FileNode>? onCopy;
  final ValueChanged<FileNode>? onMove;
  final ValueChanged<FileNode>? onMoveToSharedSpace;
  final ValueChanged<FileNode>? onMoveToPersonalSpace;
  final ValueChanged<FileNode>? onDownload;
  final ValueChanged<FileNode>? onShare;
  final ValueChanged<FileNode>? onPreview;
  final ValueChanged<FileNode>? onToggleFavorite;
  final ValueChanged<FileNode>? onShowVersions;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelection;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.file.isFolder
            ? context.filesColors.tertiary
            : context.filesColors.primary;
    final bool selectionToggleable =
        widget.selectionMode && widget.onToggleSelection != null;
    final VoidCallback? activate =
        selectionToggleable
            ? () => widget.onToggleSelection!()
            : widget.enabled && !widget.showingRecycleBin
            ? widget.file.isFolder
                ? () => widget.onOpen(widget.file)
                : widget.onPreview != null
                ? () => widget.onPreview!(widget.file)
                : null
            : null;
    final VoidCallback? longPress =
        widget.enabled && widget.onToggleSelection != null
            ? () {
              HapticFeedback.mediumImpact();
              widget.onToggleSelection!();
            }
            : null;
    return Semantics(
      button: activate != null,
      label: widget.file.name,
      onTap: activate,
      child: FocusableActionDetector(
        enabled: activate != null,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              activate?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          cursor:
              activate != null
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: activate,
            onLongPress: longPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color:
                    widget.selected
                        ? context.filesColors.primary.withValues(alpha: 0.12)
                        : _hovering || _focused
                        ? context.filesColors.surfaceContainerHigh.withValues(
                          alpha: 0.78,
                        )
                        : context.filesColors.surfaceContainerHigh.withValues(
                          alpha: 0.58,
                        ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      widget.selected
                          ? context.filesColors.primary.withValues(alpha: 0.6)
                          : _hovering || _focused
                          ? accent.withValues(alpha: 0.36)
                          : context.filesColors.outlineVariant.withValues(
                            alpha: 0.26,
                          ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.selectionMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Checkbox(
                              value: widget.selected,
                              onChanged:
                                  widget.onToggleSelection != null
                                      ? (_) => widget.onToggleSelection!()
                                      : null,
                            ),
                          ),
                        FileThumbnail(file: widget.file, size: 42),
                        const Spacer(),
                        _FileTileMenu(
                          file: widget.file,
                          showingRecycleBin: widget.showingRecycleBin,
                          enabled: widget.enabled,
                          onRename: widget.onRename,
                          onDelete: widget.onDelete,
                          onPurge: widget.onPurge,
                          onRestore: widget.onRestore,
                          onOpen: widget.onOpen,
                          onCopy: widget.onCopy,
                          onMove: widget.onMove,
                          onMoveToSharedSpace: widget.onMoveToSharedSpace,
                          onMoveToPersonalSpace: widget.onMoveToPersonalSpace,
                          onDownload: widget.onDownload,
                          onShare: widget.onShare,
                          onPreview: widget.onPreview,
                          onToggleFavorite: widget.onToggleFavorite,
                          onShowVersions: widget.onShowVersions,
                          showingFavorites: widget.showingFavorites,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      widget.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.file.isFolder
                          ? AppLocalizations.of(context).filesFolder
                          : formatFileSize(widget.file.sizeBytes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTileMenu extends StatelessWidget {
  const _FileTileMenu({
    required this.file,
    required this.showingRecycleBin,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    required this.onPurge,
    required this.onRestore,
    required this.onOpen,
    this.onCopy,
    this.onMove,
    this.onMoveToSharedSpace,
    this.onMoveToPersonalSpace,
    this.onDownload,
    this.onShare,
    this.onPreview,
    this.onToggleFavorite,
    this.onShowVersions,
    this.showingFavorites = false,
  });

  final FileNode file;
  final bool showingRecycleBin;
  final bool enabled;
  final ValueChanged<FileNode> onRename;
  final ValueChanged<FileNode> onDelete;
  final ValueChanged<FileNode> onPurge;
  final ValueChanged<FileNode> onRestore;
  final ValueChanged<FileNode> onOpen;
  final ValueChanged<FileNode>? onCopy;
  final ValueChanged<FileNode>? onMove;
  final ValueChanged<FileNode>? onMoveToSharedSpace;
  final ValueChanged<FileNode>? onMoveToPersonalSpace;
  final ValueChanged<FileNode>? onDownload;
  final ValueChanged<FileNode>? onShare;
  final ValueChanged<FileNode>? onPreview;
  final ValueChanged<FileNode>? onToggleFavorite;
  final ValueChanged<FileNode>? onShowVersions;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FileAction>(
      tooltip: AppLocalizations.of(context).filesFileActions,
      icon: const Icon(Icons.more_horiz_rounded),
      enabled: enabled,
      onSelected: (action) {
        switch (action) {
          case _FileAction.open:
            onOpen(file);
          case _FileAction.rename:
            onRename(file);
          case _FileAction.copy:
            onCopy?.call(file);
          case _FileAction.move:
            onMove?.call(file);
          case _FileAction.moveToShared:
            onMoveToSharedSpace?.call(file);
          case _FileAction.moveToPersonal:
            onMoveToPersonalSpace?.call(file);
          case _FileAction.download:
            onDownload?.call(file);
          case _FileAction.share:
            onShare?.call(file);
          case _FileAction.favorite:
            onToggleFavorite?.call(file);
          case _FileAction.preview:
            onPreview?.call(file);
          case _FileAction.delete:
            onDelete(file);
          case _FileAction.purge:
            onPurge(file);
          case _FileAction.restore:
            onRestore(file);
          case _FileAction.versions:
            onShowVersions?.call(file);
        }
      },
      itemBuilder:
          (context) => [
            if (!showingRecycleBin && file.isFolder)
              PopupMenuItem(
                value: _FileAction.open,
                child: Text(AppLocalizations.of(context).filesOpen),
              ),
            if (showingRecycleBin)
              PopupMenuItem(
                value: _FileAction.restore,
                child: Text(AppLocalizations.of(context).filesRestore),
              )
            else ...[
              PopupMenuItem(
                value: _FileAction.rename,
                child: Text(AppLocalizations.of(context).filesRename),
              ),
              if (onCopy != null && !file.isFolder)
                PopupMenuItem(
                  value: _FileAction.versions,
                  child: ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: Text(
                      AppLocalizations.of(context).filesVersionsTitle,
                    ),
                    dense: true,
                  ),
                ),
              if (onCopy != null && !file.isFolder)
                PopupMenuItem(
                  value: _FileAction.copy,
                  child: ListTile(
                    leading: const Icon(Icons.file_copy_outlined),
                    title: Text(
                      AppLocalizations.of(context).filesCopyToEllipsis,
                    ),
                    dense: true,
                  ),
                ),
              if (onMove != null)
                PopupMenuItem(
                  value: _FileAction.move,
                  child: Text(AppLocalizations.of(context).filesMoveToEllipsis),
                ),
              if (onMoveToSharedSpace != null)
                PopupMenuItem(
                  value: _FileAction.moveToShared,
                  child: Text(AppLocalizations.of(context).filesMoveToShared),
                ),
              if (onMoveToPersonalSpace != null)
                PopupMenuItem(
                  value: _FileAction.moveToPersonal,
                  child: Text(AppLocalizations.of(context).filesMoveToPersonal),
                ),
              if (onDownload != null && !file.isFolder)
                PopupMenuItem(
                  value: _FileAction.download,
                  child: Text(AppLocalizations.of(context).filesDownload),
                ),
              if (onShare != null && !file.isFolder)
                PopupMenuItem(
                  value: _FileAction.share,
                  child: Text(AppLocalizations.of(context).filesShare),
                ),
              if (onToggleFavorite != null && !file.isFolder)
                PopupMenuItem(
                  value: _FileAction.favorite,
                  child: Text(
                    showingFavorites
                        ? AppLocalizations.of(context).filesRemoveFavorite
                        : AppLocalizations.of(context).filesAddFavorite,
                  ),
                ),
              if (onPreview != null && !file.isFolder)
                PopupMenuItem(
                  value: _FileAction.preview,
                  child: Text(AppLocalizations.of(context).filesPreview),
                ),
              PopupMenuItem(
                value: _FileAction.delete,
                child: Text(AppLocalizations.of(context).filesMoveToRecycleBin),
              ),
            ],
            if (showingRecycleBin)
              PopupMenuItem(
                value: _FileAction.purge,
                child: Text(AppLocalizations.of(context).filesPurge),
              ),
          ],
    );
  }
}

enum _FileAction {
  versions,
  open,
  favorite,
  copy,
  rename,
  move,
  moveToShared,
  moveToPersonal,
  download,
  share,
  preview,
  delete,
  purge,
  restore,
}
