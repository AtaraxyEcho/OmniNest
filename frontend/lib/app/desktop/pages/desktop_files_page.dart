import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_import_filter.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_pager.dart';
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

  FileManagerSection? _appliedSection;
  String? _selectionAnchorId;
  bool _dragging = false;
  String? _externalHoverId;
  Timer? _expandTimer;
  final Map<String, GlobalKey> _folderKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _expandTimer?.cancel();
    _search.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  void _setDragging(bool value) {
    if (!mounted || _dragging == value) {
      return;
    }
    setState(() => _dragging = value);
  }

  GlobalKey _folderKey(String id) => _folderKeys.putIfAbsent(id, GlobalKey.new);

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

  Future<void> _handleDroppedItems(
    List<DropItem> droppedItems,
    FileBrowserController controller,
    FileBrowserState? state,
  ) async {
    final files = await expandDroppedItems(droppedItems);
    if (!mounted || files.isEmpty) {
      return;
    }
    await _upload(files, controller, state);
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availH = constraints.maxHeight;
                    final rawCardHeight =
                        availH <= 500
                            ? availH
                            : (availH * 0.88).clamp(500.0, 760.0);
                    final cardHeight =
                        availH.isFinite && availH > 0
                            ? math.min(availH, rawCardHeight)
                            : 640.0;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        height: cardHeight,
                        child: DesktopGlassSurface(
                          borderRadius: BorderRadius.circular(18),
                          blur: 28,
                          saturation: 1.25,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                            decoration: BoxDecoration(
                              // 浅色主题对齐 polish.css:548：半透明柔白底 + 柔和投影。
                              color:
                                  skin.isDark
                                      ? skin.panel
                                      : const Color(0xCCF7F9F6),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: skin.line),
                              boxShadow:
                                  skin.isDark
                                      ? const <BoxShadow>[]
                                      : const <BoxShadow>[
                                        BoxShadow(
                                          color: Color(0x0F1C2320),
                                          blurRadius: 24,
                                          offset: Offset(0, 8),
                                        ),
                                        BoxShadow(
                                          color: Color(0x081C2320),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
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
                                      () => _beginNewFolder(controller, state),
                                  onUpload:
                                      () => _pickAndUpload(controller, state),
                                  onEmptyRecycle:
                                      () => _showPurgeDialog(
                                        context,
                                        controller,
                                        state?.recycleBin ?? const <FileNode>[],
                                      ),
                                ),
                                if (state != null &&
                                    state.lastActionError != null) ...[
                                  const SizedBox(height: 10),
                                  _ActionErrorBanner(
                                    message:
                                        state.lastActionError!.displayMessage,
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
                                        () => _downloadSelected(
                                          state,
                                          controller,
                                        ),
                                    onDelete:
                                        () =>
                                            _deleteSelected(controller, state),
                                    onRestore:
                                        () => _restoreSelected(controller),
                                    onPurge:
                                        () => _showPurgeDialog(
                                          context,
                                          controller,
                                          _selectedNodes(state),
                                        ),
                                    onFavorite:
                                        () => _favoriteSelected(
                                          state,
                                          controller,
                                        ),
                                    onMoveToShared:
                                        () => _moveSelectedToSpace(
                                          controller,
                                          state,
                                          toShared: true,
                                        ),
                                    onMoveToPersonal:
                                        () => _moveSelectedToSpace(
                                          controller,
                                          state,
                                          toShared: false,
                                        ),
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
                                if (section ==
                                    FileManagerSection.externalStorage) ...[
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: _ExternalSection(
                                        state: state,
                                        controller: controller,
                                      ),
                                    ),
                                  ),
                                ] else if (section ==
                                        FileManagerSection.myShares ||
                                    section ==
                                        FileManagerSection.shareManagement) ...[
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: _SharesSection(
                                        state: state,
                                        controller: controller,
                                        onCopy:
                                            (link) => _copyShareLink(
                                              controller,
                                              link,
                                            ),
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
                                              message: errorReason(
                                                async.error!,
                                                l10n,
                                              ),
                                              onRetry:
                                                  () => ref.invalidate(
                                                    fileBrowserControllerProvider,
                                                  ),
                                              minHeightFactor: 0.24,
                                            )
                                            : grid
                                            ? SingleChildScrollView(
                                              child:
                                                  items.isEmpty &&
                                                          (section !=
                                                                  FileManagerSection
                                                                      .allFiles ||
                                                              state?.draftFolderName ==
                                                                  null)
                                                      ? _FilesEmpty(
                                                        section: section,
                                                        shared:
                                                            state?.spaceType ==
                                                            'SHARED',
                                                        filtered:
                                                            (state
                                                                    ?.searchQuery
                                                                    .isNotEmpty ??
                                                                false) ||
                                                            state?.fileCategory !=
                                                                FileBrowserFileCategory
                                                                    .all,
                                                        onClear: () {
                                                          _search.clear();
                                                          controller
                                                              .setSearchQuery(
                                                                '',
                                                              );
                                                          controller
                                                              .setFileCategory(
                                                                FileBrowserFileCategory
                                                                    .all,
                                                              );
                                                        },
                                                      )
                                                      : _FileGrid(
                                                        items: items,
                                                        draftFolderName:
                                                            section ==
                                                                    FileManagerSection
                                                                        .allFiles
                                                                ? state
                                                                    ?.draftFolderName
                                                                : null,
                                                        onDraftSubmit:
                                                            controller
                                                                .commitFolderCreation,
                                                        onDraftCancel:
                                                            controller
                                                                .cancelFolderCreation,
                                                        selected: selected,
                                                        draggable:
                                                            section !=
                                                            FileManagerSection
                                                                .recycleBin,
                                                        externalHoverId:
                                                            _externalHoverId,
                                                        folderKeyBuilder:
                                                            _folderKey,
                                                        onDropFiles:
                                                            (
                                                              ids,
                                                              targetId,
                                                            ) => unawaited(
                                                              controller
                                                                  .moveFilesTo(
                                                                    ids,
                                                                    targetId,
                                                                  ),
                                                            ),
                                                        onTap:
                                                            (node) => _activate(
                                                              controller,
                                                              node,
                                                              shared:
                                                                  state
                                                                      ?.spaceType ==
                                                                  'SHARED',
                                                            ),
                                                        onSelect:
                                                            (node) => _select(
                                                              controller,
                                                              node,
                                                              orderedItems:
                                                                  items,
                                                            ),
                                                        onToggleSelect:
                                                            (node) =>
                                                                _toggleSelect(
                                                                  controller,
                                                                  node,
                                                                ),
                                                        onMenu:
                                                            (node, position) =>
                                                                _openRowMenu(
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
                                                                    state?.spaceType ==
                                                                        'SHARED'
                                                                ? null
                                                                : (
                                                                  node,
                                                                ) => unawaited(
                                                                  node.favorited
                                                                      ? controller
                                                                          .removeFavorite(
                                                                            node,
                                                                          )
                                                                      : controller
                                                                          .addFavorite(
                                                                            node,
                                                                          ),
                                                                ),
                                                        onShare:
                                                            section ==
                                                                        FileManagerSection
                                                                            .recycleBin ||
                                                                    state?.spaceType ==
                                                                        'SHARED'
                                                                ? null
                                                                : (node) =>
                                                                    _showShareDialog(
                                                                      context,
                                                                      controller,
                                                                      node,
                                                                    ),
                                                      ),
                                            )
                                            : CustomScrollView(
                                              shrinkWrap: false,
                                              slivers: [
                                                if (items.isNotEmpty)
                                                  SliverPersistentHeader(
                                                    pinned: true,
                                                    delegate: _StickyFileTableHead(
                                                      sort:
                                                          state?.sortBy ??
                                                          FileBrowserSortBy
                                                              .name,
                                                      ascending:
                                                          state
                                                              ?.sortAscending ??
                                                          true,
                                                      onSort:
                                                          (value) => _sortBy(
                                                            controller,
                                                            state,
                                                            value,
                                                          ),
                                                      allSelected:
                                                          items.isNotEmpty &&
                                                          items.every(
                                                            (node) => selected
                                                                .contains(
                                                                  node.id,
                                                                ),
                                                          ),
                                                      someSelected: items.any(
                                                        (node) => selected
                                                            .contains(node.id),
                                                      ),
                                                      onToggleSelectAll:
                                                          () =>
                                                              _toggleSelectAll(
                                                                controller,
                                                                items,
                                                                selected,
                                                              ),
                                                    ),
                                                  ),
                                                SliverList(
                                                  delegate: SliverChildListDelegate([
                                                    if (section ==
                                                            FileManagerSection
                                                                .allFiles &&
                                                        state?.draftFolderName !=
                                                            null)
                                                      _DesktopDraftFolderRow(
                                                        defaultName:
                                                            state!
                                                                .draftFolderName!,
                                                        onSubmit:
                                                            controller
                                                                .commitFolderCreation,
                                                        onCancel:
                                                            controller
                                                                .cancelFolderCreation,
                                                      ),
                                                    ..._groupedRows(
                                                      state,
                                                      controller,
                                                      items,
                                                      selected,
                                                    ),
                                                    if (state != null &&
                                                        !state.isBusy &&
                                                        items.isEmpty &&
                                                        (section !=
                                                                FileManagerSection
                                                                    .allFiles ||
                                                            state.draftFolderName ==
                                                                null))
                                                      _FilesEmpty(
                                                        section: section,
                                                        shared:
                                                            state.spaceType ==
                                                            'SHARED',
                                                        filtered:
                                                            (state
                                                                .searchQuery
                                                                .isNotEmpty) ||
                                                            state.fileCategory !=
                                                                FileBrowserFileCategory
                                                                    .all,
                                                        onClear: () {
                                                          _search.clear();
                                                          controller
                                                              .setSearchQuery(
                                                                '',
                                                              );
                                                          controller
                                                              .setFileCategory(
                                                                FileBrowserFileCategory
                                                                    .all,
                                                              );
                                                        },
                                                      ),
                                                  ]),
                                                ),
                                              ],
                                            ),
                                  ),
                                ],
                                if (state != null &&
                                    _isPagedSection(section) &&
                                    _totalCount(state, section) > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: DesktopPager(
                                      page: _currentPage(state, section),
                                      pageSize: _pageSize(state, section),
                                      totalItems: _totalCount(state, section),
                                      pageSizeOptions: const [10, 20, 50],
                                      onPageChanged:
                                          (nextPage) => unawaited(
                                            controller.goToPage(
                                              section,
                                              page: nextPage,
                                            ),
                                          ),
                                      onPageSizeChanged:
                                          (nextSize) => unawaited(
                                            controller.goToPage(
                                              section,
                                              page: 0,
                                              size: nextSize,
                                            ),
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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
              target:
                  state?.spaceType == 'SHARED'
                      ? AppLocalizations.of(context).filesSharedSpace
                      : _sectionTitle(AppLocalizations.of(context), section),
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
      onDragUpdated:
          (details) => _trackExternalHover(details.globalPosition, controller),
      onDragDone: (details) {
        _setDragging(false);
        _clearExternalHover();
        unawaited(_handleDroppedItems(details.files, controller, state));
      },
      child: content,
    );
  }
}

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
