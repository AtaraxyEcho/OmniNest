import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 卡片网格视图：纯平直角卡片 + 1px hairline 边框 + ✔ 文本复选框。
///
/// 卡片内容水平内边距固定 16px，与工作区一体化工具栏的全选框保持
/// 中轴线像素级对齐。
class FileGrid extends StatelessWidget {
  const FileGrid({
    required this.files,
    required this.showingRecycleBin,
    required this.enabled,
    required this.actions,
    this.selectedFileIds = const {},
    this.inspectedFileId,
    this.selectionActive = false,
    this.showingFavorites = false,
    this.favoriteIds = const {},
    this.draftFolderName,
    this.onDraftFolderSubmit,
    this.onDraftFolderCancel,
    super.key,
  });

  final List<FileNode> files;
  final bool showingRecycleBin;
  final bool enabled;
  final FileNodeActionCallbacks actions;

  final Set<String> selectedFileIds;

  /// Inspector 检视中的节点 id。
  final String? inspectedFileId;

  /// 多选模式是否激活：激活时才显示复选框，卡片点击切换选中。
  final bool selectionActive;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  /// 已收藏节点 id 集：卡片星标按实际收藏态呈现，与表格一致。
  final Set<String> favoriteIds;

  /// 就地新建文件夹草稿名；非空时网格首格渲染草稿输入。
  final String? draftFolderName;
  final ValueChanged<String>? onDraftFolderSubmit;
  final VoidCallback? onDraftFolderCancel;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty && draftFolderName == null) {
      return FileNodeEmptyState(showingRecycleBin: showingRecycleBin);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 多选态卡片行内要并排复选框 + 缩略图 + 菜单钮，两列时内容宽度
        // 不足会溢出；手机宽度改单列，既不裁控件也不缩小命中区。
        final crossAxisCount =
            selectionActive && width < 640
                ? 1
                : width >= 1160
                ? 5
                : width >= 900
                ? 4
                : width >= 640
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: false,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: files.length + (draftFolderName == null ? 0 : 1),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.34,
          ),
          itemBuilder: (context, index) {
            if (draftFolderName != null && index == 0) {
              return FileDraftFolderRow(
                defaultName: draftFolderName!,
                onSubmit: onDraftFolderSubmit ?? (_) {},
                onCancel: onDraftFolderCancel ?? () {},
              );
            }
            final file = files[draftFolderName == null ? index : index - 1];
            return _FileTile(
              file: file,
              showingRecycleBin: showingRecycleBin,
              enabled: enabled,
              actions: actions,
              showingFavorites: showingFavorites,
              selected: selectedFileIds.contains(file.id),
              inspected: inspectedFileId == file.id,
              selectionMode: selectionActive,
              favoriteIds: favoriteIds,
            );
          },
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
    required this.actions,
    required this.showingFavorites,
    this.selected = false,
    this.inspected = false,
    this.selectionMode = false,
    this.favoriteIds = const {},
  });

  final FileNode file;
  final bool showingRecycleBin;
  final bool enabled;
  final FileNodeActionCallbacks actions;
  final bool showingFavorites;
  final bool selected;
  final bool inspected;
  final bool selectionMode;
  final Set<String> favoriteIds;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final actions = widget.actions;
    final file = widget.file;
    final bool selectionToggleable =
        widget.selectionMode && actions.onToggleSelection != null;
    final VoidCallback? activate =
        widget.enabled && !widget.showingRecycleBin
            ? file.isFolder
                ? () => actions.onOpen?.call(file)
                : actions.onPreview != null
                ? () => actions.onPreview!(file)
                : null
            : null;
    // 单击 = 检视（再次单击已检视条目 Toggle 收起）；双击 = 打开/预览；
    // 多选态下单击仍是切换勾选。
    final VoidCallback? singleTap =
        selectionToggleable
            ? () => actions.onToggleSelection!(file.id)
            : widget.enabled && actions.onInspect != null
            ? () => actions.onInspect!(file.id)
            : null;
    final VoidCallback? longPress =
        widget.enabled && actions.onToggleSelection != null
            ? () {
              HapticFeedback.mediumImpact();
              actions.onToggleSelection!(file.id);
            }
            : null;
    return Semantics(
      button: activate != null,
      enabled: activate != null,
      label: file.name,
      onTap: activate,
      onLongPress: longPress,
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
            excludeFromSemantics: true,
            onTap: singleTap,
            onDoubleTap: activate,
            onLongPress: longPress,
            onSecondaryTapUp:
                widget.enabled
                    ? (details) => showFileNodeMenuAt(
                      context,
                      details.globalPosition,
                      file: file,
                      actions: actions,
                      showingRecycleBin: widget.showingRecycleBin,
                      showingFavorites: widget.showingFavorites,
                    )
                    : null,
            child: AnimatedContainer(
              duration: MotionToken.fast,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    widget.selected
                        ? colors.sidebarSelectedBg
                        : _hovering || _focused
                        ? colors.surfaceContainerHigh
                        : colors.surfaceContainerLow,
                border: Border.all(
                  color:
                      widget.selected
                          ? colors.selectedBorder
                          : _hovering || _focused
                          ? colors.selectedBorder
                          : colors.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.selectionMode) ...[
                        FilesCheckMark(
                          value: widget.selected,
                          onChanged:
                              actions.onToggleSelection != null
                                  ? (_) => actions.onToggleSelection!(file.id)
                                  : null,
                        ),
                        const SizedBox(width: 8),
                      ],
                      FileThumbnail(file: file, size: 40, zoomOnHover: true),
                      const Spacer(),
                      if (widget.enabled)
                        if (!widget.showingRecycleBin &&
                            !file.isFolder &&
                            actions.onToggleFavorite != null)
                          _GridFavoriteStar(
                            favorited: widget.favoriteIds.contains(file.id),
                            onToggle: () => actions.onToggleFavorite!(file),
                          ),
                      PopupMenuButton<FileNodeMenuAction>(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(44, 44)),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        tooltip: AppLocalizations.of(context).filesFileActions,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        itemBuilder:
                            (context) => buildFileNodeMenuItems(
                              context,
                              file: file,
                              actions: actions,
                              showingRecycleBin: widget.showingRecycleBin,
                              showingFavorites: widget.showingFavorites,
                              favorited: widget.favoriteIds.contains(file.id),
                            ),
                        onSelected:
                            (action) => dispatchFileNodeMenuAction(
                              action,
                              file,
                              actions,
                            ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.isFolder
                        ? AppLocalizations.of(context).filesFolder
                        : formatFileSize(file.sizeBytes),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.monoFamily,
                      fontFamilyFallback: AppTypography.monoFamilyFallback,
                      fontSize: AppTypography.labelSmall,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 网格卡片内联收藏星标：与表格行内星标同图标语义（实心=已收藏），
/// 28px 命中区、悬停提示，点击切换收藏。
class _GridFavoriteStar extends StatefulWidget {
  const _GridFavoriteStar({required this.favorited, required this.onToggle});

  final bool favorited;
  final VoidCallback onToggle;

  @override
  State<_GridFavoriteStar> createState() => _GridFavoriteStarState();
}

class _GridFavoriteStarState extends State<_GridFavoriteStar> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.filesColors;
    return Tooltip(
      message:
          widget.favorited ? l10n.filesRemoveFavorite : l10n.filesAddFavorite,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            color:
                _hovering ? colors.surfaceContainerHighest : Colors.transparent,
            child: Icon(
              widget.favorited ? Icons.star_rounded : Icons.star_border_rounded,
              size: 16,
              color:
                  widget.favorited
                      ? FilesWorkstationPalette.amber
                      : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
