part of 'desktop_files_page.dart';

/// 鼠标沿用桌面即时拖动，触控设备用长按启动，避免点选时误搬文件。
class _AdaptiveFileDraggable extends StatefulWidget {
  const _AdaptiveFileDraggable({
    required this.data,
    required this.feedback,
    required this.childWhenDragging,
    required this.child,
  });

  final List<String> data;
  final Widget feedback;
  final Widget childWhenDragging;
  final Widget child;

  @override
  State<_AdaptiveFileDraggable> createState() => _AdaptiveFileDraggableState();
}

class _AdaptiveFileDraggableState extends State<_AdaptiveFileDraggable> {
  bool _mouseHasHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) {
        if (!_mouseHasHovered) setState(() => _mouseHasHovered = true);
      },
      child:
          _mouseHasHovered
              ? Draggable<List<String>>(
                data: widget.data,
                feedbackOffset: const Offset(10, 10),
                feedback: widget.feedback,
                childWhenDragging: widget.childWhenDragging,
                child: widget.child,
              )
              : LongPressDraggable<List<String>>(
                data: widget.data,
                delay: DesktopMotion.longPressDrag,
                feedbackOffset: const Offset(10, 10),
                feedback: widget.feedback,
                childWhenDragging: widget.childWhenDragging,
                child: widget.child,
              ),
    );
  }
}

/// 拖拽幽灵：跟随指针的一枚小卡片，说明正在搬什么、搬几个。
class _RowDragGhost extends StatelessWidget {
  const _RowDragGhost({required this.node, required this.count});

  final FileNode node;
  final int count;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: skin.panelSolid,
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
          border: Border.all(color: skin.line2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              node.isFolder ? DesktopIcons.folder : DesktopIcons.list2,
              size: 14,
              color: skin.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.dense(skin.text),
              ),
            ),
            if (count > 1) ...[
              const SizedBox(width: 6),
              Text('+${count - 1}', style: DesktopType.micro(skin.text3)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 行首的方图舱（样例 `.fi`）：文件夹用强调色软底，其余按类型取中性底。
class _FileIconPlate extends StatelessWidget {
  const _FileIconPlate({required this.node});

  final FileNode node;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final tone = _fileTone(node, skin);
    return Container(
      // 样例 `extra.css:75`：38×38、圆角 11。
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child:
          _hasFileThumbnail(node)
              ? FileThumbnail(
                file: node,
                size: 38,
                borderRadius: BorderRadius.circular(11),
              )
              : Icon(_fileIcon(node), size: 17, color: tone),
    );
  }
}

class _SelectionTick extends StatelessWidget {
  const _SelectionTick({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // 样例 `extra.css:77`：18×18 复选块、圆角 6、1.5 描边，`role=checkbox`。
    return Semantics(
      checked: selected,
      label: AppLocalizations.of(context).desktopFilesSelectRow,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: selected ? skin.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? skin.accent : skin.line2,
            width: 1.5,
          ),
        ),
        child:
            selected
                ? Icon(DesktopIcons.check, size: 11, color: skin.accentInk)
                : null,
      ),
    );
  }
}

class _AccessTag extends StatelessWidget {
  const _AccessTag({required this.label, required this.accent});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      // 样例 `extra.css:37`：内距 2/9，带一圈发丝描边。
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        // 样例 `.tag.acc` 有底色；`.tag.dim`（Private）是透明底 + 发丝描边。
        color: accent ? skin.accentWash(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
        border: Border.all(color: accent ? skin.accentWash(0.30) : skin.line),
      ),
      child: Text(
        label,
        style: DesktopType.caption(
          accent ? skin.accent : skin.text3,
        ).copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _FilesEmpty extends StatelessWidget {
  const _FilesEmpty({
    required this.section,
    required this.filtered,
    required this.onClear,
  });

  final FileManagerSection section;
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54),
      child: DesktopEmpty(
        icon:
            section == FileManagerSection.recycleBin
                ? DesktopIcons.trash
                : filtered
                ? DesktopIcons.search
                : DesktopIcons.folder,
        message:
            filtered
                ? l10n.desktopFilesEmptyFilter
                : l10n.desktopFilesEmptyFolder,
        actionLabel: filtered ? l10n.desktopFilesClearFilters : null,
        onAction: filtered ? onClear : null,
      ),
    );
  }
}

// ── 共用小工具 ────────────────────────────────────────────────────────

IconData _fileIcon(FileNode node) {
  if (node.isFolder) {
    return DesktopIcons.folder;
  }
  final type = node.nodeType.toUpperCase();
  final mime = node.mimeType ?? '';
  if (type == 'IMAGE' || mime.startsWith('image/')) {
    return DesktopIcons.image;
  }
  if (type == 'VIDEO' || mime.startsWith('video/')) {
    return DesktopIcons.film;
  }
  if (type == 'AUDIO' || mime.startsWith('audio/')) {
    return DesktopIcons.music;
  }
  if (type == 'DOCUMENT') {
    return DesktopIcons.book;
  }
  return DesktopIcons.file;
}

bool _hasFileThumbnail(FileNode node) {
  if (node.isFolder) {
    return false;
  }
  final mime = node.mimeType?.toLowerCase() ?? '';
  return (node.coverFileId?.isNotEmpty ?? false) || mime.startsWith('image/');
}

Color _fileTone(FileNode node, DesktopSkin skin) {
  if (node.isFolder) {
    return DesktopPalette.kindFolder;
  }
  final type = node.nodeType.toUpperCase();
  final mime = (node.mimeType ?? '').toLowerCase();
  if (type == 'IMAGE' || mime.startsWith('image/')) {
    return DesktopPalette.kindImage;
  }
  if (type == 'VIDEO' || mime.startsWith('video/')) {
    return DesktopPalette.kindVideo;
  }
  if (type == 'AUDIO' || mime.startsWith('audio/')) {
    return DesktopPalette.kindAudio;
  }
  if (mime.contains('pdf')) {
    return DesktopPalette.kindDocument;
  }
  if (mime.startsWith('text/') || type == 'TEXT') {
    return DesktopPalette.kindText;
  }
  return skin.text2;
}

/// 行副标题：目录显示直接子项数（样例 `Files.tsx` 的 `childCount`），
/// 文件显示类型标签。
String _fileSubtitle(AppLocalizations l10n, FileNode node) {
  if (node.isFolder) {
    return l10n.desktopFilesItemCount(node.childCount);
  }
  final kind = _fileKindLabel(l10n, node);
  final uploader = node.uploaderName?.trim();
  if (node.spaceType == SpaceType.shared &&
      uploader != null &&
      uploader.isNotEmpty) {
    return '$kind · ${l10n.desktopFilesOwner(uploader)}';
  }
  return kind;
}

String _fileKindLabel(AppLocalizations l10n, FileNode node) {
  if (node.isFolder) {
    return l10n.desktopFilesKindFolder;
  }
  final type = node.nodeType.toUpperCase();
  final mime = node.mimeType ?? '';
  if (type == 'IMAGE' || mime.startsWith('image/')) {
    return l10n.desktopFilesKindImage;
  }
  if (type == 'VIDEO' || mime.startsWith('video/')) {
    return l10n.desktopFilesKindVideo;
  }
  if (type == 'AUDIO' || mime.startsWith('audio/')) {
    return l10n.desktopFilesKindAudio;
  }
  if (type == 'DOCUMENT') {
    return mime.contains('pdf')
        ? 'PDF · ${l10n.desktopFilesKindDocument}'
        : l10n.desktopFilesKindDocument;
  }
  if (mime.contains('zip') || mime.contains('tar') || type == 'ARCHIVE') {
    return l10n.desktopFilesKindArchive;
  }
  if (mime.startsWith('text/')) {
    return l10n.desktopFilesKindText;
  }
  return l10n.desktopFilesKindOther;
}

/// 列表"更新时间"列：样例用 Today / Yesterday / 短月日，不写完整年-月-日。
String _formatModified(BuildContext context, DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final diff = today.difference(that).inDays;
  final l10n = AppLocalizations.of(context);
  if (diff <= 0) {
    return l10n.desktopFilesDateToday;
  }
  if (diff == 1) {
    return l10n.desktopFilesDateYesterday;
  }
  return MaterialLocalizations.of(context).formatShortMonthDay(local);
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String _sectionTitle(AppLocalizations l10n, FileManagerSection section) =>
    switch (section) {
      FileManagerSection.recent => l10n.filesRecent,
      FileManagerSection.favorites => l10n.filesFavorites,
      FileManagerSection.recycleBin => l10n.filesRecycleBin,
      FileManagerSection.sharedSpace => l10n.filesSharedSpace,
      FileManagerSection.sharedWithMe => l10n.filesSharedWithMe,
      FileManagerSection.myShares => l10n.desktopFilesSharedByMe,
      FileManagerSection.shareManagement => l10n.filesShareManagement,
      FileManagerSection.externalStorage => l10n.filesExternalStorage,
      FileManagerSection.importTasks => l10n.filesImportTasks,
      FileManagerSection.uploadQueue => l10n.filesUploadQueue,
      FileManagerSection.storageStats => l10n.filesStorageStats,
      FileManagerSection.allFiles => l10n.desktopFilesAll,
    };

/// 样例 `.drop-veil`：70% 底色 + σ14 背景模糊 + 虚线呼吸框。
///
/// `position:absolute; inset:0; z-index:95; background:bg 70%;
/// backdrop-filter:blur(14px); transition:opacity .3s`，内部框
/// `padding 70/110; border:2px dashed accent; radius:30`，整体 2s 呼吸到 1.03。
/// 外层 `pointer-events: none`，拖放事件仍归 `DropTarget`。
class _DropVeil extends StatefulWidget {
  const _DropVeil({required this.target});

  final String target;

  @override
  State<_DropVeil> createState() => _DropVeilState();
}

class _DropVeilState extends State<_DropVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _breathe.stop();
      return;
    }
    if (!_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // 样例是 `border: 2px dashed var(--accent)`，Flutter 没有内置虚线描边，
    // 用路径测长后逐段抽出来画。
    final box = CustomPaint(
      foregroundPainter: _DashedRoundedBorder(
        color: skin.accent,
        radius: 30,
        strokeWidth: 2,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 110, vertical: 70),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(DesktopIcons.upload, size: 34, color: skin.accent),
            const SizedBox(height: 10),
            Text(
              l10n.desktopFilesDropToUpload,
              style: DesktopType.displaySm(skin.accent),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.desktopFilesDropTarget(widget.target),
              style: DesktopType.caption(skin.text2),
            ),
          ],
        ),
      ),
    );
    return IgnorePointer(
      child: ClipRect(
        child: BackdropFilter.grouped(
          filterConfig: ImageFilterConfig(
            desktopGlassFilter(blur: 14, saturation: 1),
          ),
          child: ColoredBox(
            color: skin.bg.withValues(alpha: 0.7),
            child: Center(
              child:
                  reduce
                      ? box
                      : AnimatedBuilder(
                        animation: _breathe,
                        builder:
                            (context, child) => Transform.scale(
                              // 50% 处 scale 1.03（`@keyframes breathe`）。
                              scale:
                                  1 +
                                  0.03 *
                                      Curves.easeInOut.transform(
                                        _breathe.value,
                                      ),
                              child: child,
                            ),
                        child: box,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆角虚线描边：按路径长度切段，段间留空。
///
/// 样例 `.drop-veil > div` 用的是 `border: 2px dashed`，Flutter 只有实线，
/// 只能自己画。
class _DashedRoundedBorder extends CustomPainter {
  const _DashedRoundedBorder({
    required this.color,
    required this.radius,
    this.strokeWidth = 2,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  /// 虚线段长与间隔（CSS `dashed` 在 2px 边宽下约 3:1）。
  static const double _dashLength = 9;
  static const double _gapLength = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final outline =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color;
    for (final metric in outline.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + _dashLength, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorder oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}
