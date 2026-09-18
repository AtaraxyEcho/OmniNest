import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/pages/admin_analytics_page.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/pages/admin_overview_page.dart';
import 'package:omninest/features/admin/presentation/pages/admin_users_page.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_shell.dart';
import 'package:omninest/core/errors/error_message.dart';

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({required this.section, super.key});

  final AdminSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions =
        ref.watch(authSessionProvider).asData?.value.user?.permissions ??
        const <String>{};
    if (!section.isVisibleTo(permissions)) {
      return AdminShell(
        section: section,
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
    return AdminShell(section: section, child: _AdminSectionBody(section));
  }
}

class _AdminSectionBody extends ConsumerWidget {
  const _AdminSectionBody(this.section);

  final AdminSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (section) {
      AdminSection.overview => _SummaryStateBuilder(
        builder: (summary) => AdminOverviewPage(summary: summary),
      ),
      AdminSection.analytics => _AsyncStateBuilder<AdminAnalytics>(
        state: ref.watch(adminAnalyticsProvider(7)),
        onRetry: () => ref.invalidate(adminAnalyticsProvider(7)),
        builder: (analytics) => AdminAnalyticsPage(analytics: analytics),
      ),
      AdminSection.users => _UserStateBuilder(
        builder: (state) => AdminUsersPage(state: state),
      ),
      AdminSection.monitoring => _AsyncStateBuilder<AdminMonitoringView>(
        state: ref.watch(adminMonitoringProvider),
        onRetry: () => ref.invalidate(adminMonitoringProvider),
        builder: (view) => AdminMonitoringPage(view: view),
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
