import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_thumbnail.dart';

enum _FileListAction {
  favorite,
  rename,
  move,
  moveToShared,
  moveToPersonal,
  download,
  share,
  delete,
  restore,
  purge,
}

class FileList extends StatefulWidget {
  const FileList({
    required this.files,
    required this.showingRecycleBin,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    required this.onPurge,
    required this.onRestore,
    required this.onOpen,
    this.onMove,
    this.onMoveToSharedSpace,
    this.onMoveToPersonalSpace,
    this.onDownload,
    this.onShare,
    this.onPreview,
    this.onToggleFavorite,
    this.selectedFileIds = const {},
    this.onToggleSelection,
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
  final ValueChanged<FileNode>? onMove;
  final ValueChanged<FileNode>? onMoveToSharedSpace;
  final ValueChanged<FileNode>? onMoveToPersonalSpace;
  final ValueChanged<FileNode>? onDownload;
  final ValueChanged<FileNode>? onShare;
  final ValueChanged<FileNode>? onPreview;
  final ValueChanged<FileNode>? onToggleFavorite;
  final Set<String> selectedFileIds;
  final ValueChanged<String>? onToggleSelection;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  @override
  State<FileList> createState() => _FileListState();
}

class _FileListState extends State<FileList>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  int _staggerCount = 0;

  /// 标记当前是否为刷新/切换（非首次加载）
  bool _isRefresh = false;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _runStagger();
  }

  @override
  void didUpdateWidget(FileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在列表从空变为非空、或文件列表实际变化时播放动画
    // selectedFileIds 变化不应触发重新动画
    final wasEmpty = oldWidget.files.isEmpty;
    final isEmpty = widget.files.isEmpty;
    final filesChanged =
        wasEmpty ||
        isEmpty ||
        widget.files.length != oldWidget.files.length ||
        widget.files.first.id != oldWidget.files.first.id;
    if (!isEmpty && filesChanged) {
      _isRefresh = !wasEmpty;
      _runStagger();
    }
  }

  void _runStagger() {
    _staggerCount = widget.files.length;
    // 首次加载 400ms，刷新/切换 600ms（更丝滑的淡入淡出）
    _staggerController.duration = Duration(
      milliseconds: _isRefresh ? 600 : 400,
    );
    _staggerController.reset();
    if (_staggerCount > 0) {
      _staggerController.forward();
    }
    _isRefresh = false;
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 64),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.32),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              widget.showingRecycleBin
                  ? Icons.delete_sweep_outlined
                  : Icons.folder_open_outlined,
              color: context.filesColors.primary,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              widget.showingRecycleBin
                  ? AppLocalizations.of(context).filesRecycleBinEmpty
                  : AppLocalizations.of(context).filesEmpty,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < widget.files.length; i++) ...[
          _StaggeredFileRow(
            index: i,
            totalCount: _staggerCount,
            animation: _staggerController,
            child: _FileRow(
              file: widget.files[i],
              showingRecycleBin: widget.showingRecycleBin,
              enabled: widget.enabled,
              onRename: widget.onRename,
              onDelete: widget.onDelete,
              onPurge: widget.onPurge,
              onRestore: widget.onRestore,
              onOpen: widget.onOpen,
              onMove: widget.onMove,
              onMoveToSharedSpace: widget.onMoveToSharedSpace,
              onMoveToPersonalSpace: widget.onMoveToPersonalSpace,
              onDownload: widget.onDownload,
              onShare: widget.onShare,
              onPreview: widget.onPreview,
              onToggleFavorite: widget.onToggleFavorite,
              showingFavorites: widget.showingFavorites,
              selected: widget.selectedFileIds.contains(widget.files[i].id),
              selectionMode: widget.onToggleSelection != null,
              swipeActionsEnabled:
                  Theme.of(context).platform == TargetPlatform.android ||
                  Theme.of(context).platform == TargetPlatform.iOS,
              onToggleSelection:
                  widget.onToggleSelection != null
                      ? () => widget.onToggleSelection!(widget.files[i].id)
                      : null,
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

/// Stagger 入场动画包装器 — 每行从右侧滑入 + 淡入
class _StaggeredFileRow extends StatelessWidget {
  const _StaggeredFileRow({
    required this.index,
    required this.totalCount,
    required this.animation,
    required this.child,
  });

  final int index;
  final int totalCount;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 每行延迟比例：0.0 ~ 1.0，间隔 50ms 对应的比例
    final delay = (index * 50.0 / (totalCount * 50.0 + 200.0)).clamp(0.0, 0.8);
    final end = (delay + 0.4).clamp(0.0, 1.0);

    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(delay, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(24 * (1.0 - curved.value), 0),
          child: Opacity(opacity: curved.value, child: child),
        );
      },
      child: child,
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.showingRecycleBin,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    required this.onPurge,
    required this.onRestore,
    required this.onOpen,
    this.onMove,
    this.onMoveToSharedSpace,
    this.onMoveToPersonalSpace,
    this.onDownload,
    this.onShare,
    this.onPreview,
    this.onToggleFavorite,
    this.showingFavorites = false,
    this.selected = false,
    this.selectionMode = false,
    this.swipeActionsEnabled = false,
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
  final ValueChanged<FileNode>? onMove;
  final ValueChanged<FileNode>? onMoveToSharedSpace;
  final ValueChanged<FileNode>? onMoveToPersonalSpace;
  final ValueChanged<FileNode>? onDownload;
  final ValueChanged<FileNode>? onShare;
  final ValueChanged<FileNode>? onPreview;
  final ValueChanged<FileNode>? onToggleFavorite;
  final bool selected;
  final bool selectionMode;
  final bool swipeActionsEnabled;
  final VoidCallback? onToggleSelection;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  /// 是否允许左滑操作（非回收站模式下允许）
  bool get swipeable => swipeActionsEnabled && !showingRecycleBin && enabled;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final VoidCallback? activate =
        widget.enabled && !widget.showingRecycleBin
            ? file.isFolder
                ? () => widget.onOpen(file)
                : widget.onPreview != null
                ? () => widget.onPreview!(file)
                : null
            : null;
    final row = Semantics(
      button: activate != null,
      label: file.name,
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    widget.selected
                        ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08)
                        : _hovering || _focused
                        ? Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.06)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border:
                    _focused
                        ? Border.all(
                          color: context.filesColors.primary,
                          width: 1.5,
                        )
                        : null,
              ),
              child: Row(
                children: [
                  if (widget.selectionMode) ...[
                    Checkbox(
                      value: widget.selected,
                      onChanged:
                          widget.onToggleSelection != null
                              ? (_) => widget.onToggleSelection!()
                              : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                  ],
                  FileThumbnail(file: file, size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.bodyLarge,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${file.isFolder ? AppLocalizations.of(context).filesFolder : formatFileSize(file.sizeBytes)}  ·  ${file.normalizedPath}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: context.filesColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 文件夹：打开按钮 + 更多菜单
                  if (!widget.showingRecycleBin && file.isFolder)
                    _RowIconButton(
                      tooltip: AppLocalizations.of(context).filesOpenTooltip,
                      icon: Icons.chevron_right_rounded,
                      enabled: widget.enabled,
                      onTap: () => widget.onOpen(file),
                    ),
                  // 更多操作菜单
                  PopupMenuButton<_FileListAction>(
                    enabled: widget.enabled,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: context.filesColors.onSurfaceVariant,
                    ),
                    tooltip: AppLocalizations.of(context).filesMoreActions,
                    itemBuilder:
                        (context) =>
                            widget.showingRecycleBin
                                ? [
                                  PopupMenuItem(
                                    value: _FileListAction.restore,
                                    child: ListTile(
                                      leading: Icon(Icons.restore_rounded),
                                      title: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).filesRestore,
                                      ),
                                      dense: true,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: _FileListAction.purge,
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.delete_forever_outlined,
                                        color: context.filesColors.error,
                                      ),
                                      title: Text(
                                        AppLocalizations.of(context).filesPurge,
                                        style: TextStyle(
                                          color: context.filesColors.error,
                                        ),
                                      ),
                                      dense: true,
                                    ),
                                  ),
                                ]
                                : [
                                  PopupMenuItem(
                                    value: _FileListAction.rename,
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.drive_file_rename_outline,
                                      ),
                                      title: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).filesRename,
                                      ),
                                      dense: true,
                                    ),
                                  ),
                                  if (widget.onMove != null)
                                    PopupMenuItem(
                                      value: _FileListAction.move,
                                      child: ListTile(
                                        leading: Icon(
                                          Icons.drive_file_move_outlined,
                                        ),
                                        title: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).filesMoveToEllipsis,
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                  if (widget.onMoveToSharedSpace != null)
                                    PopupMenuItem(
                                      value: _FileListAction.moveToShared,
                                      child: ListTile(
                                        leading: Icon(
                                          Icons.workspaces_outlined,
                                        ),
                                        title: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).filesMoveToShared,
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                  if (widget.onMoveToPersonalSpace != null)
                                    PopupMenuItem(
                                      value: _FileListAction.moveToPersonal,
                                      child: ListTile(
                                        leading: Icon(Icons.person_outline),
                                        title: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).filesMoveToPersonal,
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                  if (widget.onDownload != null &&
                                      !file.isFolder)
                                    PopupMenuItem(
                                      value: _FileListAction.download,
                                      child: ListTile(
                                        leading: Icon(Icons.download_outlined),
                                        title: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).filesDownload,
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                  if (widget.onShare != null && !file.isFolder)
                                    PopupMenuItem(
                                      value: _FileListAction.share,
                                      child: ListTile(
                                        leading: Icon(Icons.share_outlined),
                                        title: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).filesShare,
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                  if (widget.onToggleFavorite != null &&
                                      !file.isFolder)
                                    PopupMenuItem(
                                      value: _FileListAction.favorite,
                                      child: ListTile(
                                        leading: Icon(
                                          widget.showingFavorites
                                              ? Icons.star_border_rounded
                                              : Icons.star_rounded,
                                        ),
                                        title: Text(
                                          widget.showingFavorites
                                              ? AppLocalizations.of(
                                                context,
                                              ).filesRemoveFavorite
                                              : AppLocalizations.of(
                                                context,
                                              ).filesAddFavorite,
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: _FileListAction.delete,
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.delete_outline_rounded,
                                        color: context.filesColors.error,
                                      ),
                                      title: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).filesDelete,
                                        style: TextStyle(
                                          color: context.filesColors.error,
                                        ),
                                      ),
                                      dense: true,
                                    ),
                                  ),
                                ],
                    onSelected: (action) {
                      switch (action) {
                        case _FileListAction.rename:
                          widget.onRename(file);
                        case _FileListAction.move:
                          widget.onMove?.call(file);
                        case _FileListAction.moveToShared:
                          widget.onMoveToSharedSpace?.call(file);
                        case _FileListAction.moveToPersonal:
                          widget.onMoveToPersonalSpace?.call(file);
                        case _FileListAction.download:
                          widget.onDownload?.call(file);
                        case _FileListAction.share:
                          widget.onShare?.call(file);
                        case _FileListAction.favorite:
                          widget.onToggleFavorite?.call(file);
                        case _FileListAction.delete:
                          widget.onDelete(file);
                        case _FileListAction.restore:
                          widget.onRestore(file);
                        case _FileListAction.purge:
                          widget.onPurge(file);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 非回收站且启用时，包裹 _SwipeableRow 实现左滑操作
    if (!widget.swipeable) return row;

    final actions = <Widget>[
      if (widget.onShare != null && !file.isFolder)
        _SwipeAction(
          icon: Icons.share_rounded,
          label: AppLocalizations.of(context).filesShare,
          color: context.filesColors.tertiary,
          onTap: () => widget.onShare!(file),
        ),
      _SwipeAction(
        icon: Icons.delete_outline_rounded,
        label: AppLocalizations.of(context).filesDelete,
        color: context.filesColors.error,
        onTap: () => widget.onDelete(file),
      ),
    ];

    return _SwipeableRow(actions: actions, child: row);
  }
}

/// 左滑保持展开的行包装器
///
/// 左滑露出操作按钮，松手后 Q 弹展开并保持。
/// 点击操作按钮执行动作并收回；点击行内容区域收回。
class _SwipeableRow extends StatefulWidget {
  const _SwipeableRow({required this.child, required this.actions});

  final Widget child;
  final List<Widget> actions;

  @override
  State<_SwipeableRow> createState() => _SwipeableRowState();
}

class _SwipeableRowState extends State<_SwipeableRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isOpen = false;

  /// 操作按钮区域总宽度（每个 56 + 间距 12 + 右侧 padding 16）
  double get _actionWidth =>
      widget.actions.length * 56.0 + (widget.actions.length - 1) * 12.0 + 16.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    // 仅响应左滑（负值 → controller value 增大）
    if (delta >= 0 && _controller.value <= 0) return;
    final newValue = (_controller.value - delta / _actionWidth).clamp(0.0, 1.0);
    _controller.value = newValue;
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = _controller.value > 0.4 || velocity < -300;
    _animateTo(shouldOpen ? 1.0 : 0.0);
    _isOpen = shouldOpen;
  }

  void _animateTo(double target) {
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _close() {
    if (!_isOpen) return;
    _isOpen = false;
    _animateTo(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onTap: _isOpen ? _close : null,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // 操作按钮层 — 固定在右侧，被行内容遮盖
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    _buildActionButton(widget.actions[i]),
                  ],
                ],
              ),
            ),
          ),
          // 行内容 — 左滑时左移，露出操作按钮
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return ClipRect(
                child: Transform.translate(
                  offset: Offset(-_controller.value * _actionWidth, 0),
                  child: child,
                ),
              );
            },
            // 不透明背景 — 遮盖底层操作按钮
            child: DecoratedBox(
              decoration: BoxDecoration(color: context.filesColors.surface),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(Widget action) {
    if (action is _SwipeAction) {
      return GestureDetector(
        onTap: () {
          action.onTap();
          _close();
        },
        child: action,
      );
    }
    return action;
  }
}

/// 左滑操作按钮
class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              height: 1,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowIconButton extends StatefulWidget {
  const _RowIconButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RowIconButton> createState() => _RowIconButtonState();
}

class _RowIconButtonState extends State<_RowIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = context.filesColors.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor:
            widget.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color:
                  _hovering && widget.enabled
                      ? baseColor.withValues(alpha: 0.10)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color:
                  widget.enabled
                      ? (_hovering
                          ? baseColor
                          : context.filesColors.onSurfaceVariant)
                      : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
