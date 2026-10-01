import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/module_entry_refresh_listener.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/errors/user_facing_error_l10n.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/core/widgets/app_form_factor.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/hosted_touch_canvas.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/workbench_navigation_bar.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/core/widgets/space_selector_sheet.dart';
import 'package:omninest/core/widgets/responsive_search_field.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/features/files/presentation/widgets/file_grid.dart';
import 'package:omninest/features/files/presentation/widgets/file_list.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_page.dart';
import 'package:omninest/features/files/presentation/widgets/file_drop_upload_surface.dart';
import 'package:omninest/features/files/presentation/widgets/external_storage_account_dialog.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/features/files/presentation/widgets/files_table_view.dart';
import 'package:omninest/features/files/presentation/widgets/hover_horizontal_scroll.dart';
import 'package:omninest/features/files/presentation/widgets/file_inspector_panel.dart';
import 'package:omninest/features/files/presentation/widgets/files_toolbar_control.dart';
import 'package:omninest/features/files/presentation/widgets/share_link_sheet.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

part 'files_operation_l10n.dart';
part 'file_browser_page_navigation.dart';
part 'file_browser_page_workspace.dart';
part 'file_browser_page_upload.dart';
part 'file_browser_page_sharing.dart';
part 'file_browser_page_external.dart';
part 'file_browser_page_batch.dart';
part 'file_browser_page_subpage.dart';
part 'file_browser_page_share_workspaces.dart';
part 'file_browser_page_transfer_workspaces.dart';
part 'file_browser_page_inspector.dart';
part 'file_browser_page_folder_picker.dart';
part 'file_browser_page_dialogs.dart';
part 'file_browser_page_mobile_actions.dart';
part 'file_browser_page_mobile_home.dart';

/// Inspector 常驻 dock 的自适应阈值：窗口窄于该值时隐藏 dock，
/// 检视改走贴底抽屉，为表格保留完整宽度。
abstract final class FilesInspectorAdaptive {
  static const double dockMinWidth = 1440;

  /// 仅文件列表分区提供检视：传输/分享/存储等子页没有可检视的
  /// FileNode，常驻抽屉只会挤占空间。
  static bool sectionHasFileList(FileManagerSection section) {
    return switch (section) {
      FileManagerSection.allFiles ||
      FileManagerSection.sharedSpace ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin ||
      FileManagerSection.storageStats => true,
      _ => false,
    };
  }
}

extension FileManagerSectionMeta on FileManagerSection {
  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      FileManagerSection.allFiles => l10n.filesAllFiles,
      FileManagerSection.recent => l10n.filesRecent,
      FileManagerSection.favorites => l10n.filesFavorites,
      FileManagerSection.recycleBin => l10n.filesRecycleBin,
      FileManagerSection.sharedSpace => l10n.filesSharedSpace,
      FileManagerSection.sharedWithMe => l10n.filesSharedWithMe,
      FileManagerSection.myShares => l10n.filesMyShares,
      FileManagerSection.shareManagement => l10n.filesShareManagement,
      FileManagerSection.storageStats => l10n.filesStorageStats,
      FileManagerSection.uploadQueue => l10n.filesUploadQueue,
      FileManagerSection.offlineDownloads => l10n.filesOfflineDownloads,
      FileManagerSection.externalStorage => l10n.filesExternalStorage,
      FileManagerSection.importTasks => l10n.filesImportTasks,
    };
  }

  String descriptionOf(AppLocalizations l10n) {
    return switch (this) {
      FileManagerSection.allFiles => l10n.filesAllFilesDesc,
      FileManagerSection.recent => l10n.filesRecentDesc,
      FileManagerSection.favorites => l10n.filesFavoritesDesc,
      FileManagerSection.recycleBin => l10n.filesRecycleBinDesc,
      FileManagerSection.sharedSpace => l10n.filesSharedSpaceDesc,
      FileManagerSection.sharedWithMe => l10n.filesSharedWithMeDesc,
      FileManagerSection.myShares => l10n.filesMySharesDesc,
      FileManagerSection.shareManagement => l10n.filesShareManagementDesc,
      FileManagerSection.storageStats => l10n.filesStorageStatsDesc,
      FileManagerSection.uploadQueue => l10n.filesUploadQueueDesc,
      FileManagerSection.offlineDownloads => l10n.filesOfflineDownloadsDesc,
      FileManagerSection.externalStorage => l10n.filesExternalStorageDesc,
      FileManagerSection.importTasks => l10n.filesImportTasksDesc,
    };
  }

  IconData get icon {
    return switch (this) {
      FileManagerSection.allFiles => Icons.folder_open_outlined,
      FileManagerSection.recent => Icons.history_rounded,
      FileManagerSection.favorites => Icons.star_border_rounded,
      FileManagerSection.recycleBin => Icons.delete_outline_rounded,
      FileManagerSection.sharedSpace => Icons.workspaces_outlined,
      FileManagerSection.sharedWithMe => Icons.group_outlined,
      FileManagerSection.myShares => Icons.ios_share_rounded,
      FileManagerSection.shareManagement => Icons.link_rounded,
      FileManagerSection.storageStats => Icons.pie_chart_outline_rounded,
      FileManagerSection.uploadQueue => Icons.cloud_upload_outlined,
      FileManagerSection.offlineDownloads =>
        Icons.download_for_offline_outlined,
      FileManagerSection.externalStorage => Icons.cloud_queue_rounded,
      FileManagerSection.importTasks => Icons.cloud_download_rounded,
    };
  }
}

extension FileBrowserFileCategoryMeta on FileBrowserFileCategory {
  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      FileBrowserFileCategory.all => l10n.filesCategoryAll,
      FileBrowserFileCategory.image => l10n.filesCategoryImage,
      FileBrowserFileCategory.video => l10n.filesCategoryVideo,
      FileBrowserFileCategory.audio => l10n.filesCategoryAudio,
      FileBrowserFileCategory.document => l10n.filesCategoryDocument,
      FileBrowserFileCategory.novel => l10n.filesCategoryNovel,
      FileBrowserFileCategory.comic => l10n.filesCategoryComic,
      FileBrowserFileCategory.archive => l10n.filesCategoryArchive,
      FileBrowserFileCategory.other => l10n.filesCategoryOther,
    };
  }

  IconData get icon {
    return switch (this) {
      FileBrowserFileCategory.all => Icons.all_inclusive_rounded,
      FileBrowserFileCategory.image => Icons.image_outlined,
      FileBrowserFileCategory.video => Icons.movie_outlined,
      FileBrowserFileCategory.audio => Icons.library_music_outlined,
      FileBrowserFileCategory.document => Icons.description_outlined,
      FileBrowserFileCategory.novel => Icons.menu_book_outlined,
      FileBrowserFileCategory.comic => Icons.auto_stories_outlined,
      FileBrowserFileCategory.archive => Icons.inventory_2_outlined,
      FileBrowserFileCategory.other => Icons.category_outlined,
    };
  }
}

enum _FileSidebarGroup {
  files,
  sharing,
  transfer,
  storage;

  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      _FileSidebarGroup.files => l10n.filesGroupFiles,
      _FileSidebarGroup.sharing => l10n.filesGroupSharing,
      _FileSidebarGroup.transfer => l10n.filesGroupTransfer,
      _FileSidebarGroup.storage => l10n.filesGroupStorage,
    };
  }
}

const Map<_FileSidebarGroup, List<FileManagerSection>> _fileSidebarGroups = {
  _FileSidebarGroup.files: [
    FileManagerSection.allFiles,
    FileManagerSection.recent,
    FileManagerSection.favorites,
    FileManagerSection.recycleBin,
  ],
  // shareManagement 已并入 myShares（页内“我的/全部”作用域切换）。
  _FileSidebarGroup.sharing: [
    FileManagerSection.sharedWithMe,
    FileManagerSection.myShares,
  ],
  _FileSidebarGroup.transfer: [
    FileManagerSection.uploadQueue,
    FileManagerSection.offlineDownloads,
  ],
  _FileSidebarGroup.storage: [
    FileManagerSection.externalStorage,
    FileManagerSection.importTasks,
  ],
};

/// 底部导航栏目标项
enum _FileNavDestination {
  files(Icons.folder_outlined, Icons.folder),
  recent(Icons.history_rounded, Icons.history_rounded),
  shared(Icons.group_outlined, Icons.group_outlined),
  recycleBin(Icons.delete_outline_rounded, Icons.delete_outline_rounded);

  const _FileNavDestination(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      _FileNavDestination.files => l10n.filesNavFiles,
      _FileNavDestination.recent => l10n.filesNavRecent,
      _FileNavDestination.shared => l10n.filesNavShared,
      _FileNavDestination.recycleBin => l10n.filesNavRecycleBin,
    };
  }
}

/// 底部导航栏目标项对应的默认 section
FileManagerSection _defaultSectionForDestination(_FileNavDestination dest) {
  return switch (dest) {
    _FileNavDestination.files => FileManagerSection.allFiles,
    _FileNavDestination.recent => FileManagerSection.recent,
    _FileNavDestination.shared => FileManagerSection.sharedWithMe,
    _FileNavDestination.recycleBin => FileManagerSection.recycleBin,
  };
}

/// 当前 section 对应的底部导航目标项
_FileNavDestination? _destinationForSection(FileManagerSection section) {
  return switch (section) {
    FileManagerSection.allFiles ||
    FileManagerSection.favorites => _FileNavDestination.files,
    FileManagerSection.recent => _FileNavDestination.recent,
    FileManagerSection.sharedWithMe ||
    FileManagerSection.myShares ||
    FileManagerSection.shareManagement => _FileNavDestination.shared,
    FileManagerSection.recycleBin => _FileNavDestination.recycleBin,
    _ => null,
  };
}

class FileBrowserPage extends ConsumerStatefulWidget {
  const FileBrowserPage({super.key, this.initialSection});

  final FileManagerSection? initialSection;

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends ConsumerState<FileBrowserPage> {
  bool _initialSectionApplied = false;
  final List<FileManagerSection> _sectionHistory = [];
  FileManagerSection? _lastSection;

  /// 移动首页态：true 时显示位置/分区卡首页，点卡进入列表态。
  bool _mobileHomeOpen = true;

  void _onSectionChanged(FileManagerSection section) {
    if (_lastSection != null && _lastSection != section) {
      _sectionHistory.add(_lastSection!);
    }
    _lastSection = section;
    ref.read(fileBrowserControllerProvider.notifier).loadSection(section);
  }

  void _onBack() {
    // 托管窄屏：列表态优先回首页，首页态走原有返回链（section 历史栈 → 门户）。
    final hosted = MobileShellScope.isHosted(context);
    final narrow = MediaQuery.sizeOf(context).width < 1100;
    if (hosted && narrow && !_mobileHomeOpen) {
      ref.read(fileBrowserControllerProvider.notifier).clearSelection();
      // 回到首页即回到导航根：清空分区历史栈，首页态的返回直接离站，
      // 否则历史栈残留会让返回做一次不可见的分区回退（返回键失灵观感）。
      _sectionHistory.clear();
      setState(() => _mobileHomeOpen = true);
      return;
    }
    if (_sectionHistory.isNotEmpty) {
      final prev = _sectionHistory.removeLast();
      _lastSection = prev;
      ref.read(fileBrowserControllerProvider.notifier).loadSection(prev);
    } else {
      context.go('/portal');
    }
  }

  /// 从首页打开分区：进入列表态。
  void _openMobileSection(FileManagerSection section) {
    _onSectionChanged(section);
    if (!_mobileHomeOpen) {
      return;
    }
    setState(() => _mobileHomeOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final filesState = ref.watch(fileBrowserControllerProvider);
    if (widget.initialSection != null && !_initialSectionApplied) {
      final data = filesState.asData?.value;
      if (data != null && data.section != widget.initialSection) {
        _initialSectionApplied = true;
        _mobileHomeOpen = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(fileBrowserControllerProvider.notifier)
              .loadSection(widget.initialSection!);
        });
      }
    }
    return ModuleEntryRefreshListener(
      modulePath: '/files',
      onRefresh:
          () => unawaited(
            ref
                .read(fileBrowserControllerProvider.notifier)
                .refreshForRealtime(),
          ),
      child: filesState.when(
        data: (state) {
          _lastSection ??= state.section;
          return _FileManagerShell(
            state: state,
            onBack: _onBack,
            onSectionChanged: _onSectionChanged,
            mobileHomeOpen: _mobileHomeOpen,
            onOpenMobileSection: _openMobileSection,
          );
        },
        error:
            (error, stackTrace) => Scaffold(
              body: AppErrorView(
                message: AppLocalizations.of(
                  context,
                ).localizeUserFacing(describeUserFacingError(error)),
                onRetry: () => ref.invalidate(fileBrowserControllerProvider),
              ),
            ),
        loading: () => const Scaffold(body: AppLoading()),
      ),
    );
  }
}

class _FileManagerShell extends ConsumerStatefulWidget {
  const _FileManagerShell({
    required this.state,
    required this.onBack,
    required this.onSectionChanged,
    required this.mobileHomeOpen,
    required this.onOpenMobileSection,
  });

  final FileBrowserState state;
  final VoidCallback onBack;
  final void Function(FileManagerSection) onSectionChanged;

  /// 移动首页态与其打开分区的回调（仅托管窄屏使用）。
  final bool mobileHomeOpen;
  final void Function(FileManagerSection) onOpenMobileSection;

  @override
  ConsumerState<_FileManagerShell> createState() => _FileManagerShellState();
}

class _FileManagerShellState extends ConsumerState<_FileManagerShell> {
  /// 窄屏贴底抽屉是否在场（防止 listen 重复弹层）。
  bool _inspectorSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final hosted = MobileShellScope.isHosted(context);
    ref.listen(
      fileBrowserControllerProvider.select(
        (async) => async.asData?.value.inspectedFileId,
      ),
      (previous, next) {
        if (!mounted) {
          return;
        }
        // 常驻 dock 仅在 ≥1440 的工作位出现；中窄宽度检视改走贴底
        // 抽屉，避免侧栏+抽屉挤压表格造成列溢出（skill 自适应形态）。
        final wide =
            MediaQuery.sizeOf(context).width >=
                FilesInspectorAdaptive.dockMinWidth &&
            !MobileShellScope.isHosted(context);
        if (next == null) {
          _closeInspectorSheet();
          return;
        }
        if (!FilesInspectorAdaptive.sectionHasFileList(widget.state.section)) {
          return;
        }
        if (!wide && !_inspectorSheetOpen) {
          unawaited(_showInspectorSheet(controller));
        }
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 桌面侧栏路径仅非托管窗口使用；托管态（手机/平板）一律走触屏布局。
        // 阈值与 DesktopFormMinWidth 同源于 ResponsiveBreakpoints.workbenchRail。
        final isWide =
            omniCanvasFormOf(context, constraints) ==
            OmniCanvasForm.desktopRail;
        final currentDest = _destinationForSection(state.section);
        final selectedIndex =
            currentDest != null
                ? _FileNavDestination.values.indexOf(currentDest)
                : 0;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            widget.onBack();
          },
          child: FilesWorkstationScope(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              body: Stack(
                children: [
                  if (!hosted) const _FileBackdrop(),
                  // 主内容（延伸到顶部栏下方）
                  Padding(
                    padding: EdgeInsets.only(
                      top: hosted ? 0 : WorkbenchTopBar.totalHeightOf(context),
                    ),
                    // 托管态触屏内容按壳层 chrome 同宽封顶居中：平板宽度下
                    // 卡片行/列表行不被整屏拉伸，与底栏 tab 组同语言。
                    child: HostedTouchCanvas(
                      hosted: hosted,
                      maxContentWidth: MobileLayoutTokens.chromeMaxWidth,
                      child: Column(
                        children: [
                          if (hosted && !isWide && !widget.mobileHomeOpen) ...[
                            _FileMobileBackRow(onBack: widget.onBack),
                            _FileHostedSearchBar(section: state.section),
                          ],
                          if (state.lastActionError case final error?)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                              child: _FileActionStatusBar(
                                error: error,
                                onDismissError:
                                    () =>
                                        ref
                                            .read(
                                              fileBrowserControllerProvider
                                                  .notifier,
                                            )
                                            .clearActionError(),
                              ),
                            ),
                          if (isWide)
                            Expanded(
                              child: Row(
                                children: [
                                  _FileSidebar(
                                    state: state,
                                    enabled: true,
                                    onSectionChanged:
                                        (section) => unawaited(
                                          _runFileAction(
                                            context,
                                            () =>
                                                controller.loadSection(section),
                                          ),
                                        ),
                                  ),
                                  Expanded(
                                    // 文件工作区自身提供滚动主体，避免外层
                                    // SingleChildScrollView 关闭列表虚拟化。
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        34,
                                        26,
                                        34,
                                        40,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 1500,
                                        ),
                                        child: _AnimatedSectionBody(
                                          state: state,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isWide &&
                                      MediaQuery.sizeOf(context).width >=
                                          FilesInspectorAdaptive.dockMinWidth &&
                                      FilesInspectorAdaptive.sectionHasFileList(
                                        state.section,
                                      ))
                                    _InspectorDock(state: state),
                                ],
                              ),
                            )
                          else if (hosted && widget.mobileHomeOpen)
                            Expanded(
                              child: _FileMobileHome(
                                state: state,
                                onOpenSection: widget.onOpenMobileSection,
                              ),
                            )
                          else
                            Expanded(
                              child: RefreshIndicator(
                                displacement: 40,
                                edgeOffset: 64,
                                strokeWidth: 2.5,
                                color: context.filesColors.onSurfaceVariant,
                                onRefresh: () async {
                                  await _runFileAction(
                                    context,
                                    () => controller.loadSection(state.section),
                                  );
                                  await Future<void>.delayed(
                                    MotionToken.pageSwitch,
                                  );
                                },
                                child: Padding(
                                  // 托管态无自有底栏，仅按 FAB 悬浮净距预留。
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    16,
                                    hosted ? 96 : 112,
                                  ),
                                  child: _AnimatedSectionBody(state: state),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 顶部工具栏
                  if (!hosted)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _FileTopBar(state: state),
                    ),
                ],
              ),
              floatingActionButton:
                  isWide ||
                          state.hasSelection ||
                          (hosted && widget.mobileHomeOpen)
                      ? null
                      : _FileMobileCreateButton(
                        state: state,
                        controller: controller,
                      ),
              bottomNavigationBar:
                  isWide || hosted
                      ? null
                      : WorkbenchNavigationBar(
                        currentIndex: selectedIndex,
                        onTap: (i) {
                          final dest = _FileNavDestination.values[i];
                          final section = _defaultSectionForDestination(dest);
                          widget.onSectionChanged(section);
                        },
                        items:
                            _FileNavDestination.values
                                .map(
                                  (dest) => WorkbenchNavigationItem(
                                    icon: dest.icon,
                                    selectedIcon: dest.selectedIcon,
                                    label: dest.labelOf(
                                      AppLocalizations.of(context),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
            ),
          ),
        );
      },
    );
  }

  /// 窄屏贴底抽屉：Inspector 的移动形态（Header/Footer 常驻、Body 滚动、
  /// 视口 85% 上限），关闭即清空检视态。
  Future<void> _showInspectorSheet(FileBrowserController controller) async {
    final context = this.context;
    _inspectorSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final state =
                sheetRef.watch(fileBrowserControllerProvider).asData?.value;
            final node = state?.inspectedNode;
            if (node == null) {
              return const SizedBox.shrink();
            }
            final favorites = state!.section == FileManagerSection.favorites;
            final actions = _buildFileNodeActions(
              context,
              sheetRef,
              sheetRef.read(fileBrowserControllerProvider.notifier),
              recycle: state.section == FileManagerSection.recycleBin,
              favorites: favorites,
            );
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              margin: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: context.filesColors.surfaceContainer,
                border: Border(
                  top: BorderSide(color: context.filesColors.selectedBorder),
                ),
              ),
              child: FileInspectorPanel(
                file: node,
                actions: actions,
                onClose:
                    () =>
                        sheetRef
                            .read(fileBrowserControllerProvider.notifier)
                            .clearInspection(),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _inspectorSheetOpen = false;
      final current = ref.read(fileBrowserControllerProvider).asData?.value;
      if (current?.inspectedFileId != null) {
        ref.read(fileBrowserControllerProvider.notifier).clearInspection();
      }
    });
  }

  void _closeInspectorSheet() {
    if (!_inspectorSheetOpen || !mounted) {
      return;
    }
    _inspectorSheetOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class _FileBackdrop extends StatelessWidget {
  const _FileBackdrop();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const SizedBox.expand(),
    );
  }
}

/// 56px 工位顶栏：PORTAL 入口、在线徽章、空间联动徽章、32px 搜索槽
/// 与系统级辅助控件（刷新 / 主题 / Aa / 通知 / 头像）。
///
/// 页面级控件（视图切换、上传、详情栏开关）一律下沉工作区工具栏，
/// 严禁出现在全局顶栏。
class _FileTopBar extends ConsumerStatefulWidget {
  const _FileTopBar({required this.state});

  final FileBrowserState state;

  @override
  ConsumerState<_FileTopBar> createState() => _FileTopBarState();
}

class _FileTopBarState extends ConsumerState<_FileTopBar> with RouteTopAware {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final TopBarSearchFocusHandle _searchFocusHandle;

  @override
  void initState() {
    super.initState();
    _searchFocusHandle = TopBarSearchFocusRegistry.instance.register(
      TopBarSearchFocusEntry(
        focus: _searchFocusNode.requestFocus,
        isActive: _isShortcutTarget,
      ),
    );
  }

  /// Ctrl/Cmd+F 目标自检：路由在栈顶且当前分区支持节内搜索。
  bool _isShortcutTarget() {
    if (!isRouteTop) {
      return false;
    }
    return _fileSectionSupportsSearch(widget.state.section);
  }

  @override
  void didUpdateWidget(covariant _FileTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.section != widget.state.section) {
      _searchController.clear();
    } else {
      final query = widget.state.searchQuery;
      if (_searchController.text != query) {
        _searchController.text = query;
      }
    }
  }

  @override
  void dispose() {
    _searchFocusHandle.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final canSearch = _fileSectionSupportsSearch(widget.state.section);
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final colors = context.filesColors;
    return WorkbenchTopBar(
      surfaceColor: colors.surface,
      borderColor: colors.outlineVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            WorkstationPortalLink(onTap: () => context.go('/portal')),
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: colors.outlineVariant),
            const SizedBox(width: 12),
            Text(
              'OmniNest Files / ${widget.state.section.labelOf(l10n)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.titleSmall,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 10),
            const _TopBarOnlineBadge(),
            const SizedBox(width: 8),
            _TopBarSpaceBadge(spaceType: widget.state.spaceType),
            const Spacer(),
            if (canSearch) ...[
              _TopBarSearchSlot(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: controller.setSearchQuery,
                hintText: l10n.filesSearchHint,
                width: isNarrow ? 180.0 : 280.0,
              ),
              const SizedBox(width: 10),
            ],

            if (MediaQuery.of(context).size.width >= 600) ...[
              const SizedBox(width: 8),
              const FontScaleControl(size: 20),
              const SizedBox(width: 8),
              const NotificationIcon(size: 20),
            ],
            const SizedBox(width: 8),
            const UserAvatarMenu(),
          ],
        ),
      ),
    );
  }
}

/// 在线状态徽章：surface-2 底 + 1px 细线 + 实时相位驱动的状态点。
class _TopBarOnlineBadge extends ConsumerWidget {
  const _TopBarOnlineBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(realtimePhaseProvider).asData?.value;
    final (dotColor, pulsing) = switch (phase) {
      RealtimePhase.healthy ||
      RealtimePhase.subscribed ||
      RealtimePhase.catchingUp => (context.filesColors.success, true),
      RealtimePhase.connecting ||
      RealtimePhase.reconnecting => (context.filesColors.warning, false),
      RealtimePhase.degraded => (context.filesColors.error, false),
      RealtimePhase.signedOut ||
      null => (context.filesColors.onSurfaceVariant, false),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.filesColors.surfaceContainer,
        border: Border.all(color: context.filesColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: dotColor, pulsing: pulsing),
          const SizedBox(width: 6),
          Text(
            phase == null || phase == RealtimePhase.signedOut
                ? 'OFFLINE'
                : 'ONLINE',
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelMicro,
              letterSpacing: 1.5,
              color: context.filesColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空间联动徽章：随工作区当前空间切换的只读指示。
class _TopBarSpaceBadge extends StatelessWidget {
  const _TopBarSpaceBadge({required this.spaceType});

  final String spaceType;

  @override
  Widget build(BuildContext context) {
    final isShared = spaceType == 'SHARED';
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.filesColors.surfaceContainerLow,
        border: Border.all(color: context.filesColors.outlineVariant),
      ),
      child: Center(
        child: Text(
          isShared
              ? AppLocalizations.of(context).importToSharedSpace
              : AppLocalizations.of(context).importToPersonalSpace,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.labelMicro,
            letterSpacing: 1,
            color: context.filesColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 顶栏 32px 搜索槽：凹入槽体 + 右侧等宽 Ctrl/Cmd+F 快捷键提示。
class _TopBarSearchSlot extends StatelessWidget {
  const _TopBarSearchSlot({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hintText,
    required this.width,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    // 快捷键徽标作为输入框内 suffix 呈现，避免悬挂在框外破坏 32px 高度。
    final base = filesWorkstationInputDecoration(context, hintText: hintText);
    return SizedBox(
      width: width,
      height: 32,
      child: ResponsiveSearchField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        hintText: hintText,
        maxWidth: double.infinity,
        decoration: base.copyWith(
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              topBarSearchKeycapLabel,
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: AppTypography.labelMicro,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 32,
          ),
          suffixStyle: const TextStyle(),
        ),
      ),
    );
  }
}

const Set<FileManagerSection> _superAdminOnlySections = {
  FileManagerSection.externalStorage,
  FileManagerSection.importTasks,
};

/// 当前 section 是否支持节内搜索。
bool _fileSectionSupportsSearch(FileManagerSection section) =>
    switch (section) {
      FileManagerSection.allFiles ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin => true,
      _ => false,
    };

/// 托管态页内搜索条：壳层顶栏搜索钮展开，保留节内目录定位能力。
class _FileHostedSearchBar extends ConsumerStatefulWidget {
  const _FileHostedSearchBar({required this.section});

  final FileManagerSection section;

  @override
  ConsumerState<_FileHostedSearchBar> createState() =>
      _FileHostedSearchBarState();
}

class _FileHostedSearchBarState extends ConsumerState<_FileHostedSearchBar>
    with RouteTopAware {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final TopBarSearchFocusHandle _searchFocusHandle;

  /// 展开态在 build 中缓存，按键回调期不再触碰 ref。
  bool _searchActive = false;

  @override
  void initState() {
    super.initState();
    _searchFocusHandle = TopBarSearchFocusRegistry.instance.register(
      TopBarSearchFocusEntry(
        focus: _searchFocusNode.requestFocus,
        isActive: _isShortcutTarget,
      ),
    );
  }

  /// Ctrl/Cmd+F 目标自检：路由在栈顶、搜索条处于展开态且分区支持搜索。
  bool _isShortcutTarget() {
    if (!isRouteTop) {
      return false;
    }
    return _searchActive && _fileSectionSupportsSearch(widget.section);
  }

  @override
  void didUpdateWidget(covariant _FileHostedSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchFocusHandle.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(
      mobileModuleSearchActiveProvider(MobileModuleSearchHosts.files),
    );
    _searchActive = active;
    if (!active || !_fileSectionSupportsSearch(widget.section)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    return Container(
      color: context.filesColors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: ResponsiveSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: controller.setSearchQuery,
              hintText: l10n.filesSearchHint,
              maxWidth: double.infinity,
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).coreClose,
            onPressed: () {
              ref
                  .read(
                    mobileModuleSearchActiveProvider(
                      MobileModuleSearchHosts.files,
                    ).notifier,
                  )
                  .set(false);
              controller.setSearchQuery('');
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
