part of 'desktop_files_page.dart';

/// 面包屑 + 搜索 + 筛选 + 视图切换 + 主操作的工具栏（样例 `.fx-bar` / `.f-tools`）。
class _FilesToolbar extends StatelessWidget {
  const _FilesToolbar({
    required this.controller,
    required this.section,
    required this.state,
    required this.search,
    required this.onSearch,
    required this.grid,
    required this.canUpload,
    required this.onNewFolder,
    required this.onUpload,
    required this.onEmptyRecycle,
  });

  final FileBrowserController controller;
  final FileManagerSection section;
  final FileBrowserState? state;
  final TextEditingController search;
  final ValueChanged<String> onSearch;

  /// 当前是否网格视图；视图切换钮在工具栏右侧（样例 `Files.tsx:336`），
  /// 页头不再重复一份。
  final bool grid;
  final bool canUpload;
  final VoidCallback onNewFolder;
  final VoidCallback onUpload;
  final VoidCallback onEmptyRecycle;

  bool get _nodeSection => switch (section) {
    FileManagerSection.allFiles ||
    FileManagerSection.recent ||
    FileManagerSection.favorites ||
    FileManagerSection.recycleBin ||
    FileManagerSection.sharedSpace => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final shared = state?.spaceType == 'SHARED';
    final crumbs =
        shared
            ? state?.sharedSpaceBreadcrumbs ?? const <FileNode>[]
            : state?.breadcrumbs ?? const <FileNode>[];
    final showCrumbs = section == FileManagerSection.allFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _BreadcrumbSegment(
                      label:
                          shared
                              ? l10n.filesSharedSpace
                              : _sectionTitle(l10n, section),
                      current: !showCrumbs || crumbs.isEmpty,
                      onTap:
                          showCrumbs && crumbs.isNotEmpty
                              ? () => unawaited(
                                shared
                                    ? controller.goToSharedSpaceRoot()
                                    : controller.goToRoot(),
                              )
                              : null,
                    ),
                    if (showCrumbs)
                      for (var i = 0; i < crumbs.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            DesktopIcons.chevron,
                            size: 14,
                            color: skin.text3,
                          ),
                        ),
                        _BreadcrumbSegment(
                          label: crumbs[i].name,
                          current: i == crumbs.length - 1,
                          onTap:
                              i == crumbs.length - 1
                                  ? null
                                  : () => unawaited(
                                    shared
                                        ? controller.goToSharedSpaceBreadcrumb(
                                          i,
                                        )
                                        : controller.goToBreadcrumb(i),
                                  ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (section == FileManagerSection.recycleBin)
              DesktopButton(
                label: l10n.desktopFilesEmptyRecycle,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.ghost,
                onPressed:
                    (state?.recycleBin.isEmpty ?? true) ? null : onEmptyRecycle,
              ),
            if (section == FileManagerSection.allFiles)
              DesktopButton(
                label: l10n.filesNewFolder,
                icon: DesktopIcons.plus,
                variant: DesktopButtonVariant.ghost,
                onPressed: onNewFolder,
              ),
            if (canUpload)
              DesktopButton(
                label: l10n.desktopFilesUpload,
                icon: DesktopIcons.upload,
                onPressed: onUpload,
              ),
          ],
        ),
        if (_nodeSection) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (section != FileManagerSection.recycleBin)
                // 样例 `Files.tsx:333`：有内容时给一颗 22×22 的清除钮，
                // 清空后不留空槽，避免搜索框右侧一直空一块。
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: search,
                  builder:
                      (context, value, _) => DesktopTextField(
                        keyName: 'desktop-files-search',
                        controller: search,
                        hint: l10n.desktopFilesSearchHint(
                          shared
                              ? l10n.filesSharedSpace
                              : _sectionTitle(l10n, section),
                        ),
                        prefixIcon: DesktopIcons.search,
                        trailing:
                            value.text.isEmpty
                                ? null
                                : DesktopIconButton(
                                  icon: DesktopIcons.close,
                                  size: 22,
                                  iconSize: 12,
                                  tooltip: l10n.desktopFilesClearSearch,
                                  onPressed: () {
                                    search.clear();
                                    onSearch('');
                                  },
                                ),
                        width: 268,
                        height: 36,
                        focusRing: false,
                        onChanged: onSearch,
                      ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (category, label) in _filterOptions(l10n))
                      DesktopChipButton(
                        label: label,
                        selected: _isActiveFilter(category, label, l10n),
                        onTap:
                            () =>
                                unawaited(controller.setFileCategory(category)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ViewToggle(
                grid: grid,
                onList: () => controller.setViewMode(FileBrowserViewMode.list),
                onGrid: () => controller.setViewMode(FileBrowserViewMode.grid),
              ),
            ],
          ),
        ],
        if (section == FileManagerSection.externalStorage ||
            section == FileManagerSection.myShares ||
            section == FileManagerSection.sharedWithMe)
          const SizedBox.shrink(),
      ],
    );
  }

  /// 样例 `Files.tsx:334` 的 5 颗 chip：All / Folders / Documents / Images /
  /// Media。`folders` 只在桌面出现，其余四项复用既有的服务端分类值。
  List<(FileBrowserFileCategory, String)> _filterOptions(
    AppLocalizations l10n,
  ) => [
    (FileBrowserFileCategory.all, l10n.desktopFilesFilterAll),
    (FileBrowserFileCategory.folders, l10n.desktopFilesFilterFolders),
    (FileBrowserFileCategory.document, l10n.desktopFilesFilterDocuments),
    (FileBrowserFileCategory.image, l10n.desktopFilesFilterImages),
    (FileBrowserFileCategory.video, l10n.desktopFilesFilterMedia),
  ];

  bool _isActiveFilter(
    FileBrowserFileCategory category,
    String label,
    AppLocalizations l10n,
  ) => (state?.fileCategory ?? FileBrowserFileCategory.all) == category;
}

/// 列表 / 网格切换（样例 `extra.css:454` 的 `.vtoggle`）。
///
/// 容器 `padding 3 / r10 / bg raise / border line`，按钮 `30×28 / r7`，
/// 选中 `bg raise3 + text`，过渡 `all .25s var(--spring)`。
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.grid,
    required this.onList,
    required this.onGrid,
  });

  final bool grid;
  final VoidCallback onList;
  final VoidCallback onGrid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
        border: Border.all(color: skin.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewButton(
            context,
            icon: DesktopIcons.list,
            tooltip: l10n.desktopFilesListView,
            selected: !grid,
            onTap: onList,
          ),
          _viewButton(
            context,
            icon: DesktopIcons.grid,
            tooltip: l10n.desktopFilesGridView,
            selected: grid,
            onTap: onGrid,
          ),
        ],
      ),
    );
  }

  Widget _viewButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final skin = DesktopSkin.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.springHover),
                curve: DesktopMotion.spring,
                width: 30,
                height: 28,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? skin.raise3
                          : hovered
                          ? skin.raise2
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusToggle,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: selected ? skin.text : skin.text3,
                ),
              ),
            ),
      ),
    );
  }
}

class _ActionErrorBanner extends StatelessWidget {
  const _ActionErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
        border: Border.all(color: DesktopPalette.bad.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(DesktopIcons.info, size: 15, color: DesktopPalette.bad),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: DesktopType.caption(skin.text2)),
          ),
          DesktopIconButton(
            icon: DesktopIcons.close,
            size: 24,
            iconSize: 12,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// 分区提示条：回收站保留期、共享空间容量。
class _SectionNotices extends StatelessWidget {
  const _SectionNotices({required this.section, required this.state});

  final FileManagerSection section;
  final FileBrowserState? state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final usage = state?.sharedSpaceUsage;
    if (state?.spaceType == 'SHARED' && usage != null) {
      final capacity =
          usage.isUnlimited
              ? l10n.filesSharedSpaceUnlimited
              : formatFileSize(usage.maxBytes);
      return Container(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: skin.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.line),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: skin.accentWash(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(DesktopIcons.users, size: 17, color: skin.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.filesSharedSpaceInfoTitle,
                    style: DesktopType.bodyStrong(skin.text),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.filesSharedSpaceInfo(
                      formatFileSize(usage.usedBytes),
                      capacity,
                      usage.fileCount,
                    ),
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final (String, String)? notice = switch (section) {
      FileManagerSection.recycleBin
          when (state?.recycleBin.isNotEmpty ?? false) =>
        (l10n.desktopFilesRecycleNotice, l10n.desktopFilesRecycleNoticeBody),
      FileManagerSection.sharedSpace when state?.sharedSpaceUsage != null => (
        l10n.filesSharedSpaceUsage,
        '${formatFileSize(state!.sharedSpaceUsage!.usedBytes)} · '
            '${l10n.desktopFilesItemCount(state!.sharedSpaceUsage!.fileCount)}',
      ),
      _ => null,
    };
    if (notice == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
        border: Border.all(color: skin.line),
      ),
      child: Row(
        children: [
          Icon(DesktopIcons.info, size: 16, color: skin.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice.$1, style: DesktopType.bodyStrong(skin.text)),
                const SizedBox(height: 2),
                Text(notice.$2, style: DesktopType.caption(skin.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 多选操作栏（样例 `.fx-sel`），只在有选中项时出现。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.section,
    required this.state,
    required this.onClear,
    required this.onDownload,
    required this.onDelete,
    required this.onRestore,
    required this.onPurge,
    required this.onFavorite,
    required this.onMoveToShared,
    required this.onMoveToPersonal,
    required this.onShare,
    required this.onRename,
  });

  final FileManagerSection section;
  final FileBrowserState state;
  final VoidCallback onClear;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onPurge;
  final VoidCallback onFavorite;
  final VoidCallback onMoveToShared;
  final VoidCallback onMoveToPersonal;
  final VoidCallback onShare;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final count = state.selectedFileIds.length;
    final single = count == 1;
    final recycle = section == FileManagerSection.recycleBin;
    final sharedSpace =
        section == FileManagerSection.sharedSpace ||
        state.spaceType == 'SHARED';
    final allFavorited =
        (state.selectedFileIds.length ==
            state.favoriteIdSet.intersection(state.selectedFileIds).length);
    return AnimatedContainer(
      duration: DesktopMotion.of(context, DesktopMotion.fast),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: skin.accentWash(0.1),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
        border: Border.all(color: skin.accentWash(0.28)),
      ),
      child: Row(
        children: [
          Text(
            l10n.filesSelectedCount(count),
            style: DesktopType.bodyStrong(skin.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (recycle) ...[
                  DesktopButton(
                    label: l10n.filesRestore,
                    icon: DesktopIcons.undo,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: onRestore,
                  ),
                  DesktopButton(
                    label: l10n.desktopFilesDeleteForever,
                    icon: DesktopIcons.trash,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: onPurge,
                  ),
                ] else ...[
                  if (!sharedSpace)
                    DesktopButton(
                      label: l10n.filesShare,
                      icon: DesktopIcons.share,
                      variant: DesktopButtonVariant.ghost,
                      onPressed: single ? onShare : null,
                    ),
                  DesktopButton(
                    label: l10n.filesDownload,
                    icon: DesktopIcons.download,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: onDownload,
                  ),
                  DesktopButton(
                    label: l10n.filesRename,
                    icon: DesktopIcons.edit,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: single ? onRename : null,
                  ),
                  DesktopButton(
                    label:
                        sharedSpace
                            ? l10n.filesMoveToPersonal
                            : l10n.filesMoveToShared,
                    icon: DesktopIcons.moveRight,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: sharedSpace ? onMoveToPersonal : onMoveToShared,
                  ),
                  if (!sharedSpace)
                    DesktopButton(
                      label:
                          allFavorited
                              ? l10n.filesRemoveFavorite
                              : l10n.filesAddFavorite,
                      icon:
                          allFavorited
                              ? DesktopIcons.starFilled
                              : DesktopIcons.star,
                      variant: DesktopButtonVariant.ghost,
                      onPressed: onFavorite,
                    ),
                  DesktopButton(
                    label:
                        sharedSpace
                            ? l10n.filesDelete
                            : l10n.desktopFilesMoveToRecycle,
                    icon: DesktopIcons.trash,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: Text(
              l10n.desktopFilesClear,
              style: DesktopType.link(skin.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文件表的列宽规格（样例 `extra.css:69` 的 `22 40 minmax(220,1fr) 112 84 150 108`
/// + `gap: 14`）。表头与数据行共用同一份，避免两处各写一套而错位。
abstract final class _FileColumns {
  /// 勾选列。
  static const double tick = 22;

  /// 文件类型图标列；表头留空槽占位。
  static const double icon = 40;

  /// 列间距。
  static const double gap = 14;

  static const double modified = 112;
  static const double size = 84;
  static const double access = 150;

  /// 行内动作列。
  static const double actions = 108;
}

/// 面包屑单段：全程使用 26px Newsreader 衬线，可点击段悬停带 `skin.raise2` 圆角底。
class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({
    required this.label,
    required this.current,
    this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final clickable = onTap != null;
    return DesktopHover(
      enabled: clickable,
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: DesktopMotion.of(context, DesktopMotion.fast),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hovered && clickable ? skin.raise2 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: DesktopType.crumbTitle(
                  current || hovered ? skin.text : skin.text2,
                ),
              ),
            ),
          ),
    );
  }
}

/// 三态全选复选框（未选 / 半选 / 全选）。
class _TriStateSelectionTick extends StatelessWidget {
  const _TriStateSelectionTick({
    required this.allSelected,
    required this.someSelected,
    this.onTap,
  });

  final bool allSelected;
  final bool someSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final active = allSelected || someSelected;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        checked: allSelected,
        mixed: someSelected && !allSelected,
        label: AppLocalizations.of(context).desktopFilesSelectRow,
        child: AnimatedContainer(
          duration: DesktopMotion.of(context, DesktopMotion.fast),
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? skin.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? skin.accent : skin.line2,
              width: 1.5,
            ),
          ),
          child:
              allSelected
                  ? Icon(DesktopIcons.check, size: 11, color: skin.accentInk)
                  : someSelected
                  ? Container(
                    width: 8,
                    height: 1.8,
                    decoration: BoxDecoration(
                      color: skin.accentInk,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  )
                  : null,
        ),
      ),
    );
  }
}

/// 列表表头：全选复选框 + Name / Modified / Size / Access，点击同列反向排序。
class _FileTableHead extends StatelessWidget {
  const _FileTableHead({
    required this.sort,
    required this.ascending,
    required this.onSort,
    this.allSelected = false,
    this.someSelected = false,
    this.onToggleSelectAll,
  });

  final FileBrowserSortBy sort;
  final bool ascending;
  final ValueChanged<FileBrowserSortBy> onSort;
  final bool allSelected;
  final bool someSelected;
  final VoidCallback? onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    Widget cell(
      String label,
      FileBrowserSortBy? key, {
      double? width,
      int flex = 0,
      TextAlign align = TextAlign.left,
    }) {
      final active = key != null && sort == key;
      Widget buildContent(Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: DesktopType.tableHead(color)),
          if (active) ...[
            const SizedBox(width: 4),
            Icon(
              ascending ? DesktopIcons.chevUp : DesktopIcons.chevDown,
              size: 12,
              color: color,
            ),
          ],
        ],
      );
      final child =
          key == null
              ? buildContent(skin.text3)
              : DesktopHover(
                builder:
                    (context, hovered) => GestureDetector(
                      onTap: () => onSort(key),
                      behavior: HitTestBehavior.opaque,
                      child: buildContent(
                        active
                            ? skin.accent
                            : hovered
                            ? skin.text
                            : skin.text3,
                      ),
                    ),
              );
      final aligned = Align(
        alignment:
            align == TextAlign.right
                ? Alignment.centerRight
                : Alignment.centerLeft,
        child: child,
      );
      return flex > 0
          ? Expanded(flex: flex, child: aligned)
          : SizedBox(width: width, child: aligned);
    }

    // 吸顶由 [_StickyFileTableHead] 提供：表头钉在列表视口顶部，行从它下方
    // 滑过，模糊层才有可见对象，也才需要这层 70% 底色把穿透的字压下去。
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
      child: BackdropFilter.grouped(
        filterConfig: ImageFilterConfig(
          desktopGlassFilter(blur: 14, saturation: 1),
        ),
        child: Container(
          height: _StickyFileTableHead.headHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: skin.bg.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _FileColumns.tick,
                child: Center(
                  child: _TriStateSelectionTick(
                    allSelected: allSelected,
                    someSelected: someSelected,
                    onTap: onToggleSelectAll,
                  ),
                ),
              ),
              const SizedBox(width: _FileColumns.gap),
              const SizedBox(width: _FileColumns.icon),
              const SizedBox(width: _FileColumns.gap),
              cell(l10n.desktopColTitle, FileBrowserSortBy.name, flex: 5),
              const SizedBox(width: _FileColumns.gap),
              cell(
                l10n.desktopFilesModified,
                FileBrowserSortBy.updatedAt,
                width: _FileColumns.modified,
              ),
              const SizedBox(width: _FileColumns.gap),
              cell(
                l10n.desktopFilesSize,
                FileBrowserSortBy.size,
                width: _FileColumns.size,
                align: TextAlign.right,
              ),
              const SizedBox(width: _FileColumns.gap),
              cell(l10n.filesAccess, null, width: _FileColumns.access),
              const SizedBox(width: _FileColumns.actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// 吸顶表头的 sliver 代理：等价于 `.f-head` 的 `position:sticky; top:0`。
///
/// 高度 32 + `margin-bottom: 6`（`extra.css:70`）。6px 间隙留在代理内部而不是
/// 变成列表顶部的 padding：样例里它是表头的下外边距，吸顶期间同样存在，
/// 行会从这道缝里透出来——这正是需要 blur 的原因。
class _StickyFileTableHead extends SliverPersistentHeaderDelegate {
  const _StickyFileTableHead({
    required this.sort,
    required this.ascending,
    required this.onSort,
    this.allSelected = false,
    this.someSelected = false,
    this.onToggleSelectAll,
  });

  /// 表头本体高度：36px。
  static const double headHeight = 36;

  /// 表头下外边距：8px。
  static const double gap = 8;

  final FileBrowserSortBy sort;
  final bool ascending;
  final ValueChanged<FileBrowserSortBy> onSort;
  final bool allSelected;
  final bool someSelected;
  final VoidCallback? onToggleSelectAll;

  @override
  double get minExtent => headHeight + gap;

  @override
  double get maxExtent => headHeight + gap;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      child: _FileTableHead(
        sort: sort,
        ascending: ascending,
        onSort: onSort,
        allSelected: allSelected,
        someSelected: someSelected,
        onToggleSelectAll: onToggleSelectAll,
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyFileTableHead oldDelegate) {
    return sort != oldDelegate.sort ||
        ascending != oldDelegate.ascending ||
        onSort != oldDelegate.onSort ||
        allSelected != oldDelegate.allSelected ||
        someSelected != oldDelegate.someSelected ||
        onToggleSelectAll != oldDelegate.onToggleSelectAll;
  }
}

/// 分组小标题（Folders / Files）。
class _RowGroupLabel extends StatelessWidget {
  const _RowGroupLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: DesktopType.eyebrow(skin.text3)),
          const SizedBox(width: 8),
          Text('$count', style: DesktopType.numeric(skin.text3)),
        ],
      ),
    );
  }
}
