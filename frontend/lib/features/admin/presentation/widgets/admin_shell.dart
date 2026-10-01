import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/app_form_factor.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/theme/admin_workstation_theme.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/auth/auth_controller.dart';

part 'admin_shell_navigation.dart';

/// 管理控制台工位外壳。
///
/// 外层以 [AdminWorkstationScope] 注入建筑极简主义工位皮肤
/// （Zinc 调色、全直角、1px 细线、零阴影），内部结构：
/// 56px 顶栏 + 256px 侧栏（宽屏）/ 底部导航（窄屏）+ 内容区。
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
    return AdminWorkstationScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              omniCanvasFormOf(context, constraints) ==
              OmniCanvasForm.desktopRail;
          final isUltraWide = constraints.maxWidth >= 1920;
          final l10n = AppLocalizations.of(context);
          final scheme = Theme.of(context).colorScheme;
          final content = Column(
            children: [
              _AdminTopBar(section: section, isWide: isWide),
              Expanded(
                child: Row(
                  children: [
                    if (isWide)
                      AdminSidebar(
                        selectedSection: section,
                        closeOnSelect: false,
                        onSectionChanged: onSectionChanged,
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
                        height: 64,
                        elevation: 0,
                        backgroundColor: scheme.surface,
                        indicatorColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
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
                            selectedIcon: Icon(Icons.dashboard_customize),
                            label: l10n.adminGroupOverview,
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.badge_outlined),
                            selectedIcon: Icon(Icons.badge),
                            label: l10n.adminNavUsers,
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.task_alt_outlined),
                            selectedIcon: Icon(Icons.task_alt),
                            label: l10n.adminNavTasks,
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.receipt_long_outlined),
                            selectedIcon: Icon(Icons.receipt_long),
                            label: l10n.adminNavLogs,
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.tune_outlined),
                            selectedIcon: Icon(Icons.tune),
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
      ),
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
    // 规范：侧栏切换联动主区 160ms 纯淡入，不做位移动画。
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: MotionToken.curve,
      switchOutCurve: MotionToken.curveIn,
      // 分区切换会整棵替换内容，退场子树排除语义。
      layoutBuilder: excludeExitingSemanticsStack,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Align(
        key: ValueKey(section),
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // 超宽屏（≥1920）解除内容宽度上限，充分利用 4K 全屏空间；
          // 常规宽度仍居中限宽 1920，宽屏下高密表格优先铺满工作区，
          // 避免两侧大块空白（旧 1600 上限与表格 maxTableWidth 双重收窄
          // 曾导致列表居中且两侧留白）。
          constraints: BoxConstraints(
            maxWidth: isUltraWide ? double.infinity : 1920,
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
  exitDetailRoute(context, fallbackRoute: '/portal');
}

/// 桌面工位侧栏：256px、根画板底色、右侧 1px 细线。
///
/// 结构自上而下：品牌卡（状态点 + 等宽副标）→ 分组导航
/// （上方 flex 滚动）→ 底部固定存储微卡（shrink-0）。
class AdminSidebar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>{};
    return Container(
      width: AppControlTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AdminSideHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                for (final entry
                    in AdminSection.visibleGrouped(permissions).entries) ...[
                  _SidebarGroupLabel(
                    label: _sectionGroupLabel(l10n, entry.key),
                    code: _sectionGroupCode(entry.key),
                  ),
                  const SizedBox(height: 6),
                  for (final section in entry.value)
                    _AdminNavItem(
                      section: section,
                      selected: selectedSection == section,
                      closeOnSelect: closeOnSelect,
                      onSectionChanged: onSectionChanged,
                    ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const _SidebarStorageStatus(),
        ],
      ),
    );
  }
}

/// 侧栏品牌卡：状态点 + 等宽副标，底部 1px 分割线。
class _AdminSideHeader extends ConsumerWidget {
  const _AdminSideHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final phase = ref.watch(realtimePhaseProvider).asData?.value;
    final (dotColor, pulsing) = switch (phase) {
      RealtimePhase.healthy ||
      RealtimePhase.subscribed ||
      RealtimePhase.catchingUp => (AdminColors.of(context).success, true),
      RealtimePhase.connecting ||
      RealtimePhase.reconnecting => (AdminColors.of(context).warning, false),
      RealtimePhase.degraded => (scheme.error, false),
      RealtimePhase.signedOut || null => (scheme.onSurfaceVariant, false),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const BrandLogo.sidebar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context).adminShellTitle,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusDot(color: dotColor, pulsing: pulsing),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'ADMIN CONSOLE',
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    letterSpacing: 2,
                    color: scheme.onSurfaceVariant,
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

/// 状态指示灯：规范唯一允许的正圆元素。
///
/// 心跳脉冲为克制动效：仅持续约 5 秒（3 个周期）后保持常亮，
/// 避免长驻动画干扰焦点与自动化校验。
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, this.pulsing = false});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _pulseStopTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.pulsing) {
      _controller.repeat(reverse: true);
      _pulseStopTimer = Timer(const Duration(seconds: 5), () {
        _controller.stop();
        _controller.value = 1;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing == oldWidget.pulsing) {
      return;
    }
    // 最常见路径：connecting(不闪)→healthy(脉冲)。不重启控制器会让
    // FadeTransition 钉死在 0.35 透明度，在线灯反而最暗。
    _pulseStopTimer?.cancel();
    _pulseStopTimer = null;
    if (widget.pulsing) {
      _controller
        ..value = 0
        ..repeat(reverse: true);
      _pulseStopTimer = Timer(const Duration(seconds: 5), () {
        _controller.stop();
        _controller.value = 1;
      });
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _pulseStopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulsing) {
      return dot;
    }
    return FadeTransition(
      opacity: Tween(
        begin: 0.35,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: dot,
    );
  }
}

/// 分组标题：本地化组名 + 等宽英文代码，10px mono 小标。
class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.label, required this.code});

  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '$label ($code)',
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelSmall,
          letterSpacing: 1.2,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
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

/// 56px 工位顶栏：PORTAL 入口、面包屑标题、在线徽章、32px 搜索槽
/// 与系统级辅助控件（Aa / 通知 / 头像）。
///
/// 页面级控件一律下沉各分区工作区，严禁出现在全局顶栏。
class _AdminTopBar extends ConsumerWidget {
  const _AdminTopBar({required this.section, required this.isWide});

  final AdminSection section;
  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return WorkbenchTopBar(
      surfaceColor: scheme.surface,
      borderColor: scheme.outlineVariant,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 8),
        child: Row(
          children: [
            if (isWide) ...[
              WorkstationPortalLink(onTap: () => _backToPortal(context)),
              const SizedBox(width: 12),
              Container(width: 1, height: 16, color: scheme.outlineVariant),
              const SizedBox(width: 12),
            ] else
              IconButton(
                onPressed: () => _backToPortal(context),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: l10n.profileBackTooltip,
              ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      isWide
                          ? 'OmniNest Admin / ${_sectionTitle(l10n, section)}'
                          : _sectionTitle(l10n, section),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.titleSmall,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (isWide) ...[
                    const SizedBox(width: 10),
                    const _AdminOnlineBadge(),
                  ],
                ],
              ),
            ),
            if (isWide) ...[
              const _AdminSearchSlot(),
              const SizedBox(width: 10),
              const FontScaleControl(size: 20),
              const SizedBox(width: 8),
              const NotificationIcon(size: 20),
              const SizedBox(width: 8),
              const UserAvatarMenu(),
            ] else ...[
              IconButton(
                onPressed: () => _showMobileSearch(context, ref),
                icon: const Icon(Icons.search_rounded),
                tooltip: l10n.adminSearchHint,
              ),
              IconButton(
                onPressed: () => _showMobileSections(context),
                icon: const Icon(Icons.menu_rounded),
                tooltip: l10n.adminOpenMenu,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showMobileSearch(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await showWorkstationDialog<void>(
      context: context,
      builder:
          (dialogContext) => WorkstationDialogFrame(
            title: l10n.adminSearchHint,
            width: 460,
            body: const _AdminSearchField(autofocus: true),
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
      backgroundColor: Colors.transparent,
      builder: (context) => _MobileAdminSectionSheet(selected: section),
    );
  }
}

/// 在线状态徽章：surface-2 底 + 1px 细线 + 实时相位驱动的状态点。
class _AdminOnlineBadge extends ConsumerWidget {
  const _AdminOnlineBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final phase = ref.watch(realtimePhaseProvider).asData?.value;
    final (dotColor, pulsing) = switch (phase) {
      RealtimePhase.healthy ||
      RealtimePhase.subscribed ||
      RealtimePhase.catchingUp => (AdminColors.of(context).success, true),
      RealtimePhase.connecting ||
      RealtimePhase.reconnecting => (AdminColors.of(context).warning, false),
      RealtimePhase.degraded => (scheme.error, false),
      RealtimePhase.signedOut || null => (scheme.onSurfaceVariant, false),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant),
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
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏 32px 搜索槽：凹入槽体，Ctrl/Cmd+F 快捷键帽以 suffixIcon 呈现在
/// 框内（等宽 mono、点击聚焦输入框），不再悬挂在框外破坏 32px 高度。
class _AdminSearchSlot extends StatelessWidget {
  const _AdminSearchSlot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 288, height: 32, child: _AdminSearchField());
  }
}

/// 自持 Consumer 的搜索框：移动端会被放进独立对话框路由子树，
/// 不复用顶栏 WidgetRef，避免跨子树 ref 生命周期违规。
class _AdminSearchField extends ConsumerStatefulWidget {
  const _AdminSearchField({this.autofocus = false});

  final bool autofocus;

  @override
  ConsumerState<_AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends ConsumerState<_AdminSearchField>
    with RouteTopAware {
  final FocusNode _focusNode = FocusNode();
  late final TopBarSearchFocusHandle _searchFocusHandle;

  @override
  void initState() {
    super.initState();
    _searchFocusHandle = TopBarSearchFocusRegistry.instance.register(
      TopBarSearchFocusEntry(
        focus: _focusNode.requestFocus,
        isActive: () => isRouteTop,
      ),
    );
  }

  @override
  void dispose() {
    _searchFocusHandle.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onChanged:
          (query) => ref.read(adminSearchProvider.notifier).updateQuery(query),
      decoration: workstationInputDecoration(
        context,
        hintText: AppLocalizations.of(context).adminSearchHint,
      ).copyWith(
        // 快捷键帽移入框内：等宽 mono 徽标，点击聚焦输入框。
        suffixIcon: Tooltip(
          message: AppLocalizations.of(context).adminSearchHint,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _focusNode.requestFocus(),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  topBarSearchKeycapLabel,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        // suffix 盒与 32px 槽同高：键帽文字垂直居中的关键
        //（minHeight:0 会让 suffix 内容贴顶，正文随之上浮）。
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 32),
        suffixStyle: const TextStyle(),
      ),
    );
  }
}

/// 移动端分区抽屉：直角纯平列表，按权限过滤分组。
class _MobileAdminSectionSheet extends ConsumerWidget {
  const _MobileAdminSectionSheet({required this.selected});

  final AdminSection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>{};
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (final entry
                  in AdminSection.visibleGrouped(permissions).entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                  child: Text(
                    '${_sectionGroupLabel(l10n, entry.key)} (${_sectionGroupCode(entry.key)})',
                    style: TextStyle(
                      fontFamily: AppTypography.monoFamily,
                      fontFamilyFallback: AppTypography.monoFamilyFallback,
                      fontSize: AppTypography.labelSmall,
                      letterSpacing: 1.2,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final item in entry.value)
                  ListTile(
                    minTileHeight: 48,
                    leading: Icon(
                      _iconFor(item),
                      color:
                          item == selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      _sectionLabel(l10n, item),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight:
                            item == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                      ),
                    ),
                    selected: item == selected,
                    selectedTileColor: scheme.surfaceContainerHighest,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
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
      ),
    );
  }
}
