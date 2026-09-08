import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/features/reader/presentation/pages/reader_center_page.dart'
    show kReaderSerifFamily;
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';

/// 阅读模块页面目标，对应模块内一级导航与路由
enum ReaderPageTarget { library, bookshelf, stats, admin }

extension ReaderPageTargetX on ReaderPageTarget {
  /// 对应的模块内路由
  String get location => switch (this) {
    ReaderPageTarget.library => '/reader',
    ReaderPageTarget.bookshelf => '/reader/bookshelf',
    ReaderPageTarget.stats => '/reader/stats',
    ReaderPageTarget.admin => '/reader/admin',
  };

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    ReaderPageTarget.library => l10n.readerNavLibrary,
    ReaderPageTarget.bookshelf => l10n.readerNavBookshelf,
    ReaderPageTarget.stats => l10n.readerNavStats,
    ReaderPageTarget.admin => l10n.readerNavManage,
  };

  IconData get icon => switch (this) {
    ReaderPageTarget.library => Icons.import_contacts_outlined,
    ReaderPageTarget.bookshelf => Icons.auto_stories_outlined,
    ReaderPageTarget.stats => Icons.bar_chart_rounded,
    ReaderPageTarget.admin => Icons.admin_panel_settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    ReaderPageTarget.library => Icons.import_contacts_rounded,
    ReaderPageTarget.bookshelf => Icons.auto_stories_rounded,
    ReaderPageTarget.stats => Icons.bar_chart_rounded,
    ReaderPageTarget.admin => Icons.admin_panel_settings_rounded,
  };
}

/// 阅读模块页面骨架，1:1 参照样例 App.tsx：
/// 44px 顶栏（返回门户 + 「OmniNest › 阅读」衬线面包屑 + 字号/通知/头像）、
/// 208px 左侧栏（≥1024，激活项前景色反白）、56px 底导航（<1024）、
/// 移动端托管态使用横排页签（全局壳已占底栏）。
class ReaderPageScaffold extends ConsumerStatefulWidget {
  const ReaderPageScaffold({
    required this.target,
    required this.child,
    this.searchController,
    this.onSearchChanged,
    this.onRefresh,
    this.header,
    super.key,
  });

  final ReaderPageTarget target;

  /// 页面内容（非滚动容器，由骨架负责滚动）
  final Widget child;

  /// 书库搜索控制器；传入后在窄屏提供搜索弹窗入口
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;

  final Future<void> Function()? onRefresh;

  /// 固定页头（置于内容滚动区上方，对应参考设计 sticky header）
  final Widget? header;

  @override
  ConsumerState<ReaderPageScaffold> createState() => _ReaderPageScaffoldState();
}

class _ReaderPageScaffoldState extends ConsumerState<ReaderPageScaffold> {
  void _goFallback() {
    context.go(
      widget.target == ReaderPageTarget.library
          ? '/portal'
          : ReaderPageTarget.library.location,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManage = user?.role == 'SUPER_ADMIN';
    if (widget.target == ReaderPageTarget.admin && !canManage) {
      return const _ReaderAdminForbidden();
    }

    final hosted = MobileShellScope.isHosted(context);
    final rc = context.readerColors;
    final targets = [
      ReaderPageTarget.library,
      ReaderPageTarget.bookshelf,
      ReaderPageTarget.stats,
      if (canManage) ReaderPageTarget.admin,
    ];

    final contentArea = _ReaderPageScrollArea(
      hosted: hosted,
      onRefresh: widget.onRefresh,
      header: widget.header,
      child: widget.child,
    );

    if (hosted) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _goFallback();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: ColoredBox(
            color: rc.surface,
            child: Column(
              children: [
                ReaderSectionTabBar(
                  current: widget.target,
                  canManage: canManage,
                ),
                contentArea,
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1024;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _goFallback();
          },
          child: Scaffold(
            backgroundColor: rc.surface,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReaderModuleTopBar(
                  target: widget.target,
                  user: user,
                  searchController: widget.searchController,
                  onSearchChanged: widget.onSearchChanged,
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isWide)
                        _ReaderSidebar(
                          current: widget.target,
                          targets: targets,
                        ),
                      Expanded(child: contentArea),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar:
                isWide
                    ? null
                    : _ReaderModuleBottomNav(
                      current: widget.target,
                      targets: targets,
                    ),
          ),
        );
      },
    );
  }
}

/// 44px 模块顶栏：返回门户 + 「OmniNest › 阅读」衬线面包屑 + 全局控件。
class _ReaderModuleTopBar extends StatelessWidget {
  const _ReaderModuleTopBar({
    required this.target,
    required this.user,
    this.searchController,
    this.onSearchChanged,
  });

  final ReaderPageTarget target;
  final UserProfile? user;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: rc.surface,
        border: Border(bottom: BorderSide(color: rc.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          InkWell(
            onTap: () => context.go('/portal'),
            borderRadius: BorderRadius.circular(2),
            child: Container(
              padding: const EdgeInsets.only(right: 12),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: rc.outlineVariant)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 14,
                    color: rc.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.readerPortal,
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            'OmniNest',
            style: TextStyle(
              color: rc.onSurface,
              fontSize: 14,
              height: 1.2,
              fontFamily: kReaderSerifFamily,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 12, color: rc.outlineVariant),
          const SizedBox(width: 6),
          Text(
            l10n.mobileNavReader,
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: 14,
              height: 1.2,
              fontFamily: kReaderSerifFamily,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
          FontScaleControl(size: 18, color: rc.onSurfaceVariant),
          NotificationIcon(size: 18, color: rc.onSurfaceVariant),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
        ],
      ),
    );
  }
}

/// 桌面左侧栏（w-52）：导航项激活为前景色反白。
class _ReaderSidebar extends StatelessWidget {
  const _ReaderSidebar({required this.current, required this.targets});

  final ReaderPageTarget current;
  final List<ReaderPageTarget> targets;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return Container(
      width: 208,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: rc.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final target in targets)
            _SidebarNavItem(
              target: target,
              selected: target == current,
              onTap: () => context.go(target.location),
            ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final ReaderPageTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      hoverColor: rc.surfaceContainerHigh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? rc.sidebarSelectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(
              selected ? target.selectedIcon : target.icon,
              size: 18,
              color: selected ? rc.sidebarSelectedFg : rc.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              target.localizedLabel(l10n),
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                color: selected ? rc.sidebarSelectedFg : rc.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 窄屏底导航（h-14）：图标 + 10px 标签，激活前景色。
class _ReaderModuleBottomNav extends StatelessWidget {
  const _ReaderModuleBottomNav({required this.current, required this.targets});

  final ReaderPageTarget current;
  final List<ReaderPageTarget> targets;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: rc.surface,
        border: Border(top: BorderSide(color: rc.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final target in targets)
                Expanded(
                  child: InkWell(
                    onTap: () => context.go(target.location),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          target == current ? target.selectedIcon : target.icon,
                          size: 18,
                          color:
                              target == current
                                  ? rc.onSurface
                                  : rc.onSurfaceVariant,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target.localizedLabel(l10n),
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color:
                                target == current
                                    ? rc.onSurface
                                    : rc.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 移动端托管态横排页签（全局壳内切换模块页面）。
class ReaderSectionTabBar extends StatelessWidget {
  const ReaderSectionTabBar({
    required this.current,
    required this.canManage,
    this.onChanged,
    super.key,
  });

  final ReaderPageTarget current;
  final bool canManage;

  /// 覆盖默认的路由跳转（测试或特殊导航场景使用）
  final ValueChanged<ReaderPageTarget>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final targets = [
      ReaderPageTarget.library,
      ReaderPageTarget.bookshelf,
      ReaderPageTarget.stats,
      if (canManage) ReaderPageTarget.admin,
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: rc.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            for (final target in targets)
              _ReaderSectionTab(
                target: target,
                selected: target == current,
                onTap: () {
                  if (target == current) return;
                  if (onChanged != null) {
                    onChanged!(target);
                  } else {
                    context.go(target.location);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderSectionTab extends StatelessWidget {
  const _ReaderSectionTab({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final ReaderPageTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final label = target.localizedLabel(AppLocalizations.of(context));
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? rc.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            height: 1.2,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? rc.onSurface : rc.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 页面内容滚动容器：横向内边距对齐样例（px-6 / lg:px-8），窄屏带下拉刷新。
class _ReaderPageScrollArea extends StatelessWidget {
  const _ReaderPageScrollArea({
    required this.hosted,
    required this.child,
    this.header,
    this.onRefresh,
  });

  final bool hosted;
  final Widget child;
  final Widget? header;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(wide ? 32 : 24, 24, wide ? 32 : 24, 40),
      child: child,
    );
    if (hosted) {
      return RefreshIndicator(
        displacement: 40,
        edgeOffset: 64,
        strokeWidth: 2.5,
        color: rc.reading,
        onRefresh: onRefresh ?? () async {},
        child: scroll,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 32 : 24, 24, wide ? 32 : 0, 0),
            child: header!,
          ),
        Expanded(
          child: RefreshIndicator(
            strokeWidth: 2.5,
            color: rc.reading,
            onRefresh: onRefresh ?? () async {},
            child: scroll,
          ),
        ),
      ],
    );
  }
}

/// 管理页无权限兜底视图（页签对非管理员隐藏，直接访问路由时展示）。
class _ReaderAdminForbidden extends StatelessWidget {
  const _ReaderAdminForbidden();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.readerColors.surface,
      body: Center(
        child: ReaderEmptyState(
          title: l10n.readerMetadataManagement,
          subtitle: l10n.readerManageHint,
          icon: Icons.admin_panel_settings_outlined,
        ),
      ),
    );
  }
}

/// 等宽数字（列表编号、百分比等）。
class ReaderTabularFigures extends StatelessWidget {
  const ReaderTabularFigures({
    required this.text,
    this.color,
    this.fontSize,
    super.key,
  });

  final String text;
  final Color? color;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? context.readerColors.onSurfaceVariant,
        fontSize: fontSize ?? 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
