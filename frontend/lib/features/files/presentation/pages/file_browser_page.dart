import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/workbench_navigation_bar.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/confirm_action_dialog.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/core/widgets/space_selector_sheet.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/share_link_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/features/files/presentation/widgets/file_grid.dart';
import 'package:omninest/features/files/presentation/widgets/file_list.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_page.dart';
import 'package:omninest/features/files/presentation/widgets/file_drop_upload_surface.dart';
import 'package:omninest/features/files/presentation/widgets/external_storage_account_dialog.dart';
import 'package:omninest/features/files/presentation/widgets/share_link_sheet.dart';
import 'package:omninest/features/files/presentation/widgets/upload_panel.dart';

part 'file_browser_page_navigation.dart';
part 'file_browser_page_workspace.dart';
part 'file_browser_page_upload.dart';
part 'file_browser_page_sharing.dart';
part 'file_browser_page_external.dart';
part 'file_browser_page_dialogs.dart';
part 'file_browser_page_mobile_actions.dart';

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
  _FileSidebarGroup.sharing: [
    FileManagerSection.sharedWithMe,
    FileManagerSection.myShares,
    FileManagerSection.shareManagement,
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

  void _onSectionChanged(FileManagerSection section) {
    if (_lastSection != null && _lastSection != section) {
      _sectionHistory.add(_lastSection!);
    }
    _lastSection = section;
    ref.read(fileBrowserControllerProvider.notifier).loadSection(section);
  }

  void _onBack() {
    if (_sectionHistory.isNotEmpty) {
      final prev = _sectionHistory.removeLast();
      _lastSection = prev;
      ref.read(fileBrowserControllerProvider.notifier).loadSection(prev);
    } else {
      context.go('/portal');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filesState = ref.watch(fileBrowserControllerProvider);
    if (widget.initialSection != null && !_initialSectionApplied) {
      final data = filesState.asData?.value;
      if (data != null && data.section != widget.initialSection) {
        _initialSectionApplied = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(fileBrowserControllerProvider.notifier)
              .loadSection(widget.initialSection!);
        });
      }
    }
    return filesState.when(
      data: (state) {
        _lastSection ??= state.section;
        return _FileManagerShell(
          state: state,
          onBack: _onBack,
          onSectionChanged: _onSectionChanged,
        );
      },
      error:
          (error, stackTrace) => Scaffold(
            body: AppErrorView(
              message: describeUserFacingError(error).displayMessage,
              onRetry: () => ref.invalidate(fileBrowserControllerProvider),
            ),
          ),
      loading: () => const Scaffold(body: AppLoading()),
    );
  }
}

class _FileManagerShell extends ConsumerWidget {
  const _FileManagerShell({
    required this.state,
    required this.onBack,
    required this.onSectionChanged,
  });

  final FileBrowserState state;
  final VoidCallback onBack;
  final void Function(FileManagerSection) onSectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final hosted = MobileShellScope.isHosted(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final currentDest = _destinationForSection(state.section);
        final selectedIndex =
            currentDest != null
                ? _FileNavDestination.values.indexOf(currentDest)
                : 0;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            onBack();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: Stack(
              children: [
                if (hosted)
                  const MobilePageSurface(
                    exposeBackdrop: true,
                    backdropOpacity: 0.56,
                    child: SizedBox.expand(),
                  )
                else
                  const _FileBackdrop(),
                // 主内容（延伸到顶部栏下方）
                Padding(
                  padding: EdgeInsets.only(
                    top: hosted ? 0 : WorkbenchTopBar.totalHeightOf(context),
                  ),
                  child: Column(
                    children: [
                      if (hosted && !isWide)
                        _FileMobileSectionBar(
                          section: state.section,
                          onSectionChanged: onSectionChanged,
                        ),
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
                                closeOnSelect: false,
                                onSectionChanged:
                                    (section) => unawaited(
                                      _runFileAction(
                                        context,
                                        () => controller.loadSection(section),
                                      ),
                                    ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
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
                                    child: _AnimatedSectionBody(state: state),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: RefreshIndicator(
                            displacement: 40,
                            edgeOffset: 64,
                            strokeWidth: 2.5,
                            color:
                                hosted
                                    ? context.mobileColors.musicAccent
                                    : context.filesColors.primary,
                            onRefresh: () async {
                              await _runFileAction(
                                context,
                                () => controller.loadSection(state.section),
                              );
                              await Future<void>.delayed(
                                const Duration(milliseconds: 200),
                              );
                            },
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                112,
                              ),
                              child: _AnimatedSectionBody(state: state),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 顶部工具栏
                if (!hosted)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _FileTopBar(state: state, showMenu: false),
                  ),
              ],
            ),
            floatingActionButton:
                isWide || state.hasSelection
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
                        onSectionChanged(section);
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
        );
      },
    );
  }
}

class _FileMobileSectionBar extends StatelessWidget {
  const _FileMobileSectionBar({
    required this.section,
    required this.onSectionChanged,
  });

  final FileManagerSection section;
  final ValueChanged<FileManagerSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const sections = <FileManagerSection>[
      FileManagerSection.allFiles,
      FileManagerSection.recent,
      FileManagerSection.favorites,
      FileManagerSection.sharedWithMe,
      FileManagerSection.recycleBin,
    ];
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = sections[index];
          return ChoiceChip(
            selected: value == section,
            showCheckmark: false,
            onSelected: (_) => onSectionChanged(value),
            avatar: Icon(value.icon, size: 17),
            label: Text(value.labelOf(l10n)),
          );
        },
      ),
    );
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

class _FileTopBar extends ConsumerWidget {
  const _FileTopBar({required this.state, required this.showMenu});

  final FileBrowserState state;
  final bool showMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final canSearch = switch (state.section) {
      FileManagerSection.allFiles ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin => true,
      _ => false,
    };
    return WorkbenchTopBar(
      surfaceColor: context.filesColors.surface,
      borderColor: context.filesColors.outlineVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            if (showMenu)
              Builder(
                builder:
                    (context) => IconButton(
                      tooltip: AppLocalizations.of(context).filesOpenFileMenu,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: Icon(Icons.menu_rounded),
                    ),
              ),
            TextButton.icon(
              onPressed: () => context.go('/portal'),
              icon: Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text(
                'Portal',
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.section.labelOf(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 24 / 15,
                  fontWeight: FontWeight.w800,
                  color: context.filesColors.primary,
                ),
              ),
            ),
            if (canSearch)
              IconButton(
                tooltip: l10n.filesSearch,
                onPressed: () => _showSearchOverlay(context, ref),
                icon: Icon(Icons.search_rounded, size: 20),
              ),
            IconButton(
              tooltip: l10n.filesRefresh,
              onPressed:
                  state.isBusy
                      ? null
                      : () => unawaited(
                        _runFileAction(
                          context,
                          () => controller.loadSection(state.section),
                        ),
                      ),
              icon: Icon(Icons.refresh_rounded, size: 20),
            ),
            if (MediaQuery.of(context).size.width >= 600) ...[
              const SizedBox(width: 16),
              const FontScaleControl(size: 20),
              const NotificationIcon(size: 20),
              const SizedBox(width: 8),
            ],
            const UserAvatarMenu(),
          ],
        ),
      ),
    );
  }

  void _showSearchOverlay(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.filesSearch,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder:
          (context, animation, secondaryAnimation) => Dialog(
            backgroundColor: Colors.transparent,
            child: _SearchOverlayCard(
              initialQuery:
                  ref
                      .read(fileBrowserControllerProvider)
                      .asData
                      ?.value
                      .searchQuery ??
                  '',
              onChanged: controller.setSearchQuery,
            ),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// 搜索弹窗 — 屏幕中间展开的玻璃卡片
class _SearchOverlayCard extends StatefulWidget {
  const _SearchOverlayCard({
    required this.initialQuery,
    required this.onChanged,
  });

  final String initialQuery;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchOverlayCard> createState() => _SearchOverlayCardState();
}

class _SearchOverlayCardState extends State<_SearchOverlayCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(20),
      backgroundColor: context.filesColors.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.filesSearchFiles,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.coreClose,
                icon: Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: l10n.filesSearchHint,
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

const Set<FileManagerSection> _superAdminOnlySections = {
  FileManagerSection.externalStorage,
  FileManagerSection.importTasks,
};
