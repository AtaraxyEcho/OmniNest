part of 'admin_shell.dart';

class _AdminNavItem extends StatefulWidget {
  const _AdminNavItem({
    required this.section,
    required this.selected,
    required this.closeOnSelect,
  });

  final AdminSection section;
  final bool selected;
  final bool closeOnSelect;

  @override
  State<_AdminNavItem> createState() => _AdminNavItemState();
}

class _AdminNavItemState extends State<_AdminNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final adminColors = context.adminColors;
    final selected = widget.selected;
    final foreground =
        selected
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : adminColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            final router = GoRouter.of(context);
            if (widget.closeOnSelect) {
              Navigator.of(context).pop();
            }
            router.go(widget.section.location);
          },
          child: AnimatedContainer(
            duration: MotionToken.fast,
            curve: MotionToken.curve,
            height: 40,
            decoration: BoxDecoration(
              color:
                  selected
                      ? adminColors.primaryContainer.withValues(alpha: 0.88)
                      : _hovered
                      ? adminColors.onSurfaceVariant.withValues(alpha: 0.08)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    selected
                        ? adminColors.primary.withValues(alpha: 0.34)
                        : _hovered
                        ? adminColors.outlineVariant.withValues(alpha: 0.36)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(_iconFor(widget.section), size: 18, color: foreground),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _sectionLabel(AppLocalizations.of(context), widget.section),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: AppTypography.bodyLarge,
                      height: 20 / 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarStorageStatus extends ConsumerWidget {
  const _SidebarStorageStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.adminColors;
    final l10n = AppLocalizations.of(context);
    // 与概览页共用同一 summary provider，避免重复请求。
    final storage =
        ref.watch(adminConsoleControllerProvider).asData?.value.storage;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 18, color: c.onSurface),
                const SizedBox(width: 8),
                Text(
                  l10n.adminStorageOverview,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              storage == null
                  ? '—'
                  : l10n.adminStorageUsed(formatFileSize(storage.usedBytes)),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: c.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              storage == null
                  ? '—'
                  : l10n.adminStorageFileCount(storage.fileCount),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(AdminSection section) {
  return switch (section) {
    AdminSection.overview => Icons.dashboard_customize_outlined,
    AdminSection.analytics => Icons.bar_chart_rounded,
    AdminSection.monitoring => Icons.monitor_heart_outlined,
    AdminSection.logs => Icons.receipt_long_outlined,
    AdminSection.tasks => Icons.pending_actions_outlined,
    AdminSection.sessions => Icons.devices_rounded,
    AdminSection.users => Icons.group_outlined,
    AdminSection.roles => Icons.verified_user_outlined,
    AdminSection.config => Icons.tune_rounded,
    AdminSection.storage => Icons.cloud_queue_rounded,
    AdminSection.externalStorage => Icons.add_to_drive_outlined,
  };
}

String _sectionLabel(AppLocalizations l10n, AdminSection section) {
  return switch (section) {
    AdminSection.overview => l10n.adminNavOverview,
    AdminSection.analytics => l10n.adminNavAnalytics,
    AdminSection.monitoring => l10n.adminNavMonitoring,
    AdminSection.logs => l10n.adminNavLogs,
    AdminSection.tasks => l10n.adminNavTasks,
    AdminSection.sessions => l10n.adminNavSessions,
    AdminSection.users => l10n.adminNavUsers,
    AdminSection.roles => l10n.adminNavRoles,
    AdminSection.config => l10n.adminNavConfig,
    AdminSection.storage => l10n.adminNavStorage,
    AdminSection.externalStorage => l10n.adminNavExternalStorage,
  };
}

String _sectionTitle(AppLocalizations l10n, AdminSection section) {
  return switch (section) {
    AdminSection.overview => l10n.adminOverviewTitle,
    AdminSection.analytics => l10n.adminAnalyticsTitle,
    AdminSection.monitoring => l10n.adminMonitoringTitle,
    AdminSection.logs => l10n.adminLogsTitle,
    AdminSection.tasks => l10n.adminTasksTitle,
    AdminSection.sessions => l10n.adminSessionsTitle,
    AdminSection.users => l10n.adminUsersTitle,
    AdminSection.roles => l10n.adminRolesTitle,
    AdminSection.config => l10n.adminConfigTitle,
    AdminSection.storage => l10n.adminStorageTitle,
    AdminSection.externalStorage => l10n.adminExternalStorageTitle,
  };
}

String _sectionGroupLabel(AppLocalizations l10n, AdminSectionGroup group) {
  return switch (group) {
    AdminSectionGroup.overview => l10n.adminGroupOverview,
    AdminSectionGroup.operations => l10n.adminGroupOperations,
    AdminSectionGroup.identity => l10n.adminGroupIdentity,
    AdminSectionGroup.configuration => l10n.adminGroupConfiguration,
    AdminSectionGroup.storage => l10n.adminGroupStorage,
  };
}

int _adminDockIndex(AdminSection section) {
  return switch (section) {
    AdminSection.overview || AdminSection.analytics => 0,
    AdminSection.users || AdminSection.roles => 1,
    AdminSection.tasks || AdminSection.sessions || AdminSection.monitoring => 2,
    AdminSection.logs => 3,
    AdminSection.config ||
    AdminSection.storage ||
    AdminSection.externalStorage => 4,
  };
}

AdminSection? _adminDockSection(int index) {
  return switch (index) {
    0 => AdminSection.overview,
    1 => AdminSection.users,
    2 => AdminSection.tasks,
    3 => AdminSection.logs,
    4 => AdminSection.config,
    _ => null,
  };
}
