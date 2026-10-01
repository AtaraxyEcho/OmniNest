import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 高密数据表格视图：勾选 / 名称 / 路径 / 上传者 / 大小 / 修改时间 / 格式 /
/// MIME / 操作。
///
/// 全部字段列居左对齐。字段列按可用宽度渐进展开（技能 §3.3 高维技术列），
/// 避免全屏时名称列独占弹性宽度形成大片留白：560 起格式、780 起上传者、
/// 960 起 MIME、1200 起路径（与名称按 1:2 分弹性宽）。节点 ID 属内部
/// 标识，不在用户界面展示。
/// 文件行内操作为 收藏 + 分享 + 预览 + 下载 + 更多（常驻不隐藏），
/// 文件夹仅 更多；⋯ 菜单不再重复快捷项；排序交互保留在
/// 名称/大小/修改时间表头。
class FileTableView extends StatelessWidget {
  const FileTableView({
    required this.files,
    required this.showingRecycleBin,
    required this.enabled,
    required this.actions,
    required this.sortBy,
    this.sortAscending = true,
    this.onToggleSortAscending,
    this.onSortByChanged,
    this.selectedFileIds = const {},
    this.inspectedFileId,
    this.selectionActive = false,
    this.showingFavorites = false,
    this.favoriteIds = const {},
    this.draftFolderName,
    this.onDraftFolderSubmit,
    this.onDraftFolderCancel,
    this.onToggleSelectAll,
    super.key,
  });

  final List<FileNode> files;
  final bool showingRecycleBin;
  final bool enabled;
  final FileNodeActionCallbacks actions;
  final FileBrowserSortBy sortBy;

  /// 排序方向与表头方向切换回调。
  final bool sortAscending;
  final VoidCallback? onToggleSortAscending;

  final ValueChanged<FileBrowserSortBy>? onSortByChanged;

  final Set<String> selectedFileIds;

  /// Inspector 检视中的节点 id。
  final String? inspectedFileId;
  final bool selectionActive;
  final bool showingFavorites;

  /// 已收藏节点 id 集：行内星标按实际收藏态呈现，跨分区一致。
  final Set<String> favoriteIds;

  /// 就地新建文件夹草稿名；非空时表格首行渲染草稿输入行。
  final String? draftFolderName;
  final ValueChanged<String>? onDraftFolderSubmit;
  final VoidCallback? onDraftFolderCancel;

  /// 表头全选框回调：全选态点击=清空选择，否则=全选可见节点。
  final VoidCallback? onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty && draftFolderName == null) {
      return FileNodeEmptyState(showingRecycleBin: showingRecycleBin);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = _TableColumns.of(width.isFinite ? width : 1440);
        return Column(
          children: [
            _TableHeader(
              sortBy: sortBy,
              sortAscending: sortAscending,
              onSortByChanged: onSortByChanged,
              onToggleSortAscending: onToggleSortAscending,
              enabled: enabled,
              columns: columns,
              selectedFileIds: selectedFileIds,
              fileCount: files.length,
              onToggleSelectAll: onToggleSelectAll,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: files.length + (draftFolderName == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (draftFolderName != null && index == 0) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FileDraftFolderRow(
                          defaultName: draftFolderName!,
                          onSubmit: onDraftFolderSubmit ?? (_) {},
                          onCancel: onDraftFolderCancel ?? () {},
                        ),
                        Divider(
                          height: 1,
                          color: context.filesColors.outlineVariant,
                        ),
                      ],
                    );
                  }
                  final file =
                      files[draftFolderName == null ? index : index - 1];
                  return _TableRow(
                    file: file,
                    showingRecycleBin: showingRecycleBin,
                    enabled: enabled,
                    actions: actions,
                    showingFavorites: showingFavorites,
                    selected: selectedFileIds.contains(file.id),
                    inspected: inspectedFileId == file.id,
                    selectionMode: selectionActive,
                    columns: columns,
                    favoriteIds: favoriteIds,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 依据表格可用宽度自适应的字段列集合。
///
/// 阈值按「先保名称/路径弹性列，宽屏逐级展开技术字段」排序；路径列与
/// 名称列按 1:2 分摊弹性宽度，全屏时富余宽度由路径文本吸收而非名称列
/// 留白。
class _TableColumns {
  const _TableColumns({
    required this.showFormat,
    required this.showUploader,
    required this.showMime,
    required this.showPath,
  });

  factory _TableColumns.of(double width) {
    return _TableColumns(
      showFormat: width >= 560,
      showUploader: width >= 780,
      showMime: width >= 960,
      showPath: width >= 1200,
    );
  }

  final bool showFormat;
  final bool showUploader;
  final bool showMime;
  final bool showPath;
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.sortBy,
    required this.onSortByChanged,
    required this.enabled,
    required this.columns,
    required this.selectedFileIds,
    required this.fileCount,
    this.sortAscending = true,
    this.onToggleSortAscending,
    this.onToggleSelectAll,
  });

  final FileBrowserSortBy sortBy;
  final ValueChanged<FileBrowserSortBy>? onSortByChanged;
  final bool enabled;
  final _TableColumns columns;
  final bool sortAscending;
  final VoidCallback? onToggleSortAscending;
  final Set<String> selectedFileIds;
  final int fileCount;
  final VoidCallback? onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.filesColors;
    final selectedCount = selectedFileIds.length;
    final allSelected = fileCount > 0 && selectedCount >= fileCount;
    final partial =
        !allSelected && selectedCount > 0 && selectedCount < fileCount;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Center(
              child: FilesCheckMark(
                value: allSelected,
                indeterminate: partial,
                enabled: enabled && onToggleSelectAll != null && fileCount > 0,
                onChanged: (_) => onToggleSelectAll?.call(),
              ),
            ),
          ),
          Expanded(
            child: _HeaderLabel(
              label: l10n.filesColumnName,
              sort: FileBrowserSortBy.name,
              sortBy: sortBy,
              onSortByChanged: onSortByChanged,
              ascending: sortAscending,
              onToggleAscending: onToggleSortAscending,
            ),
          ),
          if (columns.showPath)
            Expanded(
              flex: 2,
              child: _HeaderLabel(label: l10n.filesInspectorPath),
            ),
          if (columns.showUploader)
            SizedBox(
              width: 112,
              child: _HeaderLabel(label: l10n.filesColumnUploader),
            ),
          SizedBox(
            width: 112,
            child: _HeaderLabel(
              label: l10n.filesColumnSize,
              sort: FileBrowserSortBy.size,
              sortBy: sortBy,
              onSortByChanged: onSortByChanged,
              ascending: !sortAscending,
              onToggleAscending: onToggleSortAscending,
            ),
          ),
          SizedBox(
            width: 144,
            child: _HeaderLabel(
              label: l10n.filesColumnModified,
              sort: FileBrowserSortBy.updatedAt,
              sortBy: sortBy,
              onSortByChanged: onSortByChanged,
              ascending: !sortAscending,
              onToggleAscending: onToggleSortAscending,
            ),
          ),
          if (columns.showFormat)
            SizedBox(
              width: 96,
              child: _HeaderLabel(label: l10n.filesColumnFormat),
            ),
          if (columns.showMime)
            SizedBox(
              width: 140,
              child: _HeaderLabel(label: l10n.filesInspectorMime),
            ),
          SizedBox(
            width: 168,
            child: _HeaderLabel(label: l10n.filesFileActions),
          ),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel({
    required this.label,
    this.sort,
    this.sortBy,
    this.onSortByChanged,
    this.ascending = true,
    this.onToggleAscending,
  });

  final String label;
  final FileBrowserSortBy? sort;
  final FileBrowserSortBy? sortBy;
  final ValueChanged<FileBrowserSortBy>? onSortByChanged;

  /// 激活字段的当前方向与切换回调（点击已激活字段时翻转）。
  final bool ascending;
  final VoidCallback? onToggleAscending;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final sortable = sort != null && onSortByChanged != null;
    final active = sortable && sortBy == sort;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        letterSpacing: 1.2,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active ? colors.onSurface : colors.onSurfaceVariant,
      ),
    );
    final cell = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        if (sortable) ...[
          const SizedBox(width: 2),
          Icon(
            active
                ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 12,
            color: active ? colors.onSurface : colors.outlineVariant,
          ),
        ],
      ],
    );
    if (!sortable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: cell,
      );
    }
    // TextButton 默认将子级居中；表头统一左对齐并与静态列共享 10px 起点。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextButton(
        onPressed: () {
          if (sortBy == sort && onToggleAscending != null) {
            onToggleAscending!();
            return;
          }
          onSortByChanged!(sort!);
        },
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
        ),
        child: cell,
      ),
    );
  }
}

class _TableRow extends StatefulWidget {
  const _TableRow({
    required this.file,
    required this.showingRecycleBin,
    required this.enabled,
    required this.actions,
    required this.showingFavorites,
    required this.selected,
    required this.inspected,
    required this.selectionMode,
    required this.columns,
    required this.favoriteIds,
  });

  final FileNode file;
  final bool showingRecycleBin;
  final bool enabled;
  final FileNodeActionCallbacks actions;
  final bool showingFavorites;
  final bool selected;
  final bool inspected;
  final bool selectionMode;
  final _TableColumns columns;
  final Set<String> favoriteIds;

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final actions = widget.actions;
    final file = widget.file;
    final l10n = AppLocalizations.of(context);
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
    final locale = Localizations.localeOf(context).toString();
    final modified =
        file.updatedAt == null
            ? '—'
            : DateFormat('yyyy-MM-dd HH:mm', locale).format(file.updatedAt!);
    final format = fileFormatLabel(
      file,
      _categoryLabelOf(file, l10n),
      l10n.filesFolder,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: activate != null,
          enabled: activate != null,
          label: file.name,
          onTap: activate,
          child: FocusableActionDetector(
            enabled: activate != null,
            onShowFocusHighlight:
                (focused) => setState(() => _focused = focused),
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
                  singleTap != null
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
              child: GestureDetector(
                excludeFromSemantics: true,
                onTap: singleTap,
                onDoubleTap: activate,
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
                  height: 44,
                  decoration: BoxDecoration(
                    color:
                        widget.selected || widget.inspected
                            ? colors.surfaceContainerHigh
                            : _hovering || _focused
                            ? colors.surfaceContainerHigh.withValues(alpha: 0.4)
                            : Colors.transparent,
                    border:
                        _focused || widget.inspected
                            ? Border.all(
                              color:
                                  _focused
                                      ? colors.onSurface
                                      : colors.selectedBorder,
                              width: 1,
                            )
                            : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: FilesCheckMark(
                          value: widget.selected,
                          enabled: widget.enabled,
                          onChanged:
                              actions.onToggleSelection != null
                                  ? (_) => actions.onToggleSelection!(file.id)
                                  : null,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              // 缩略图优先：图片直接引用实际缩略图，
                              // 其余类型由 FileThumbnail 内建降级到类型图标。
                              FileThumbnail(
                                file: file,
                                size: 20,
                                borderRadius: BorderRadius.zero,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppTypography.bodyMedium,
                                    fontWeight:
                                        widget.selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.columns.showPath)
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              file.normalizedPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _monoStyle(colors),
                            ),
                          ),
                        ),
                      if (widget.columns.showUploader)
                        SizedBox(
                          width: 112,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              file.uploaderName ?? file.uploadedBy ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _monoStyle(colors),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 112,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            file.isFolder
                                ? '—'
                                : formatFileSize(file.sizeBytes),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _monoStyle(colors),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 144,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            modified,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _monoStyle(colors),
                          ),
                        ),
                      ),
                      if (widget.columns.showFormat)
                        SizedBox(
                          width: 96,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              format,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _monoStyle(colors),
                            ),
                          ),
                        ),
                      if (widget.columns.showMime)
                        SizedBox(
                          width: 140,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              file.mimeType ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _monoStyle(colors),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 168,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!widget.showingRecycleBin &&
                                  !file.isFolder &&
                                  actions.onPreview != null)
                                _RowIconAction(
                                  tooltip: l10n.filesPreview,
                                  icon: Icons.visibility_outlined,
                                  onTap: () => actions.onPreview!(file),
                                ),
                              if (!widget.showingRecycleBin &&
                                  !file.isFolder &&
                                  actions.onShare != null)
                                _RowIconAction(
                                  tooltip: l10n.filesShare,
                                  icon: Icons.share_outlined,
                                  onTap: () => actions.onShare!(file),
                                ),
                              if (!widget.showingRecycleBin &&
                                  !file.isFolder &&
                                  actions.onDownload != null)
                                _RowIconAction(
                                  tooltip: l10n.filesDownload,
                                  icon: Icons.download_outlined,
                                  onTap: () => actions.onDownload!(file),
                                ),
                              if (!widget.showingRecycleBin &&
                                  !file.isFolder &&
                                  actions.onToggleFavorite != null)
                                _RowIconAction(
                                  tooltip:
                                      widget.favoriteIds.contains(file.id)
                                          ? l10n.filesRemoveFavorite
                                          : l10n.filesAddFavorite,
                                  icon:
                                      widget.favoriteIds.contains(file.id)
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                  color:
                                      widget.favoriteIds.contains(file.id)
                                          ? FilesWorkstationPalette.amber
                                          : null,
                                  onTap: () => actions.onToggleFavorite!(file),
                                ),
                              if (widget.enabled)
                                PopupMenuButton<FileNodeMenuAction>(
                                  tooltip: l10n.filesMoreActions,
                                  style: const ButtonStyle(
                                    minimumSize: WidgetStatePropertyAll(
                                      Size(32, 32),
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    size: 16,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  itemBuilder:
                                      (context) => buildFileNodeMenuItems(
                                        context,
                                        file: file,
                                        actions: actions,
                                        showingRecycleBin:
                                            widget.showingRecycleBin,
                                        showingFavorites:
                                            widget.showingFavorites,
                                        includeQuickActions: false,
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
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
      ],
    );
  }

  TextStyle _monoStyle(FilesColors colors) {
    return TextStyle(
      fontFamily: AppTypography.monoFamily,
      fontFamilyFallback: AppTypography.monoFamilyFallback,
      fontSize: AppTypography.labelSmall,
      color: colors.onSurfaceVariant,
    );
  }
}

String _categoryLabelOf(FileNode node, AppLocalizations l10n) {
  return switch (fileCategoryOfNode(node)) {
    FileCategoryLabel.image => l10n.filesCategoryImage,
    FileCategoryLabel.video => l10n.filesCategoryVideo,
    FileCategoryLabel.audio => l10n.filesCategoryAudio,
    FileCategoryLabel.document => l10n.filesCategoryDocument,
    FileCategoryLabel.novel => l10n.filesCategoryNovel,
    FileCategoryLabel.comic => l10n.filesCategoryComic,
    FileCategoryLabel.archive => l10n.filesCategoryArchive,
    _ => l10n.filesCategoryOther,
  };
}

class _RowIconAction extends StatefulWidget {
  const _RowIconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// 固定语义色（如已收藏琥珀）；为空时走默认灰阶悬停逻辑。
  final Color? color;

  @override
  State<_RowIconAction> createState() => _RowIconActionState();
}

class _RowIconActionState extends State<_RowIconAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            color:
                _hovering ? colors.surfaceContainerHighest : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 14,
              color:
                  widget.color ??
                  (_hovering ? colors.onSurface : colors.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
