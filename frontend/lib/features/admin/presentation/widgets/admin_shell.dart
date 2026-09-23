import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/features/tasks/task_ui.dart';
import 'package:omninest/core/widgets/app_form_factor.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/auth/auth_controller.dart';

part 'admin_shell_navigation.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({
    required this.section,
    required this.onSectionChanged,
    required this.child,
    super.key,
  });

  final AdminSection section;
  final ValueChanged<AdminSection> onSectionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            omniCanvasFormOf(context, constraints) ==
            OmniCanvasForm.desktopRail;
        final isUltraWide = constraints.maxWidth >= 1920;
        final l10n = AppLocalizations.of(context);
        final content = Column(
          children: [
            _AdminTopBar(section: section, isWide: isWide),
            Expanded(
              child: Row(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child:
                        isWide
                            ? AdminSidebar(
                              selectedSection: section,
                              closeOnSelect: false,
                              onSectionChanged: onSectionChanged,
                            )
                            : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: _AdminShellBody(
                      section: section,
                      isWide: isWide,
                      isUltraWide: isUltraWide,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        return PopScope(
          canPop: true,
          child: Scaffold(
            extendBody: true,
            bottomNavigationBar:
                isWide
                    ? null
                    : NavigationBar(
                      height: 70,
                      backgroundColor: context.mobileColors.surface,
                      indicatorColor: context.mobileColors.surfaceSelected,
                      selectedIndex: _adminDockIndex(section),
                      onDestinationSelected: (i) {
                        final target = _adminDockSection(i);
                        if (target != null && target != section) {
                          onSectionChanged(target);
                        }
                      },
                      destinations: [
                        NavigationDestination(
                          icon: Icon(Icons.dashboard_customize_outlined),
                          selectedIcon: Icon(Icons.dashboard_customize_rounded),
                          label: l10n.adminGroupOverview,
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.group_outlined),
                          selectedIcon: Icon(Icons.group_rounded),
                          label: l10n.adminNavUsers,
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.pending_actions_outlined),
                          selectedIcon: Icon(Icons.pending_actions_rounded),
                          label: l10n.adminNavTasks,
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          selectedIcon: Icon(Icons.receipt_long_rounded),
                          label: l10n.adminNavLogs,
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.tune_rounded),
                          selectedIcon: Icon(Icons.tune_rounded),
                          label: l10n.adminNavConfig,
                        ),
                      ],
                    ),
            body:
                isWide
                    ? Stack(children: [const _AdminBackdrop(), content])
                    : MobilePageSurface(child: content),
          ),
        );
      },
    );
  }
}

class _AdminShellBody extends StatelessWidget {
  const _AdminShellBody({
    required this.section,
    required this.isWide,
    required this.isUltraWide,
    required this.child,
  });

  final AdminSection section;
  final bool isWide;
  final bool isUltraWide;
  final Widget child;

  /// 需要填满剩余空间的页面（如带 TabBarView 的日志中心）。
  static const Set<AdminSection> _fillSections = {
    AdminSection.logs,
    AdminSection.tasks,
  };

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      isWide ? 40 : 18,
      32,
      isWide ? 40 : 18,
      isWide ? 40 : 92,
    );
    final slideOffset =
        isWide ? MotionToken.slideDesktop : MotionToken.slideMobile;
    final content = AnimatedSwitcher(
      duration: MotionToken.normal,
      switchInCurve: MotionToken.curve,
      switchOutCurve: MotionToken.curveIn,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: MotionToken.curve,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: slideOffset,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: Align(
        key: ValueKey(section),
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // 超宽屏（≥1920）解除内容宽度上限，充分利用 4K 全屏空间；
          // 常规宽度仍居中限宽，避免可读性劣化。
          constraints: BoxConstraints(
            maxWidth: isUltraWide ? double.infinity : 1480,
          ),
          child: child,
        ),
      ),
    );
    if (_fillSections.contains(section) && isWide) {
      return Padding(padding: padding, child: content);
    }
    return SingleChildScrollView(padding: padding, child: content);
  }
}

/// 返回 Portal：优先 pop（保留 Portal shell 状态），无栈可弹时兜底 go。
void _backToPortal(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/portal');
  }
}

class AdminSidebar extends ConsumerStatefulWidget {
  const AdminSidebar({
    required this.selectedSection,
    required this.closeOnSelect,
    required this.onSectionChanged,
    super.key,
  });

  final AdminSection selectedSection;
  final bool closeOnSelect;
  final ValueChanged<AdminSection> onSectionChanged;

  @override
  ConsumerState<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends ConsumerState<AdminSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _storageFade;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(duration: MotionToken.slow, vsync: this);
    _titleFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0, 0.35, curve: MotionToken.curve),
    );
    _titleSlide = Tween<Offset>(
      begin: MotionToken.slideContent,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0, 0.35, curve: MotionToken.curve),
      ),
    );
    _storageFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.6, 1, curve: MotionToken.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!_reducedMotion && !_entrance.isCompleted) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// 为第 [index] 个导航项计算交错的淡入+滑入动画。
  ({Animation<double> fade, Animation<Offset> slide}) _itemAnimation(
    int index,
  ) {
    final start = index * MotionToken.elementStagger;
    final end = (start + MotionToken.elementExtent).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: MotionToken.curve),
    );
    return (
      fade: curve,
      slide: Tween<Offset>(
        begin: MotionToken.slideContent,
        end: Offset.zero,
      ).animate(curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return Container(
      // 256 与常见桌面侧栏一致；原先 220 扣除内边距后品牌名仅约 112px，
      // 会被 ellipsis 截断成 “OmniNe…”。
      width: AppControlTokens.sidebarWidth,
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 24),
      decoration: BoxDecoration(
        color: c.surfaceContainerLow.withValues(alpha: 0.88),
        border: Border(
          right: BorderSide(color: c.outlineVariant.withValues(alpha: 0.18)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题区域 — 淡入+上滑
          FadeTransition(
            opacity:
                _reducedMotion ? const AlwaysStoppedAnimation(1) : _titleFade,
            child: SlideTransition(
              position:
                  _reducedMotion
                      ? const AlwaysStoppedAnimation(Offset.zero)
                      : _titleSlide,
              child: const _AdminSideTitle(),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(child: ListView(children: _buildNavChildren(context))),
          const SizedBox(height: 14),
          // 存储状态卡片 — 淡入
          FadeTransition(
            opacity:
                _reducedMotion ? const AlwaysStoppedAnimation(1) : _storageFade,
            child: const _SidebarStorageStatus(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNavChildren(BuildContext context) {
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>{};
    final children = <Widget>[];
    var navIndex = 0;
    for (final entry in AdminSection.visibleGrouped(permissions).entries) {
      children.add(
        _SidebarGroupLabel(
          label: _sectionGroupLabel(AppLocalizations.of(context), entry.key),
        ),
      );
      children.add(const SizedBox(height: 8));
      for (final section in entry.value) {
        children.add(
          _buildNavItem(
            navIndex,
            section: section,
            selected: widget.selectedSection == section,
          ),
        );
        navIndex++;
      }
      children.add(const SizedBox(height: 14));
    }
    return children;
  }

  Widget _buildNavItem(
    int index, {
    required AdminSection section,
    required bool selected,
  }) {
    final item = _AdminNavItem(
      section: section,
      selected: selected,
      closeOnSelect: widget.closeOnSelect,
      onSectionChanged: widget.onSectionChanged,
    );
    if (_reducedMotion) return item;
    final anim = _itemAnimation(index);
    return FadeTransition(
      opacity: anim.fade,
      child: SlideTransition(position: anim.slide, child: item),
    );
  }
}

class _AdminBackdrop extends StatelessWidget {
  const _AdminBackdrop();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const SizedBox.expand(),
    );
  }
}

class _AdminTopBar extends ConsumerWidget {
  const _AdminTopBar({required this.section, required this.isWide});

  final AdminSection section;
  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.adminColors;
    final l10n = AppLocalizations.of(context);
    return WorkbenchTopBar(
      surfaceColor: c.surface,
      borderColor: c.outlineVariant,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 8),
        child: Row(
          children: [
            if (isWide) ...[
              _TopBarPortalButton(onPressed: () => _backToPortal(context)),
              const SizedBox(width: 12),
              AdminStatusPill(
                label: l10n.adminRolePillLabel,
                color: c.tertiary,
              ),
              const SizedBox(width: 12),
            ] else
              IconButton(
                onPressed: () => _backToPortal(context),
                icon: Icon(Icons.arrow_back_rounded),
                tooltip: AppLocalizations.of(context).profileBackTooltip,
              ),
            Expanded(
              child: Text(
                _sectionTitle(AppLocalizations.of(context), section),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.titleMedium,
                  height: 24 / 16,
                  color: context.adminColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (isWide) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: _AdminSearchField(ref: ref),
              ),
              const SizedBox(width: 16),
              const FontScaleControl(size: 20),
              const TaskActivityButton(size: 20),
              const NotificationIcon(size: 20),
              const SizedBox(width: 12),
              const UserAvatarMenu(),
            ] else ...[
              IconButton(
                onPressed: () => _showMobileSearch(context, ref),
                icon: Icon(Icons.search_rounded),
                tooltip: AppLocalizations.of(context).adminSearchHint,
              ),
              IconButton(
                onPressed: () => _showMobileSections(context),
                icon: Icon(Icons.menu_rounded),
                tooltip: AppLocalizations.of(context).adminOpenMenu,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showMobileSearch(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminSearchHint),
            content: _AdminSearchField(ref: ref, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.coreCancel),
              ),
            ],
          ),
    );
  }

  Future<void> _showMobileSections(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mobileColors.surface,
      showDragHandle: true,
      builder: (context) => _MobileAdminSectionSheet(selected: section),
    );
  }
}

class _AdminSearchField extends StatelessWidget {
  const _AdminSearchField({required this.ref, this.autofocus = false});

  final WidgetRef ref;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.adminColors;
    return TextField(
      autofocus: autofocus,
      onChanged:
          (query) => ref.read(adminSearchProvider.notifier).updateQuery(query),
      style: TextStyle(
        color: colors.onSurface,
        fontSize: AppTypography.bodyMedium,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.82),
        hintText: AppLocalizations.of(context).adminSearchHint,
        prefixIcon: Icon(Icons.search_rounded, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _MobileAdminSectionSheet extends ConsumerWidget {
  const _MobileAdminSectionSheet({required this.selected});

  final AdminSection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>{};
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            for (final entry
                in AdminSection.visibleGrouped(permissions).entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(
                  _sectionGroupLabel(l10n, entry.key),
                  style: TextStyle(
                    color: context.mobileColors.textSecondary,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final item in entry.value)
                ListTile(
                  minTileHeight: MobileLayoutTokens.minimumTarget,
                  leading: Icon(
                    _iconFor(item),
                    color:
                        item == selected
                            ? context.mobileColors.musicAccent
                            : context.mobileColors.textSecondary,
                  ),
                  title: Text(
                    _sectionLabel(l10n, item),
                    style: TextStyle(
                      color: context.mobileColors.textPrimary,
                      fontWeight:
                          item == selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  selected: item == selected,
                  selectedTileColor: context.mobileColors.surfaceSelected,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    // 分区深链：/admin/:section，由 AdminDashboardPage 解析。
                    context.go(item.location);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBarPortalButton extends StatelessWidget {
  const _TopBarPortalButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.arrow_back_rounded, size: 18),
      label: Text(AppLocalizations.of(context).adminTopBarPortal),
      style: TextButton.styleFrom(
        textStyle: TextStyle(
          fontSize: AppTypography.bodyMedium,
          height: 18 / 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminSideTitle extends StatelessWidget {
  const _AdminSideTitle();

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final l10n = AppLocalizations.of(context);
    return Padding(
      // 与导航项内缩接近，品牌行不至于贴边，同时给标题更多宽度。
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const BrandLogo.sidebar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.adminShellTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: AppTypography.titleSmall + 1,
                    height: 20 / 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.adminShellSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: AppTypography.labelSmall,
                    height: 14 / 11,
                    color: c.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: AppTypography.labelSmall,
          height: 14 / 11,
          color: context.adminColors.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
