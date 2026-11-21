import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_system_logs.dart';
import 'package:omninest/features/admin/presentation/pages/admin_overview_page.dart';
import 'package:omninest/features/admin/presentation/pages/admin_users_page.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

/// 样例 `Admin.tsx` 的 5 分区容器：一张卡里的内嵌页签承载原 10 个分区。
///
/// Desktop Identity 与 Storage 的相关卡片纵向组合在一页；Ops 保留 Tasks /
/// Logs / Sessions / Maintenance 页签（Dead letters 与 Sign-in audit 已内嵌
/// 在 Tasks / Logs 页内）。移动端继续使用原页签；导航分区仍由 URL 驱动。
class AdminGroupPage extends StatefulWidget {
  const AdminGroupPage({
    required this.group,
    required this.initialSection,
    required this.onTabChanged,
    super.key,
  });

  final AdminSectionGroup group;
  final AdminSection initialSection;

  /// 页签切换同步到 URL，让外壳的滚动策略与当前页签保持一致。
  final ValueChanged<AdminSection> onTabChanged;

  @override
  State<AdminGroupPage> createState() => _AdminGroupPageState();
}

class _AdminGroupPageState extends State<AdminGroupPage> {
  late AdminSection _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialSection;
  }

  @override
  void didUpdateWidget(covariant AdminGroupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.group != widget.group) {
      _tab = widget.initialSection;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 页签不做权限过滤：分区入口与页面数据仍由外壳权限判断和后端
    // @PreAuthorize 把关，这里隐藏页签只会让深链落到一个空容器。
    final tabs = AdminSection.grouped[widget.group]!;
    final active = tabs.contains(_tab) ? _tab : tabs.first;
    final desktop = DesktopShellScope.isHosted(context);
    final stackedDesktopGroup =
        desktop &&
        (widget.group == AdminSectionGroup.identity ||
            widget.group == AdminSectionGroup.storage);
    if (desktop &&
        widget.group == AdminSectionGroup.operations &&
        active != AdminSection.maintenance) {
      return _DesktopOperationsHub(
        initialSection: active,
        onTabChanged: (section) {
          setState(() => _tab = section);
          widget.onTabChanged(section);
        },
        onMaintenance: () {
          setState(() => _tab = AdminSection.maintenance);
          widget.onTabChanged(AdminSection.maintenance);
        },
      );
    }
    final seg =
        tabs.length > 1 && !stackedDesktopGroup
            ? Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _groupTabBar(context, l10n, tabs, active),
            )
            : const SizedBox.shrink();
    final content =
        stackedDesktopGroup
            ? _StackedAdminGroupContent(group: widget.group)
            : AdminSectionContent(section: active);
    // 外壳已按 URL 段决定是否套滚动；带 TabBarView 的页签必须有界高度。
    final fills = active == AdminSection.logs || active == AdminSection.tasks;
    if (fills) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [seg, Expanded(child: content)],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [seg, content],
    );
  }

  /// 样例 `.seg` 的分段条：选中项实色，避免隐式动画在工位/移动测试里留下
  /// 未结束的动画计时器；同时不依赖桌面皮肤，三种外壳形态都可用。
  Widget _groupTabBar(
    BuildContext context,
    AppLocalizations l10n,
    List<AdminSection> tabs,
    AdminSection active,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final section in tabs)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (section == active) return;
                setState(() => _tab = section);
                widget.onTabChanged(section);
              },
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color:
                      section == active
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: section == active ? scheme.primary : scheme.outline,
                  ),
                ),
                child: Center(
                  child: Text(
                    _tabLabel(l10n, section),
                    style: TextStyle(
                      fontSize: AppTypography.labelMedium,
                      fontWeight:
                          section == active ? FontWeight.w600 : FontWeight.w500,
                      color:
                          section == active
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _DesktopOperationsTab {
  tasks,
  deadLetters,
  signInAudit,
  sessions,
  systemLogs,
}

class _DesktopOperationsHub extends ConsumerStatefulWidget {
  const _DesktopOperationsHub({
    required this.initialSection,
    required this.onTabChanged,
    required this.onMaintenance,
  });

  final AdminSection initialSection;
  final ValueChanged<AdminSection> onTabChanged;
  final VoidCallback onMaintenance;

  @override
  ConsumerState<_DesktopOperationsHub> createState() =>
      _DesktopOperationsHubState();
}

class _DesktopOperationsHubState extends ConsumerState<_DesktopOperationsHub> {
  late _DesktopOperationsTab _tab = _tabForSection(widget.initialSection);

  @override
  void didUpdateWidget(covariant _DesktopOperationsHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _tab = _tabForSection(widget.initialSection);
    }
  }

  _DesktopOperationsTab _tabForSection(AdminSection section) =>
      switch (section) {
        AdminSection.sessions => _DesktopOperationsTab.sessions,
        AdminSection.logs => _DesktopOperationsTab.signInAudit,
        _ => _DesktopOperationsTab.tasks,
      };

  AdminSection _sectionForTab(_DesktopOperationsTab tab) => switch (tab) {
    _DesktopOperationsTab.tasks ||
    _DesktopOperationsTab.deadLetters => AdminSection.tasks,
    _DesktopOperationsTab.signInAudit ||
    _DesktopOperationsTab.systemLogs => AdminSection.logs,
    _DesktopOperationsTab.sessions => AdminSection.sessions,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final available = <_DesktopOperationsTab>[
      if (AdminSection.tasks.isVisibleTo(permissions))
        _DesktopOperationsTab.tasks,
      if (AdminSection.tasks.isVisibleTo(permissions))
        _DesktopOperationsTab.deadLetters,
      if (AdminSection.logs.isVisibleTo(permissions))
        _DesktopOperationsTab.signInAudit,
      if (AdminSection.sessions.isVisibleTo(permissions))
        _DesktopOperationsTab.sessions,
      if (AdminSection.logs.isVisibleTo(permissions))
        _DesktopOperationsTab.systemLogs,
    ];
    if (available.isEmpty) return const SizedBox.shrink();
    final tabs = available;
    final selected = tabs.contains(_tab) ? _tab : tabs.first;
    final body = switch (selected) {
      _DesktopOperationsTab.tasks => const AdminTasksPage(
        initialTab: 0,
        hideDesktopTabSelector: true,
        embedded: true,
      ),
      _DesktopOperationsTab.deadLetters => const AdminTasksPage(
        initialTab: 1,
        hideDesktopTabSelector: true,
        embedded: true,
      ),
      _DesktopOperationsTab.signInAudit => const AdminLogsPage(
        initialTab: 1,
        hideDesktopTabSelector: true,
        embedded: true,
      ),
      _DesktopOperationsTab.sessions => const AdminSessionsPage(embedded: true),
      _DesktopOperationsTab.systemLogs => const AdminSystemLogsPage(),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopSeg<_DesktopOperationsTab>(
              options: tabs,
              value: selected,
              small: true,
              labelOf:
                  (tab) => switch (tab) {
                    _DesktopOperationsTab.tasks => l10n.adminTaskList,
                    _DesktopOperationsTab.deadLetters => l10n.adminDlq,
                    _DesktopOperationsTab.signInAudit => l10n.adminTabLoginLog,
                    _DesktopOperationsTab.sessions => l10n.adminNavSessions,
                    _DesktopOperationsTab.systemLogs => l10n.adminSystemLogs,
                  },
              onChanged: (tab) {
                setState(() => _tab = tab);
                widget.onTabChanged(_sectionForTab(tab));
              },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child:
                selected == _DesktopOperationsTab.systemLogs
                    ? body
                    : SingleChildScrollView(child: body),
          ),
          if (AdminSection.maintenance.isVisibleTo(permissions)) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: DesktopLink(
                label: l10n.adminNavMaintenance,
                onPressed: widget.onMaintenance,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 设计稿把 Identity 与 Storage 内容放在同一页面纵向展示。
/// 依据当前权限拼装可读分区，避免预取用户无权读取的管理端接口。
class _StackedAdminGroupContent extends ConsumerWidget {
  const _StackedAdminGroupContent({required this.group});

  final AdminSectionGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final sections = AdminSection.visibleInGroup(group, permissions);
    if (group == AdminSectionGroup.storage &&
        DesktopShellScope.isHosted(context)) {
      return const AdminDesktopStorageDashboard();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: 20),
          AdminSectionContent(section: sections[index]),
        ],
      ],
    );
  }
}

String _tabLabel(AppLocalizations l10n, AdminSection section) {
  return switch (section) {
    AdminSection.overview => l10n.adminNavOverview,
    AdminSection.logs => l10n.adminNavLogs,
    AdminSection.tasks => l10n.adminNavTasks,
    AdminSection.sessions => l10n.adminNavSessions,
    AdminSection.maintenance => l10n.adminNavMaintenance,
    AdminSection.users => l10n.adminNavUsers,
    AdminSection.roles => l10n.adminNavRoles,
    AdminSection.mediaLibrary => l10n.adminGroupLibrary,
    AdminSection.config => l10n.adminNavConfig,
    AdminSection.storage => l10n.adminNavStorage,
    AdminSection.externalStorage => l10n.adminNavExternalStorage,
  };
}

/// 单个页签的内容。原 `_AdminSectionBody` 的 10 路 switch 原样保留。
class AdminSectionContent extends ConsumerWidget {
  const AdminSectionContent({required this.section, super.key});

  final AdminSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (section) {
      AdminSection.overview => _SummaryStateBuilder(
        builder: (summary) => AdminOverviewPage(summary: summary),
      ),
      AdminSection.users => _UserStateBuilder(
        builder: (state) => AdminUsersPage(state: state),
      ),
      AdminSection.logs => const AdminLogsPage(),
      AdminSection.tasks => const AdminTasksPage(),
      AdminSection.roles => _AsyncStateBuilder<AdminRoleManagementView>(
        state: ref.watch(adminRolesProvider),
        onRetry: () => ref.invalidate(adminRolesProvider),
        builder: (view) => AdminRolesPage(view: view),
      ),
      AdminSection.config => _AsyncStateBuilder<AdminConfigManagementView>(
        state: ref.watch(adminConfigsProvider),
        onRetry: () => ref.invalidate(adminConfigsProvider),
        builder: (view) => AdminConfigPage(view: view),
      ),
      AdminSection.storage => _AsyncStateBuilder<AdminStorageManagementView>(
        state: ref.watch(adminStorageProvider),
        onRetry: () => ref.invalidate(adminStorageProvider),
        builder: (view) => AdminStoragePage(view: view),
      ),
      AdminSection.externalStorage =>
        _AsyncStateBuilder<AdminExternalStorageView>(
          state: ref.watch(adminExternalStorageProvider),
          onRetry: () => ref.invalidate(adminExternalStorageProvider),
          builder: (view) => AdminExternalStoragePage(view: view),
        ),
      AdminSection.mediaLibrary => const AdminMediaLibraryPage(),
      AdminSection.sessions => const AdminSessionsPage(),
      AdminSection.maintenance => const AdminMaintenancePage(),
    };
  }
}

class _SummaryStateBuilder extends ConsumerWidget {
  const _SummaryStateBuilder({required this.builder});

  final Widget Function(AdminConsoleSummary summary) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(adminConsoleControllerProvider);
    return summaryState.when(
      data: builder,
      error:
          (error, stackTrace) => AppErrorView(
            message: errorReason(error, AppLocalizations.of(context)),
            onRetry: () => ref.invalidate(adminConsoleControllerProvider),
          ),
      loading:
          () =>
              DesktopShellScope.isHosted(context)
                  ? const _AdminOverviewLoadingSkeleton()
                  : const AppLoading(),
    );
  }
}

class _UserStateBuilder extends ConsumerWidget {
  const _UserStateBuilder({required this.builder});

  final Widget Function(AdminUserState state) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(adminUserControllerProvider);
    return usersState.when(
      data: builder,
      error:
          (error, stackTrace) => AppErrorView(
            message: errorReason(error, AppLocalizations.of(context)),
            onRetry: () => ref.invalidate(adminUserControllerProvider),
          ),
      loading:
          () =>
              DesktopShellScope.isHosted(context)
                  ? const DesktopSkeletonRows(count: 8)
                  : const AppLoading(),
    );
  }
}

class _AsyncStateBuilder<T> extends StatelessWidget {
  const _AsyncStateBuilder({
    required this.state,
    required this.builder,
    required this.onRetry,
  });

  final AsyncValue<T> state;
  final Widget Function(T value) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return state.when(
      data: builder,
      error:
          (error, stackTrace) => AppErrorView(
            message: errorReason(error, AppLocalizations.of(context)),
            onRetry: onRetry,
          ),
      loading:
          () =>
              DesktopShellScope.isHosted(context)
                  ? const AdminListSkeleton(rows: 6)
                  : const AppLoading(),
    );
  }
}

class _AdminOverviewLoadingSkeleton extends StatelessWidget {
  const _AdminOverviewLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    Widget panel({required double height, required Widget child}) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: SizedBox(height: height, child: child),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 960 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    width: width,
                    child: panel(
                      height: 88,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DesktopSkeletonBox(width: 82, height: 10, index: i),
                          DesktopSkeletonBox(
                            width: 56,
                            height: 22,
                            index: i + 1,
                          ),
                          DesktopSkeletonBox(
                            width: 112,
                            height: 9,
                            index: i + 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        panel(
          height: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DesktopSkeletonBox(width: 138, height: 12, index: 5),
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 14; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: DesktopSkeletonBox(
                            height: 16 + ((i * 29) % 74),
                            radius: 4,
                            index: i + 6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          height: 74,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const DesktopSkeletonBox(width: 124, height: 11, index: 20),
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    DesktopSkeletonBox(width: 88, height: 22, index: i + 21),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          height: 74,
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DesktopSkeletonBox(width: 150, height: 12, index: 26),
                    SizedBox(height: 10),
                    DesktopSkeletonBox(width: 230, height: 9, index: 27),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              DesktopSkeletonBox(width: 112, height: 34, radius: 17, index: 28),
            ],
          ),
        ),
      ],
    );
  }
}
