part of 'admin_shell.dart';

/// 侧栏导航项：纯平直角，激活态靠背景与 1px 边框表达，禁左侧线段。
class _AdminNavItem extends StatefulWidget {
  const _AdminNavItem({
    required this.section,
    required this.selected,
    required this.closeOnSelect,
    required this.onSectionChanged,
  });

  final AdminSection section;
  final bool selected;
  final bool closeOnSelect;
  final ValueChanged<AdminSection> onSectionChanged;

  @override
  State<_AdminNavItem> createState() => _AdminNavItemState();
}

class _AdminNavItemState extends State<_AdminNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground =
        selected || _hovering ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (widget.closeOnSelect) {
              Navigator.of(context).pop();
            }
            if (!widget.selected) {
              widget.onSectionChanged(widget.section);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  selected
                      ? scheme.surfaceContainerHighest
                      : _hovering
                      ? scheme.surfaceContainer
                      : Colors.transparent,
              border: Border.all(
                color: selected ? scheme.outlineVariant : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(_iconFor(widget.section), size: 16, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _sectionLabel(AppLocalizations.of(context), widget.section),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      height: 18 / AppTypography.bodyMedium,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
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

/// 底部固定存储微卡：严格吸附侧栏最底部（shrink-0），
/// 标题 + 已用数值 + 文件数说明，1px 上边线，纯平直角。
class _SidebarStorageStatus extends ConsumerWidget {
  const _SidebarStorageStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    // 与概览页共用同一 summary provider，避免重复请求。
    final storage =
        ref.watch(adminConsoleControllerProvider).asData?.value.storage;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.adminStorageOverview,
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelSmall,
                  letterSpacing: 1.2,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                storage == null ? '—' : formatFileSize(storage.usedBytes),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            storage == null
                ? '—'
                : l10n.adminStorageFileCount(storage.fileCount),
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelMicro,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(AdminSection section) {
  return switch (section) {
    AdminSection.overview => Icons.dashboard_customize_outlined,
    AdminSection.logs => Icons.receipt_long_outlined,
    AdminSection.tasks => Icons.task_alt_outlined,
    AdminSection.sessions => Icons.devices_rounded,
    AdminSection.users => Icons.badge_outlined,
    AdminSection.roles => Icons.verified_user_outlined,
    AdminSection.config => Icons.tune_outlined,
    AdminSection.storage => Icons.dns_outlined,
    AdminSection.externalStorage => Icons.cloud_sync_outlined,
  };
}

String _sectionLabel(AppLocalizations l10n, AdminSection section) {
  return switch (section) {
    AdminSection.overview => l10n.adminNavOverview,
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

String _sectionGroupCode(AdminSectionGroup group) {
  return switch (group) {
    AdminSectionGroup.overview => 'OVERVIEW',
    AdminSectionGroup.operations => 'OPERATIONS',
    AdminSectionGroup.identity => 'IDENTITY',
    AdminSectionGroup.configuration => 'CONFIG',
    AdminSectionGroup.storage => 'STORAGE',
  };
}

int _adminDockIndex(AdminSection section) {
  return switch (section) {
    AdminSection.overview => 0,
    AdminSection.users || AdminSection.roles => 1,
    AdminSection.tasks || AdminSection.sessions => 2,
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
