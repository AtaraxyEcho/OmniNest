import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/features/files/domain/file_node.dart';

/// 文件节点操作回调集合。
///
/// 表格、列表、卡片三个视图共用一份回调，替代此前每个视图 20+ 个
/// 具名参数逐字重复的形态；菜单项的可见性也由此对象的可空性决定。
@immutable
class FileNodeActionCallbacks {
  const FileNodeActionCallbacks({
    this.onOpen,
    this.onRename,
    this.onDelete,
    this.onPurge,
    this.onRestore,
    this.onCopy,
    this.onShowVersions,
    this.onMove,
    this.onMoveToSharedSpace,
    this.onMoveToPersonalSpace,
    this.onDownload,
    this.onShare,
    this.onPreview,
    this.onToggleFavorite,
    this.onToggleSelection,
    this.onInspect,
  });

  final ValueChanged<FileNode>? onOpen;
  final ValueChanged<FileNode>? onRename;
  final ValueChanged<FileNode>? onDelete;
  final ValueChanged<FileNode>? onPurge;
  final ValueChanged<FileNode>? onRestore;
  final ValueChanged<FileNode>? onCopy;
  final ValueChanged<FileNode>? onShowVersions;
  final ValueChanged<FileNode>? onMove;
  final ValueChanged<FileNode>? onMoveToSharedSpace;
  final ValueChanged<FileNode>? onMoveToPersonalSpace;
  final ValueChanged<FileNode>? onDownload;
  final ValueChanged<FileNode>? onShare;
  final ValueChanged<FileNode>? onPreview;
  final ValueChanged<FileNode>? onToggleFavorite;

  /// 按节点 id 切换选中态。
  final ValueChanged<String>? onToggleSelection;

  /// 单击行/卡片的检视回调（Toggle 语义由 controller.inspectNode 实现）。
  final ValueChanged<String>? onInspect;
}

enum FileNodeMenuAction {
  open,
  rename,
  versions,
  copy,
  move,
  moveToShared,
  moveToPersonal,
  download,
  share,
  favorite,
  preview,
  delete,
  purge,
  restore,
}

/// 构建文件节点右键/更多菜单项。
///
/// 菜单项可见性规则与旧版列表/网格一致：回收站只保留恢复与粉碎；
/// 文件夹不提供版本/复制/下载/分享/收藏；回调为 null 的能力不展示。
///
/// [includeQuickActions] 控制是否列出 收藏/分享/预览/下载 四个快捷项：
/// 已在表格操作列内联常驻的视图（表格视图）传 false 去重，仍以菜单为
/// 唯一入口的调用方（移动列表、卡片网格）保持默认 true。
///
/// [favorited] 为该文件的实际收藏态：收藏菜单项的图标与文案随它切换；
/// 未提供时回退分区语义（收藏分区=全部已收藏）。
List<PopupMenuEntry<FileNodeMenuAction>> buildFileNodeMenuItems(
  BuildContext context, {
  required FileNode file,
  required FileNodeActionCallbacks actions,
  required bool showingRecycleBin,
  required bool showingFavorites,
  bool includeQuickActions = true,
  bool? favorited,
}) {
  final l10n = AppLocalizations.of(context);
  final error = context.filesColors.error;
  if (showingRecycleBin) {
    return [
      _menuItem(
        context,
        value: FileNodeMenuAction.restore,
        icon: Icons.restore_rounded,
        label: l10n.filesRestore,
      ),
      _menuItem(
        context,
        value: FileNodeMenuAction.purge,
        icon: Icons.delete_forever_outlined,
        label: l10n.filesPurge,
        color: error,
      ),
    ];
  }
  return [
    if (file.isFolder && actions.onOpen != null)
      _menuItem(
        context,
        value: FileNodeMenuAction.open,
        icon: Icons.folder_open_outlined,
        label: l10n.filesOpen,
      ),
    if (actions.onRename != null)
      _menuItem(
        context,
        value: FileNodeMenuAction.rename,
        icon: Icons.drive_file_rename_outline,
        label: l10n.filesRename,
      ),
    if (actions.onShowVersions != null && !file.isFolder)
      _menuItem(
        context,
        value: FileNodeMenuAction.versions,
        icon: Icons.history_rounded,
        label: l10n.filesVersionsTitle,
      ),
    if (actions.onCopy != null && !file.isFolder)
      _menuItem(
        context,
        value: FileNodeMenuAction.copy,
        icon: Icons.file_copy_outlined,
        label: l10n.filesCopyToEllipsis,
      ),
    if (actions.onMove != null)
      _menuItem(
        context,
        value: FileNodeMenuAction.move,
        icon: Icons.drive_file_move_outlined,
        label: l10n.filesMoveToEllipsis,
      ),
    if (actions.onMoveToSharedSpace != null)
      _menuItem(
        context,
        value: FileNodeMenuAction.moveToShared,
        icon: Icons.workspaces_outlined,
        label: l10n.filesMoveToShared,
      ),
    if (actions.onMoveToPersonalSpace != null)
      _menuItem(
        context,
        value: FileNodeMenuAction.moveToPersonal,
        icon: Icons.person_outline,
        label: l10n.filesMoveToPersonal,
      ),
    if (includeQuickActions && actions.onDownload != null && !file.isFolder)
      _menuItem(
        context,
        value: FileNodeMenuAction.download,
        icon: Icons.download_outlined,
        label: l10n.filesDownload,
      ),
    if (includeQuickActions && actions.onShare != null && !file.isFolder)
      _menuItem(
        context,
        value: FileNodeMenuAction.share,
        icon: Icons.share_outlined,
        label: l10n.filesShare,
      ),
    if (includeQuickActions && actions.onPreview != null && !file.isFolder)
      _menuItem(
        context,
        value: FileNodeMenuAction.preview,
        icon: Icons.visibility_outlined,
        label: l10n.filesPreview,
      ),
    if (includeQuickActions &&
        actions.onToggleFavorite != null &&
        !file.isFolder)
      _menuItem(
        context,
        value: FileNodeMenuAction.favorite,
        icon:
            (favorited ?? showingFavorites)
                ? Icons.star_border_rounded
                : Icons.star_rounded,
        label:
            (favorited ?? showingFavorites)
                ? l10n.filesRemoveFavorite
                : l10n.filesAddFavorite,
      ),
    _menuItem(
      context,
      value: FileNodeMenuAction.delete,
      icon: Icons.delete_outline_rounded,
      label: l10n.filesDelete,
      color: error,
    ),
  ];
}

PopupMenuEntry<FileNodeMenuAction> _menuItem(
  BuildContext context, {
  required FileNodeMenuAction value,
  required IconData icon,
  required String label,
  Color? color,
}) {
  return PopupMenuItem(
    value: value,
    height: 36,
    child: Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? context.filesColors.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );
}

/// 派发菜单动作到回调。
void dispatchFileNodeMenuAction(
  FileNodeMenuAction action,
  FileNode file,
  FileNodeActionCallbacks actions,
) {
  switch (action) {
    case FileNodeMenuAction.open:
      actions.onOpen?.call(file);
    case FileNodeMenuAction.rename:
      actions.onRename?.call(file);
    case FileNodeMenuAction.versions:
      actions.onShowVersions?.call(file);
    case FileNodeMenuAction.copy:
      actions.onCopy?.call(file);
    case FileNodeMenuAction.move:
      actions.onMove?.call(file);
    case FileNodeMenuAction.moveToShared:
      actions.onMoveToSharedSpace?.call(file);
    case FileNodeMenuAction.moveToPersonal:
      actions.onMoveToPersonalSpace?.call(file);
    case FileNodeMenuAction.download:
      actions.onDownload?.call(file);
    case FileNodeMenuAction.share:
      actions.onShare?.call(file);
    case FileNodeMenuAction.favorite:
      actions.onToggleFavorite?.call(file);
    case FileNodeMenuAction.preview:
      actions.onPreview?.call(file);
    case FileNodeMenuAction.delete:
      actions.onDelete?.call(file);
    case FileNodeMenuAction.purge:
      actions.onPurge?.call(file);
    case FileNodeMenuAction.restore:
      actions.onRestore?.call(file);
  }
}

/// 在指定全局位置弹出文件节点菜单并派发选中动作。
Future<void> showFileNodeMenuAt(
  BuildContext context,
  Offset globalPosition, {
  required FileNode file,
  required FileNodeActionCallbacks actions,
  required bool showingRecycleBin,
  required bool showingFavorites,
  bool? favorited,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final action = await showMenu<FileNodeMenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: buildFileNodeMenuItems(
      context,
      file: file,
      actions: actions,
      showingRecycleBin: showingRecycleBin,
      showingFavorites: showingFavorites,
      favorited: favorited,
    ),
  );
  if (action == null) {
    return;
  }
  dispatchFileNodeMenuAction(action, file, actions);
}

/// 就地新建文件夹草稿行：出现在列表首行，Enter/失焦提交、Esc 取消。
///
/// 空名提交回落默认名；重名去重由 controller.commitFolderCreation 处理。
class FileDraftFolderRow extends StatefulWidget {
  const FileDraftFolderRow({
    required this.defaultName,
    required this.onSubmit,
    required this.onCancel,
    this.compact = false,
    super.key,
  });

  final String defaultName;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  /// true = 表格/列表 44px 行形态；false = 卡片格形态。
  final bool compact;

  @override
  State<FileDraftFolderRow> createState() => _FileDraftFolderRowState();
}

class _FileDraftFolderRowState extends State<FileDraftFolderRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.defaultName.length,
      );
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && !_settled) {
      _submit();
    }
  }

  void _submit() {
    if (_settled) {
      return;
    }
    _settled = true;
    widget.onSubmit(_controller.text);
  }

  void _cancel() {
    if (_settled) {
      return;
    }
    _settled = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: TextStyle(
        fontSize: AppTypography.bodyMedium,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
        isCollapsed: true,
      ),
      onSubmitted: (value) => _submit(),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.selectedBorder),
        ),
        child: Row(
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 16,
              color: colors.success,
            ),
            const SizedBox(width: 10),
            Expanded(child: field),
            Icon(
              Icons.subdirectory_arrow_left_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Icon(Icons.close_rounded, size: 14, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 客户端近似分类：按 MIME 与扩展名归入九个分类（供筛选计数复用）。
FileCategoryLabel fileCategoryOfNode(FileNode node) {
  if (node.isFolder) {
    return FileCategoryLabel.other;
  }
  final mime = (node.mimeType ?? '').toLowerCase();
  final name = node.name.toLowerCase();
  if (mime.startsWith('image/')) {
    return FileCategoryLabel.image;
  }
  if (mime.startsWith('video/')) {
    return FileCategoryLabel.video;
  }
  if (mime.startsWith('audio/')) {
    return FileCategoryLabel.audio;
  }
  if (name.endsWith('.cbz') || name.endsWith('.cbr')) {
    return FileCategoryLabel.comic;
  }
  if (name.endsWith('.epub') || name.endsWith('.txt')) {
    return FileCategoryLabel.novel;
  }
  if (name.endsWith('.zip') ||
      name.endsWith('.rar') ||
      name.endsWith('.7z') ||
      name.endsWith('.tar') ||
      name.endsWith('.gz')) {
    return FileCategoryLabel.archive;
  }
  if (mime.contains('pdf') ||
      mime.startsWith('text/') ||
      mime.contains('word') ||
      mime.contains('sheet') ||
      name.endsWith('.doc') ||
      name.endsWith('.docx') ||
      name.endsWith('.xls') ||
      name.endsWith('.xlsx') ||
      name.endsWith('.ppt') ||
      name.endsWith('.pptx') ||
      name.endsWith('.pdf')) {
    return FileCategoryLabel.document;
  }
  return FileCategoryLabel.other;
}

/// 表格"格式"列友好标签：扩展名大写 + 分类中文（模板 MKV 视频 / PDF 文档 形态）。
String fileFormatLabel(
  FileNode node,
  String categoryLabel,
  String folderLabel,
) {
  if (node.isFolder) {
    return folderLabel;
  }
  final dot = node.name.lastIndexOf('.');
  final ext =
      dot > 0 && dot < node.name.length - 1
          ? node.name.substring(dot + 1).toUpperCase()
          : (node.mimeType?.split('/').last.toUpperCase() ?? '');
  if (ext.isEmpty) {
    return categoryLabel;
  }
  return '$ext $categoryLabel';
}

/// 三视图共享的空状态：hairline 直角框 + 图标 + 文案。
class FileNodeEmptyState extends StatelessWidget {
  const FileNodeEmptyState({required this.showingRecycleBin, super.key});

  final bool showingRecycleBin;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            showingRecycleBin
                ? Icons.delete_sweep_outlined
                : Icons.folder_open_outlined,
            color: colors.onSurfaceVariant,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            showingRecycleBin
                ? AppLocalizations.of(context).filesRecycleBinEmpty
                : AppLocalizations.of(context).filesEmpty,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 分类近似枚举（与 FileBrowserFileCategory 一一对应，供展示层复用）。
enum FileCategoryLabel {
  all,
  image,
  video,
  audio,
  document,
  novel,
  comic,
  archive,
  other,
}
