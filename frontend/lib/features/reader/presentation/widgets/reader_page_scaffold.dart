import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
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
    this.onRefresh,
    this.header,
    this.headerPadding,
    this.enablePopGuard = true,
    super.key,
  });

  final ReaderPageTarget target;

  /// 页面内容（非滚动容器，由骨架负责滚动）
  final Widget child;

  final Future<void> Function()? onRefresh;

  /// 固定页头（置于内容滚动区上方，对应参考设计 sticky header）
  final Widget? header;

  /// 页头内边距；默认随书库等页头缩进，全宽页头（详情返回条）传 EdgeInsets.zero
  final EdgeInsetsGeometry? headerPadding;

  /// 是否拦截系统返回（模块主页面 true）；详情等推入页传 false 以保留自然返回
  final bool enablePopGuard;

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

    final rc = context.readerColors;
    final targets = [
      ReaderPageTarget.library,
      ReaderPageTarget.bookshelf,
      ReaderPageTarget.stats,
      if (canManage) ReaderPageTarget.admin,
    ];

    final contentArea = _ReaderPageScrollArea(
      onRefresh: widget.onRefresh,
      header: widget.header,
      headerPadding: widget.headerPadding,
      child: widget.child,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1024;
        return PopScope(
          canPop: !widget.enablePopGuard,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _goFallback();
          },
          child: Scaffold(
            backgroundColor: rc.surface,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReaderModuleTopBar(target: widget.target, user: user),
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

/// 模块顶栏：与其他模块一致的 WorkbenchTopBar 结构，
/// 左侧为返回门户与「OmniNest › 阅读」衬线面包屑，右侧控件自然尺寸内联排布。
class _ReaderModuleTopBar extends StatelessWidget {
  const _ReaderModuleTopBar({required this.target, required this.user});

  final ReaderPageTarget target;
  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    return WorkbenchTopBar(
      surfaceColor: rc.surface,
      borderColor: rc.outlineVariant,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 16),
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
                  fontSize: AppTypography.bodyMedium,
                  height: 18 / 13,
                  fontWeight: FontWeight.w700,
                  color: rc.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'OmniNest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rc.onSurface,
                        fontSize: AppTypography.bodyLarge,
                        height: 1.2,
                        fontFamily: kReaderSerifFamily,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 12,
                    color: rc.outlineVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l10n.mobileNavReader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rc.onSurfaceVariant,
                        fontSize: AppTypography.bodyLarge,
                        height: 1.2,
                        fontFamily: kReaderSerifFamily,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FontScaleControl(size: 20, color: rc.onSurfaceVariant),
            const SizedBox(width: 12),
            NotificationIcon(size: 20, color: rc.onSurfaceVariant),
            const SizedBox(width: 12),
            const UserAvatarMenu(),
          ],
        ),
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
    final mainTargets =
        targets.where((t) => t != ReaderPageTarget.admin).toList();
    final adminTargets =
        targets.where((t) => t == ReaderPageTarget.admin).toList();
    return Container(
      width: 208,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: rc.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final target in mainTargets)
            _SidebarNavItem(
              target: target,
              selected: target == current,
              onTap: () => context.go(target.location),
            ),
          const Spacer(),
          if (adminTargets.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: rc.outlineVariant)),
              ),
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final target in adminTargets)
                    _SidebarNavItem(
                      target: target,
                      selected: target == current,
                      onTap: () => context.go(target.location),
                    ),
                ],
              ),
            ),
          ],
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
                fontSize: AppTypography.bodyMedium,
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
                            // ignore: font_size_whitelist
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

/// 页面内容滚动容器：横向内边距对齐样例（px-6 / lg:px-8），窄屏带下拉刷新。
class _ReaderPageScrollArea extends StatelessWidget {
  const _ReaderPageScrollArea({
    required this.child,
    this.header,
    this.headerPadding,
    this.onRefresh,
  });

  final Widget child;
  final Widget? header;
  final EdgeInsetsGeometry? headerPadding;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding:
                headerPadding ??
                EdgeInsets.fromLTRB(wide ? 32 : 24, 24, wide ? 32 : 0, 0),
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
