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
import 'package:omninest/core/theme/motion_token.dart';

/// 列表视图：hairline 行线 + 纯平直角行 + ✔ 文本复选框。
///
/// 入场动画由外层视图切换 180ms 淡入微移统一承担，行级 stagger 移除。
class FileList extends StatelessWidget {
  const FileList({
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

  /// 多选模式是否激活：激活时才显示复选框，行点击切换选中。
  final bool selectionActive;

  /// 当前是否处于收藏分区（决定收藏菜单项的文案与图标）。
  final bool showingFavorites;

  /// 已收藏节点 id 集：菜单收藏项随实际态呈现。
  final Set<String> favoriteIds;

  /// 就地新建文件夹草稿名；非空时列表首行渲染草稿输入行。
  final String? draftFolderName;
  final ValueChanged<String>? onDraftFolderSubmit;
  final VoidCallback? onDraftFolderCancel;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty && draftFolderName == null) {
      return FileNodeEmptyState(showingRecycleBin: showingRecycleBin);
    }
    final mobile =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    return ListView.builder(
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
              Divider(height: 1),
            ],
          );
        }
        final file = files[draftFolderName == null ? index : index - 1];
        final row = _FileRow(
          file: file,
          showingRecycleBin: showingRecycleBin,
          enabled: enabled,
          actions: actions,
          showingFavorites: showingFavorites,
          selected: selectedFileIds.contains(file.id),
          inspected: inspectedFileId == file.id,
          selectionMode: selectionActive,
          swipeActionsEnabled: mobile,
          favoriteIds: favoriteIds,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [row, const Divider(height: 1)],
        );
      },
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.showingRecycleBin,
    required this.enabled,
    required this.actions,
    required this.showingFavorites,
    this.selected = false,
    this.inspected = false,
    this.selectionMode = false,
    this.swipeActionsEnabled = false,
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
  final bool swipeActionsEnabled;
  final Set<String> favoriteIds;

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
    final colors = context.filesColors;
    final actions = widget.actions;
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
    // 长按是进入多选的触屏入口，多选态由页面状态驱动。
    final VoidCallback? longPress =
        widget.enabled && actions.onToggleSelection != null
            ? () {
              HapticFeedback.mediumImpact();
              actions.onToggleSelection!(file.id);
            }
            : null;
    final row = Semantics(
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
                      favorited: widget.favoriteIds.contains(file.id),
                    )
                    : null,
            child: AnimatedContainer(
              duration: MotionToken.fast,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    widget.selected
                        ? colors.sidebarSelectedBg
                        : _hovering || _focused
                        ? colors.sidebarHoverBg
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
                  if (widget.selectionMode) ...[
                    FilesCheckMark(
                      value: widget.selected,
                      onChanged:
                          actions.onToggleSelection != null
                              ? (_) => actions.onToggleSelection!(file.id)
                              : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                  FileThumbnail(file: file, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTypography.bodyMedium,
                            height: 18 / AppTypography.bodyMedium,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${file.isFolder ? AppLocalizations.of(context).filesFolder : formatFileSize(file.sizeBytes)}  ·  ${file.normalizedPath}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.monoFamily,
                            fontFamilyFallback:
                                AppTypography.monoFamilyFallback,
                            fontSize: AppTypography.labelSmall,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.showingRecycleBin && file.isFolder)
                    _RowIconButton(
                      tooltip: AppLocalizations.of(context).filesOpenTooltip,
                      icon: Icons.chevron_right_rounded,
                      enabled: widget.enabled,
                      onTap: () => actions.onOpen?.call(file),
                    ),
                  PopupMenuButton<FileNodeMenuAction>(
                    enabled: widget.enabled,
                    // 钉最小尺寸：与行内打开钮同为 44 命中盒，避免被
                    // kMinInteractiveDimension 抬到 48 撑高行。
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(44, 44)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    tooltip: AppLocalizations.of(context).filesMoreActions,
                    icon: Icon(
                      Icons.more_vert_rounded,
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
                        (action) =>
                            dispatchFileNodeMenuAction(action, file, actions),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.swipeable) return row;

    final swipeActions = <Widget>[
      if (actions.onShare != null && !file.isFolder)
        _SwipeAction(
          icon: Icons.share_rounded,
          label: AppLocalizations.of(context).filesShare,
          color: colors.onSurface,
          onTap: () => actions.onShare!(file),
        ),
      _SwipeAction(
        icon: Icons.delete_outline_rounded,
        label: AppLocalizations.of(context).filesDelete,
        color: colors.error,
        onTap: () => actions.onDelete?.call(file),
      ),
    ];

    return _SwipeableRow(actions: swipeActions, child: row);
  }
}

/// 左滑保持展开的行包装器。
///
/// 左滑露出操作按钮，松手后展开并保持；点击操作按钮执行动作并收回；
/// 点击行内容区域收回。
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

  double get _actionWidth =>
      widget.actions.length * 56.0 + (widget.actions.length - 1) * 12.0 + 16.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionToken.pageSwitch,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
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
      duration: MotionToken.pageSwitch,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
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
          behavior: HitTestBehavior.opaque,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: AnimatedContainer(
                duration: MotionToken.fast,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color:
                      _hovering && widget.enabled
                          ? baseColor.withValues(alpha: 0.10)
                          : Colors.transparent,
                ),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color:
                      widget.enabled
                          ? (_hovering
                              ? context.filesColors.onSurface
                              : baseColor)
                          : baseColor.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
