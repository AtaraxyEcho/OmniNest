import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/pages/admin_overview_page.dart';
import 'package:omninest/features/admin/presentation/pages/admin_users_page.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_shell.dart';
import 'package:omninest/core/errors/error_message.dart';

/// 管理控制台主页面。
///
/// 深链分区：`/admin/:section`（section 对应 [AdminSection.pathSegment]）。
/// 侧栏切换分区时同步 URL；外部导航为 push/pop。
class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({this.initialSectionSegment, super.key});

  /// 路由路径段，如 `storage`、`monitoring`；空或非法时回落 overview。
  final String? initialSectionSegment;

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> {
  late AdminSection _section;

  @override
  void initState() {
    super.initState();
    _section = AdminSection.fromPathSegment(widget.initialSectionSegment);
    // 进入即查由页面挂载统一承担：失效目标分区常驻缓存；未创建的
    // provider 失效为空操作，挂载后仅取数一次。
    _invalidateSectionAfterFrame(_section);
  }

  @override
  void didUpdateWidget(covariant AdminDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSectionSegment != widget.initialSectionSegment) {
      final next = AdminSection.fromPathSegment(widget.initialSectionSegment);
      if (next != _section) {
        setState(() => _section = next);
        _invalidateSectionAfterFrame(next);
      }
    }
  }

  /// 失效必须推迟到本帧之后：initState/didUpdateWidget 都处于构建期，
  /// 此时弄脏侧栏也在监听的常驻 provider，兄弟节点稍后 watch 该 provider
  /// 会同步刷新并回灌侧栏，触发 setState() during build。
  void _invalidateSectionAfterFrame(AdminSection section) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(adminSectionRefreshProvider).invalidate(section);
    });
  }

  void _onSectionChanged(AdminSection section) {
    if (section == _section) {
      return;
    }
    final target = section.location;
    final uri = GoRouterState.of(context).uri.toString();
    if (uri == target) {
      // URL 已与目标一致（深链回绕）：本地切分区并失效缓存。
      setState(() => _section = section);
      ref.read(adminSectionRefreshProvider).invalidate(section);
      return;
    }
    // 分区切换与缓存失效统一由路由驱动（initState/didUpdateWidget）。
    // 首次点击跨 /admin → /admin/:section 路由会整页替换：若此处先
    // setState，退出中的旧页与进入的新页会各挂载一次目标分区，
    // autoDispose 分区（tasks/logs/sessions 及存储子列表）被创建
    // 两次，形成首次点击的二次加载。
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>{};
    if (!_section.isVisibleTo(permissions)) {
      return AdminShell(
        section: _section,
        onSectionChanged: _onSectionChanged,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppLocalizations.of(context).adminSectionForbidden,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return AdminShell(
      section: _section,
      onSectionChanged: _onSectionChanged,
      child: _AdminSectionBody(section: _section),
    );
  }
}

class _MonitoringSectionBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch 轮询器以在其挂载期间保活；分区卸载即停止轮询。
    ref.watch(adminMonitoringPollerProvider);
    return _AsyncStateBuilder<AdminMonitoringView>(
      state: ref.watch(adminMonitoringProvider),
      onRetry: () => ref.invalidate(adminMonitoringProvider),
      builder: (view) => AdminMonitoringPage(view: view),
    );
  }
}

class _AdminSectionBody extends ConsumerWidget {
  const _AdminSectionBody({required this.section});

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
      AdminSection.monitoring => _MonitoringSectionBody(),
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
      AdminSection.sessions => const AdminSessionsPage(),
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
            message: describeUserFacingError(error).message,
            onRetry: () => ref.invalidate(adminConsoleControllerProvider),
          ),
      loading: () => const AppLoading(),
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
            message: describeUserFacingError(error).message,
            onRetry: () => ref.invalidate(adminUserControllerProvider),
          ),
      loading: () => const AppLoading(),
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
      // 分区切换失效与监控轮询走 invalidate（isRefreshing），默认
      // skipLoadingOnRefresh 已保留已渲染内容不闪 loading；也不开启
      // 「reload 期间保留旧值」——isReloading 仅在换号世代变化时出现，
      // 此时必须显示 loading 而非上一账号数据。
      data: builder,
      error:
          (error, stackTrace) => AppErrorView(
            message: describeUserFacingError(error).message,
            onRetry: onRetry,
          ),
      loading: () => const AppLoading(),
    );
  }
}
