import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:omninest/platform/file_pick.dart';
import 'package:omninest/platform/platform_capabilities.dart';

part 'desktop_files_actions.dart';
part 'desktop_files_dialogs.dart';
part 'desktop_files_rail.dart';
part 'desktop_files_rail_tree.dart';
part 'desktop_files_grid.dart';
part 'desktop_files_rows.dart';
part 'desktop_files_rows_drag.dart';
part 'desktop_files_sections.dart';
part 'desktop_files_table.dart';

/// 桌面文件页（样例 `Files.tsx`）。
///
/// 分区轨 + 文件夹树 + 面包屑 + 工具栏 + 列表/网格，数据全部走
/// `fileBrowserControllerProvider`：这一页只是它的另一种排版，不另起
/// 一套取数与选中状态，否则桌面与移动会看到两份不同的选中集。
class DesktopFilesPage extends ConsumerStatefulWidget {
  const DesktopFilesPage({this.initialSection, super.key});

  /// `?section=` 深链（工具总入口按分区直达）。
  final FileManagerSection? initialSection;

  @override
  ConsumerState<DesktopFilesPage> createState() => _DesktopFilesPageState();
}

class _DesktopFilesPageState extends ConsumerState<DesktopFilesPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _pageFocus = FocusNode(debugLabel: 'desktop-files');

  /// 已消费的深链分区：只在首次数据到达后加载一次，之后滚动/切换不重载。
  FileManagerSection? _appliedSection;
  bool _dragging = false;

  /// 外部拖入时悬停在哪一行文件夹上（`null` = 没有）。
  String? _externalHoverId;

  /// 悬停满 650ms 后才展开目录：样例 `expandOnHover` 的同一档延迟。
  Timer? _expandTimer;

  /// 文件夹行的渲染锚点：外部拖拽没有 Flutter 的 DragTarget 可用，
  /// 只能按指针位置在这些矩形里做命中测试。
  final Map<String, GlobalKey> _folderKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _expandTimer?.cancel();
    _search.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  /// 拖放遮罩的开合。`setState` 是 `State` 的受保护成员，
  /// 因此它必须留在类里，不能随动作层挪进扩展。
  void _setDragging(bool value) {
    if (!mounted || _dragging == value) {
      return;
    }
    setState(() => _dragging = value);
  }

  /// 某个文件夹行的锚点（懒建，按节点 id 复用）。
  GlobalKey _folderKey(String id) => _folderKeys.putIfAbsent(id, GlobalKey.new);

  /// 指针落点在哪个文件夹行上；不在任何行上返回 null。
  String? _folderAt(Offset globalPosition) {
    for (final entry in _folderKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) {
        continue;
      }
      final origin = box.localToGlobal(Offset.zero);
      if ((origin & box.size).contains(globalPosition)) {
        return entry.key;
      }
    }
    return null;
  }

  /// 外部拖入时的悬停跟踪：更新高亮，并在同一行上停满 650ms 后展开它。
  void _trackExternalHover(
    Offset globalPosition,
    FileBrowserController controller,
  ) {
    final id = _folderAt(globalPosition);
    if (id == _externalHoverId) {
      return;
    }
    _expandTimer?.cancel();
    _expandTimer = null;
    if (mounted) {
      setState(() => _externalHoverId = id);
    }
    if (id == null) {
      return;
    }
    _expandTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _externalHoverId != id) {
        return;
      }
      final state = ref.read(fileBrowserControllerProvider).asData?.value;
      final folder = state?.files.where((node) => node.id == id).firstOrNull;
      if (folder != null && folder.isFolder) {
        _clearExternalHover();
        unawaited(
          state?.spaceType == 'SHARED'
              ? controller.openSharedSpaceFolder(folder)
              : controller.openFolder(folder),
        );
      }
    });
  }

  void _clearExternalHover() {
    _expandTimer?.cancel();
    _expandTimer = null;
    if (!mounted || _externalHoverId == null) {
      return;
    }
    setState(() => _externalHoverId = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final async = ref.watch(fileBrowserControllerProvider);
    final state = async.asData?.value;
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final stats = ref.watch(fileStorageStatsProvider).asData?.value;

    if (state != null) {
      _applyInitialSection(state.section);
    }

    final section = state?.section ?? FileManagerSection.allFiles;
    final items = _itemsForSection(state, section, _search.text);
    final grid = state?.viewMode == FileBrowserViewMode.grid;
    final selected = state?.selectedFileIds ?? const <String>{};
    final showTree = MediaQuery.sizeOf(context).width > 1180;
    final canUpload =
        section == FileManagerSection.allFiles ||
        section == FileManagerSection.sharedSpace;

    // 样例 `extra.css:70` 的表头是 `position: sticky`：它粘在**列表容器**
    // 的顶部，而不是整页。主区玻璃面板只包住工具栏与列表，表头才能在
    // 面板内部滚动并保持自己的模糊层。
    final page = DesktopPage(
      maxWidth: double.infinity,
      topPadding: DesktopMetrics.pageTopPaddingCompact,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTree) ...[
                SizedBox(
                  width: 244,
                  // 侧栏条目随窗口高度变化，超出时自己滚，不挤压列表。
                  child: SingleChildScrollView(
                    child: _FilesRail(
                      state: state,
                      section: section,
                      stats: stats,
                      onSection: (value) => _goSection(controller, value),
                      onSharedRoot:
                          () => unawaited(controller.goToSharedSpaceRoot()),
                      onSpaceChanged:
                          (spaceType) => _switchSpace(controller, spaceType),
                      onOpenFolder:
                          (folder, path) => _openFolder(
                            controller,
                            folder,
                            shared: state?.spaceType == 'SHARED',
                            breadcrumbs: path,
                          ),
                      onMoveFiles:
                          (ids, target) => controller.moveFilesTo(ids, target),
                    ),
                  ),
                ),
                const SizedBox(width: 22),
              ],
              Expanded(
                child: DesktopGlassSurface(
                  borderRadius: BorderRadius.circular(18),
                  blur: 28,
                  saturation: 1.25,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                    decoration: BoxDecoration(
                      color: skin.panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: skin.line),
                      boxShadow: const <BoxShadow>[],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FilesToolbar(
                          controller: controller,
                          section: section,
                          state: state,
                          search: _search,
                          onSearch: controller.setSearchQuery,
                          grid: grid,
                          canUpload: canUpload,
                          onNewFolder:
                              () => _showNewFolderDialog(context, controller),
                          onUpload: () => _pickAndUpload(controller, state),
                          onEmptyRecycle:
                              () => _showPurgeDialog(
                                context,
                                controller,
                                state?.recycleBin ?? const <FileNode>[],
                              ),
                        ),
                        if (state != null && state.lastActionError != null) ...[
                          const SizedBox(height: 10),
                          _ActionErrorBanner(
                            message: state.lastActionError!.displayMessage,
                            onDismiss: controller.clearActionError,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _SectionNotices(section: section, state: state),
                        if (state != null && selected.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SelectionBar(
                            section: section,
                            state: state,
                            onClear: controller.clearSelection,
                            onDownload:
                                () => _downloadSelected(state, controller),
                            onDelete: () => _deleteSelected(controller, state),
                            onRestore: () => _restoreSelected(controller),
                            onPurge:
                                () => _showPurgeDialog(
                                  context,
                                  controller,
                                  _selectedNodes(state),
                                ),
                            onFavorite:
                                () => _favoriteSelected(state, controller),
                            onShare:
                                () => _showShareDialog(
                                  context,
                                  controller,
                                  _selectedNodes(state).first,
                                ),
                            onRename:
                                () => _showRenameDialog(
                                  context,
                                  controller,
                                  _selectedNodes(state).first,
                                ),
                          ),
                        ],
                        if (section == FileManagerSection.externalStorage) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _ExternalSection(
                                state: state,
                                controller: controller,
                              ),
                            ),
                          ),
                        ] else if (section == FileManagerSection.myShares ||
                            section == FileManagerSection.shareManagement) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _SharesSection(
                                state: state,
                                controller: controller,
                                onCopy:
                                    (link) => _copyShareLink(controller, link),
                              ),
                            ),
                          ),
                        ] else if (section ==
                            FileManagerSection.sharedWithMe) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _WithMeSection(
                                state: state,
                                controller: controller,
                              ),
                            ),
                          ),
                        ] else if (section ==
                            FileManagerSection.uploadQueue) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _UploadQueueSection(
                                state: state,
                                controller: controller,
                              ),
                            ),
                          ),
                        ] else if (section ==
                            FileManagerSection.importTasks) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _ImportTasksSection(state: state),
                            ),
                          ),
                        ] else if (section ==
                            FileManagerSection.storageStats) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _StorageSection(
                                stats: state?.storageStats ?? stats,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child:
                                state == null && async.isLoading
                                    ? SingleChildScrollView(
                                      child:
                                          grid
                                              ? const _FileGridSkeleton()
                                              : const DesktopSkeletonRows(
                                                count: 8,
                                              ),
                                    )
                                    : state == null && async.hasError
                                    ? DesktopErrorView(
                                      message: errorReason(async.error!, l10n),
                                      onRetry:
                                          () => ref.invalidate(
                                            fileBrowserControllerProvider,
                                          ),
                                      minHeightFactor: 0.24,
                                    )
                                    : grid
                                    ? SingleChildScrollView(
                                      child: _FileGrid(
                                        items: items,
                                        selected: selected,
                                        onTap:
                                            (node) => _activate(
                                              controller,
                                              node,
                                              shared:
                                                  state?.spaceType == 'SHARED',
                                            ),
                                        onSelect:
                                            (node) => _select(controller, node),
                                        onMenu:
                                            (node, position) => _openRowMenu(
                                              context,
                                              controller,
                                              state,
                                              node,
                                              position,
                                            ),
                                        onFavorite:
                                            section ==
                                                        FileManagerSection
                                                            .recycleBin ||
                                                    state?.spaceType == 'SHARED'
                                                ? null
                                                : (node) => unawaited(
                                                  node.favorited
                                                      ? controller
                                                          .removeFavorite(node)
                                                      : controller.addFavorite(
                                                        node,
                                                      ),
                                                ),
                                        onShare:
                                            section ==
                                                        FileManagerSection
                                                            .recycleBin ||
                                                    state?.spaceType == 'SHARED'
                                                ? null
                                                : (node) => _showShareDialog(
                                                  context,
                                                  controller,
                                                  node,
                                                ),
                                      ),
                                    )
                                    : CustomScrollView(
                                      slivers: [
                                        // 表头吸顶：行真的从表头下方滑过，模糊层
                                        // 才有可见对象（样例 `extra.css:70`）。
                                        // 空列表不画表头（样例 `Files.tsx:345` 的
                                        // `rows.length > 0` 条件）。
                                        if (items.isNotEmpty)
                                          SliverPersistentHeader(
                                            pinned: true,
                                            delegate: _StickyFileTableHead(
                                              sort:
                                                  state?.sortBy ??
                                                  FileBrowserSortBy.name,
                                              ascending:
                                                  state?.sortAscending ?? true,
                                              onSort:
                                                  (value) => _sortBy(
                                                    controller,
                                                    state,
                                                    value,
                                                  ),
                                            ),
                                          ),
                                        SliverList(
                                          delegate: SliverChildListDelegate([
                                            ..._groupedRows(
                                              state,
                                              controller,
                                              items,
                                              selected,
                                            ),
                                            if (state != null &&
                                                !state.isBusy &&
                                                items.isEmpty)
                                              _FilesEmpty(
                                                section: section,
                                                filtered:
                                                    (state
                                                        .searchQuery
                                                        .isNotEmpty) ||
                                                    state.fileCategory !=
                                                        FileBrowserFileCategory
                                                            .all,
                                                onClear: () {
                                                  _search.clear();
                                                  controller.setSearchQuery('');
                                                  controller.setFileCategory(
                                                    FileBrowserFileCategory.all,
                                                  );
                                                },
                                              ),
                                          ]),
                                        ),
                                      ],
                                    ),
                          ),
                        ],
                        if (state != null && _hasMore(state, section))
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: DesktopButton(
                                label: l10n.desktopFilesLoadMore(
                                  _loadedCount(state, section),
                                  _totalCount(state, section),
                                ),
                                variant: DesktopButtonVariant.ghost,
                                onPressed:
                                    () => _loadMore(controller, state, section),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final content = Stack(
      children: [
        _PageFocus(
          focusNode: _pageFocus,
          onKey: (event) => _handleKey(event, controller, state, section),
          child: page,
        ),
        if (state != null && _transfers(state).isNotEmpty)
          Positioned(
            right: 28,
            bottom: DesktopMetrics.playerBarClearance,
            child: _TransfersCard(state: state, controller: controller),
          ),
        if (_dragging)
          Positioned.fill(
            child: _DropVeil(
              target: _sectionTitle(AppLocalizations.of(context), section),
            ),
          ),
      ],
    );

    if (!PlatformCapabilities.current().supportsDragAndDropUpload) {
      return content;
    }
    return DropTarget(
      enable: canUpload,
      onDragEntered: (_) {
        _setDragging(true);
      },
      onDragExited: (_) {
        _setDragging(false);
        _clearExternalHover();
      },
      // 外部拖入时指针位置只有这条回调给得到：用它找出悬停的文件夹行，
      // 先高亮，悬停满 650ms 再把该目录打开（样例 `expandOnHover`）。
      onDragUpdated:
          (details) => _trackExternalHover(details.globalPosition, controller),
      onDragDone: (details) {
        _setDragging(false);
        _clearExternalHover();
        final files = details.files
            .whereType<DropItemFile>()
            .cast<XFile>()
            .toList(growable: false);
        if (files.isEmpty) {
          return;
        }
        unawaited(_upload(files, controller, state));
      },
      child: content,
    );
  }
}

/// 让整页接键盘：`Focus` 只在没有子控件抢焦点时收到事件，
/// 因此搜索框/弹窗内的按键不会被列表快捷键吃掉。
class _PageFocus extends StatelessWidget {
  const _PageFocus({
    required this.focusNode,
    required this.onKey,
    required this.child,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => onKey(event),
      child: child,
    );
  }
}
