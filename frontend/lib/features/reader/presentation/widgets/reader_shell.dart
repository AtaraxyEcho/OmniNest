import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/workbench_navigation_bar.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_search_overlay.dart';

part 'reader_shell_sidebar_item.dart';

/// 底部导航目标
enum _ReaderNavDestination {
  bookshelf(Icons.auto_stories_outlined, Icons.auto_stories),
  library(Icons.library_books_outlined, Icons.library_books),
  bookmarks(Icons.bookmark_outline, Icons.bookmark),
  notes(Icons.edit_note_outlined, Icons.edit_note);

  const _ReaderNavDestination(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    bookshelf => l10n.readerNavBookshelf,
    library => l10n.readerNavLibrary,
    bookmarks => l10n.readerNavBookmarks,
    notes => '笔记',
  };
}

/// 底部导航目标对应的 ReaderSection
ReaderSection _readerSectionForDestination(_ReaderNavDestination dest) {
  return switch (dest) {
    _ReaderNavDestination.bookshelf => ReaderSection.bookshelf,
    _ReaderNavDestination.library => ReaderSection.books,
    _ReaderNavDestination.bookmarks => ReaderSection.bookmarks,
    _ReaderNavDestination.notes => ReaderSection.notes,
  };
}

/// ReaderSection 对应的底部导航目标
_ReaderNavDestination _destinationForReaderSection(ReaderSection section) {
  return switch (section) {
    ReaderSection.bookshelf => _ReaderNavDestination.bookshelf,
    ReaderSection.books => _ReaderNavDestination.library,
    ReaderSection.bookmarks => _ReaderNavDestination.bookmarks,
    ReaderSection.notes => _ReaderNavDestination.notes,
    _ => _ReaderNavDestination.bookshelf,
  };
}

class ReaderShell extends ConsumerStatefulWidget {
  const ReaderShell({
    required this.section,
    required this.child,
    this.onSectionSelected,
    this.trailing,
    this.onSearch,
    this.onRefresh,
    super.key,
  });

  final ReaderSection section;
  final Widget child;
  final ValueChanged<ReaderSection>? onSectionSelected;
  final Widget? trailing;
  final ValueChanged<String>? onSearch;
  final Future<void> Function()? onRefresh;

  @override
  ConsumerState<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<ReaderShell> {
  final List<ReaderSection> _sectionHistory = [];
  ReaderSection? _lastSection;

  @override
  void didUpdateWidget(covariant ReaderShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section == widget.section || _lastSection == widget.section) {
      return;
    }
    if (_lastSection != null) {
      _sectionHistory.add(_lastSection!);
    }
    _lastSection = widget.section;
  }

  void _onSectionSelected(ReaderSection section) {
    if (_lastSection != null && _lastSection != section) {
      _sectionHistory.add(_lastSection!);
    }
    _lastSection = section;
    widget.onSectionSelected?.call(section);
  }

  void _onBack() {
    if (_sectionHistory.isNotEmpty) {
      final prev = _sectionHistory.removeLast();
      _lastSection = prev;
      widget.onSectionSelected?.call(prev);
      return;
    }
    if (_lastSection != null && _lastSection != ReaderSection.bookshelf) {
      _lastSection = ReaderSection.bookshelf;
      widget.onSectionSelected?.call(ReaderSection.bookshelf);
      return;
    }
    context.go('/portal');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hosted = MobileShellScope.isHosted(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManage = user?.role == 'SUPER_ADMIN';
    final effectiveSection =
        !widget.section.requiresManagementRole || canManage
            ? widget.section
            : ReaderSection.bookshelf;

    _lastSection ??= effectiveSection;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;
        final currentDest = _destinationForReaderSection(effectiveSection);
        final selectedIndex = _ReaderNavDestination.values.indexOf(currentDest);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _onBack();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: Stack(
              children: [
                // 页面背景层
                if (hosted)
                  const MobilePageSurface(
                    exposeBackdrop: true,
                    backdropOpacity: 0.56,
                    child: SizedBox.expand(),
                  )
                else
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const SizedBox.expand(),
                  ),
                // 主内容（延伸到顶部栏下方）
                Padding(
                  padding: EdgeInsets.only(
                    top: hosted ? 0 : WorkbenchTopBar.totalHeightOf(context),
                  ),
                  child: Column(
                    children: [
                      if (hosted &&
                          !isWide &&
                          effectiveSection != ReaderSection.bookshelf)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: MobileSubpageBackButton(
                              key: const ValueKey<String>(
                                'reader-mobile-section-back',
                              ),
                              onPressed: _onBack,
                            ),
                          ),
                        ),
                      Expanded(
                        child:
                            isWide
                                ? Row(
                                  children: [
                                    _ReaderSidebar(
                                      section: effectiveSection,
                                      canManage: canManage,
                                      closeOnSelect: false,
                                      onSectionSelected: _onSectionSelected,
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(
                                          40,
                                          28,
                                          40,
                                          40,
                                        ),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight:
                                                constraints.maxHeight - 64,
                                          ),
                                          child: AnimatedSwitcher(
                                            duration: MotionToken.resolve(
                                              context,
                                              MotionToken.pageSwitch,
                                            ),
                                            reverseDuration:
                                                MotionToken.resolve(
                                                  context,
                                                  MotionToken.fast,
                                                ),
                                            switchInCurve:
                                                MotionToken.pageCurve,
                                            switchOutCurve: MotionToken.curveIn,
                                            layoutBuilder: (
                                              currentChild,
                                              previousChildren,
                                            ) {
                                              return Stack(
                                                alignment: Alignment.topLeft,
                                                children: [
                                                  ...previousChildren,
                                                  if (currentChild != null)
                                                    currentChild,
                                                ],
                                              );
                                            },
                                            transitionBuilder: (
                                              child,
                                              animation,
                                            ) {
                                              final curved = CurvedAnimation(
                                                parent: animation,
                                                curve: MotionToken.pageCurve,
                                              );
                                              return FadeTransition(
                                                opacity: curved,
                                                child: SlideTransition(
                                                  position: Tween<Offset>(
                                                    begin: const Offset(
                                                      0,
                                                      0.012,
                                                    ),
                                                    end: Offset.zero,
                                                  ).animate(curved),
                                                  child: child,
                                                ),
                                              );
                                            },
                                            child: KeyedSubtree(
                                              key: ValueKey(effectiveSection),
                                              child: widget.child,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : _ReaderNarrowTabLayout(
                                  section: effectiveSection,
                                  onSectionSelected: _onSectionSelected,
                                  onRefresh: widget.onRefresh,
                                  minContentHeight: constraints.maxHeight - 64,
                                  child: widget.child,
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
                    child: _ReaderTopBar(
                      section: effectiveSection,
                      isWide: isWide,
                      canManage: canManage,
                      onSectionSelected: _onSectionSelected,
                      trailing: widget.trailing,
                      onSearch: widget.onSearch,
                      user: user,
                    ),
                  ),
              ],
            ),
            bottomNavigationBar:
                isWide || hosted
                    ? null
                    : WorkbenchNavigationBar(
                      currentIndex: selectedIndex,
                      onTap: (i) {
                        final dest = _ReaderNavDestination.values[i];
                        final readerSection = _readerSectionForDestination(
                          dest,
                        );
                        _onSectionSelected(readerSection);
                      },
                      items:
                          _ReaderNavDestination.values
                              .map(
                                (dest) => WorkbenchNavigationItem(
                                  icon: dest.icon,
                                  selectedIcon: dest.selectedIcon,
                                  label: dest.localizedLabel(l10n),
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

class _ReaderTopBar extends ConsumerWidget {
  const _ReaderTopBar({
    required this.section,
    required this.isWide,
    required this.canManage,
    required this.user,
    this.onSectionSelected,
    this.trailing,
    this.onSearch,
  });

  final ReaderSection section;
  final bool isWide;
  final bool canManage;
  final UserProfile? user;
  final ValueChanged<ReaderSection>? onSectionSelected;
  final Widget? trailing;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rc = context.readerColors;
    final barContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => context.go('/portal'),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: rc.onSurfaceVariant,
            ),
            label: Text(
              l10n.readerPortal,
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
                fontWeight: FontWeight.w700,
                color: rc.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(width: 12),
          Text(
            readerSectionLabel(l10n, section),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: rc.onSurface,
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Spacer(),
          MediaImportButton(
            subsystemDirectory: 'Reader',
            acceptedExtensions: const ['epub', 'txt', 'cbz', 'zip'],
            reuseExistingFiles: true,
            onImportComplete: () {
              ref.read(readerCenterControllerProvider.notifier).refresh();
            },
            style: ImportButtonStyle.iconButton,
            color: rc.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          // 搜索图标（移动端弹出搜索弹窗）
          if (!isWide && onSearch != null) ...[
            _SearchIconButton(onSearch: onSearch!, colors: rc),
            const SizedBox(width: 8),
          ] else if (trailing != null) ...[
            SizedBox(width: 20),
            trailing!,
            const SizedBox(width: 16),
          ],
          if (isWide) ...[
            FontScaleControl(size: 20, color: rc.onSurfaceVariant),
            NotificationIcon(size: 20, color: rc.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          const UserAvatarMenu(),
        ],
      ),
    );

    return WorkbenchTopBar(
      surfaceColor: rc.surface,
      borderColor: rc.outlineVariant,
      child: barContent,
    );
  }
}

class _ReaderSidebar extends StatelessWidget {
  const _ReaderSidebar({
    required this.section,
    required this.canManage,
    required this.closeOnSelect,
    this.onSectionSelected,
  });

  final ReaderSection section;
  final bool canManage;
  final bool closeOnSelect;
  final ValueChanged<ReaderSection>? onSectionSelected;

  static String _sectionLabel(AppLocalizations l10n, ReaderSection s) =>
      switch (s) {
        ReaderSection.bookshelf => l10n.readerNavBookshelf,
        ReaderSection.books => l10n.readerNavLibrary,
        ReaderSection.comics => l10n.readerNavComics,
        ReaderSection.bookmarks => l10n.readerNavBookmarks,
        ReaderSection.notes => l10n.readerNavNotes,
        ReaderSection.history => l10n.readerHistory,
        ReaderSection.imports => l10n.readerImports,
        ReaderSection.metadata => l10n.readerMetadataManagement,
      };

  static String _groupLabel(AppLocalizations l10n, ReaderSidebarGroup g) =>
      switch (g) {
        ReaderSidebarGroup.library => l10n.readerNavLibrary,
        ReaderSidebarGroup.personal => l10n.readerGroupPersonal,
        ReaderSidebarGroup.tools => l10n.readerGroupTools,
        ReaderSidebarGroup.management => l10n.readerGroupManagement,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = readerSidebarGroups.entries.where(
      (entry) => canManage || entry.key != ReaderSidebarGroup.management,
    );
    return Container(
      width: 280,
      padding: EdgeInsets.fromLTRB(14, 20, 14, 20),
      decoration: BoxDecoration(
        color: context.readerColors.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: context.readerColors.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).readerCenter,
                  style: TextStyle(
                    color: context.readerColors.onSurface,
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'OmniNest',
                  style: TextStyle(
                    color: context.readerColors.onSurfaceVariant,
                    fontSize: 11,
                    height: 14 / 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final entry in groups) ...[
                  _SidebarGroupLabel(_groupLabel(l10n, entry.key)),
                  const SizedBox(height: 6),
                  for (final item in entry.value)
                    _SidebarNavItem(
                      label: _sectionLabel(l10n, item),
                      icon: item.icon,
                      selected: item == section,
                      closeOnSelect: closeOnSelect,
                      onTap: () {
                        onSectionSelected?.call(item);
                        if (closeOnSelect) {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                  SizedBox(height: 14),
                ],
              ],
            ),
          ),
          if (!canManage)
            Padding(
              padding: EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Text(
                l10n.readerManageHint,
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant,
                  fontSize: 11,
                  height: 14 / 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 窄屏布局：可滚动 TabBar + 内容区域。
/// TabBar 显示 7 个用户分区，点击切换时通过 [onSectionSelected] 回调通知外部。
/// 搜索图标按钮，点击弹出搜索覆盖层。
class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({required this.onSearch, required this.colors});

  final ValueChanged<String> onSearch;
  final ReaderColors colors;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).readerSearch,
      icon: Icon(
        Icons.search_rounded,
        size: 22,
        color: colors.onSurfaceVariant,
      ),
      onPressed: () => _showSearchDialog(context),
    );
  }

  void _showSearchDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    // dispose 兜底标记：dialog future 异常中断时控制器也不会重复释放
    var controllerDisposed = false;
    void disposeController() {
      if (controllerDisposed) return;
      controllerDisposed = true;
      controller.dispose();
    }

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.readerSearch,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder:
          (context, animation, secondaryAnimation) => Dialog(
            backgroundColor: Colors.transparent,
            child: ReaderSearchOverlay(
              controller: controller,
              colors: colors,
              onSearch: (query) {
                if (query.trim().isNotEmpty) {
                  onSearch(query.trim());
                  Navigator.of(context).pop();
                }
              },
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
    ).whenComplete(disposeController);
  }
}

class _ReaderNarrowTabLayout extends StatelessWidget {
  const _ReaderNarrowTabLayout({
    required this.section,
    required this.child,
    required this.minContentHeight,
    this.onSectionSelected,
    this.onRefresh,
  });

  final ReaderSection section;
  final Widget child;
  final double minContentHeight;
  final ValueChanged<ReaderSection>? onSectionSelected;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final hosted = MobileShellScope.isHosted(context);
    return RefreshIndicator(
      displacement: 40,
      edgeOffset: 64,
      strokeWidth: 2.5,
      color:
          hosted
              ? context.mobileColors.musicAccent
              : context.readerColors.primary,
      onRefresh: onRefresh ?? () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 72),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minContentHeight),
          child: AnimatedSwitcher(
            duration: MotionToken.resolve(context, MotionToken.pageSwitch),
            reverseDuration: MotionToken.resolve(context, MotionToken.fast),
            switchInCurve: MotionToken.pageCurve,
            switchOutCurve: MotionToken.curveIn,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.topLeft,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: MotionToken.pageCurve,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.018),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(key: ValueKey(section), child: child),
          ),
        ),
      ),
    );
  }
}
