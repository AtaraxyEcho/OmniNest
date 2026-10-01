import 'dart:math';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

part 'admin_user_dialogs.dart';

/// 角色编码到本地化名称的映射，未知编码原样返回。
String adminRoleDisplayName(AppLocalizations l10n, String role) {
  return switch (role) {
    AdminRoles.superAdmin => l10n.adminRoleSuperAdmin,
    AdminRoles.admin => l10n.adminRoleAdmin,
    AdminRoles.member => l10n.adminRoleMember,
    AdminRoles.guest => l10n.adminRoleGuest,
    _ => role,
  };
}

/// 用户状态到本地化名称的映射，未知状态原样返回。
String adminUserStatusDisplayName(AppLocalizations l10n, String status) {
  return switch (status) {
    AdminUserStatus.active => l10n.adminUserStatusActive,
    AdminUserStatus.disabled => l10n.adminUserStatusDisabled,
    _ => status,
  };
}

/// 用户行头像：有图片时 26px 圆形裁切，加载失败或无图回退显示名首字块。
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.imageUrl, required this.fallbackText});

  final String? imageUrl;
  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        fallbackText.trim().isEmpty
            ? '?'
            : fallbackText.trim().characters.first;
    final fallback = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) {
      return fallback;
    }
    return ClipOval(
      child: Image.network(
        imageUrl!,
        width: 26,
        height: 26,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// 用户管理页 — 全局口径指标卡 + 服务端分页用户表。
///
/// 指标卡与角色 chips 的计数取控制台 summary（全库口径），不再使用
/// 当前页子集；搜索与角色筛选直传后端分页接口。
class AdminUsersPage extends ConsumerWidget {
  const AdminUsersPage({required this.state, super.key});

  final AdminUserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 顶栏全局搜索接入：转发给控制器（内部 300ms 防抖后回第一页）。
    ref.listenManual(adminSearchProvider, (previous, next) {
      ref.read(adminUserControllerProvider.notifier).setSearchTerm(next);
    });
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: l10n.adminUserManagement,
          subtitle: l10n.adminUserManagementSubtitle,
        ),
        const SizedBox(height: 24),
        const _UserMetricCards(),
        const SizedBox(height: 24),
        _UserManagementPanel(state: state),
      ],
    );
  }
}

/// 全局口径指标卡：用户总数与角色分布取控制台 summary 的 roleCounts。
class _UserMetricCards extends ConsumerWidget {
  const _UserMetricCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    // 侧栏存储卡与概览共用该 provider，此处 watch 不会产生额外请求。
    final users = ref.watch(adminConsoleControllerProvider).asData?.value.users;
    final roleCount = users?.roleCount ?? (String role) => 0;
    final total = users?.total;
    return AdminResponsiveMetricGrid(
      children: [
        AdminMetricCard(
          title: l10n.adminTotalUsers,
          value: total?.toString() ?? '—',
          detail: l10n.adminDatabaseAccounts,
          icon: Icons.badge_outlined,
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminActive,
              value: users?.active.toString() ?? '—',
            ),
            AdminMetricMiniStat(
              label: l10n.adminStatusDisabled,
              value: users?.disabled.toString() ?? '—',
            ),
          ],
        ),
        AdminMetricCard(
          title: l10n.adminSuperAdmin,
          value: roleCount(AdminRoles.superAdmin).toString(),
          detail: l10n.adminHighestPrivilege,
          icon: Icons.workspace_premium_outlined,
          supporting: [
            _MetricNoteChip(
              icon: Icons.lock_outline,
              label: l10n.adminSuperAdminDisableNote,
            ),
          ],
        ),
        AdminMetricCard(
          title: l10n.adminRoleAdmin,
          value: roleCount(AdminRoles.admin).toString(),
          detail: l10n.adminSystemMaintenance,
          icon: Icons.admin_panel_settings_outlined,
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminAssignableRoles,
              value: '${AdminRoles.manageableRoles.length}',
            ),
          ],
        ),
        AdminMetricCard(
          title: l10n.adminMemberGuest,
          value:
              '${roleCount(AdminRoles.member)} / ${roleCount(AdminRoles.guest)}',
          detail: l10n.adminBusinessAccess,
          icon: Icons.groups_2_outlined,
          accent: adminColors.success,
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminRoleMember,
              value: roleCount(AdminRoles.member).toString(),
            ),
            AdminMetricMiniStat(
              label: l10n.adminRoleGuest,
              value: roleCount(AdminRoles.guest).toString(),
            ),
          ],
        ),
      ],
    );
  }
}

/// 指标卡说明 chip：与 [AdminMetricMiniStat] 同几何的静态说明标签，
/// 用于超管卡“不可禁用”等提示，对应样板中数值下方的着色说明行。
class _MetricNoteChip extends StatelessWidget {
  const _MetricNoteChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.adminColors.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserManagementPanel extends ConsumerWidget {
  const _UserManagementPanel({required this.state});

  final AdminUserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(adminUserControllerProvider.notifier);
    final summary = ref.watch(adminConsoleControllerProvider).asData?.value;
    final roleCount = summary?.users.roleCount ?? (String role) => 0;
    return AdminInfoPanel(
      title: l10n.adminAccountList,
      subtitle: l10n.adminAccountListSubtitle,
      trailing: FilledButton.icon(
        onPressed:
            () => showWorkstationDialog(
              context: context,
              builder: (context) => const _CreateUserDialog(),
            ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.adminCreateUser),
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              selected: state.roleFilter == 'ALL',
              label: Text('${l10n.adminAll} (${summary?.users.total ?? 0})'),
              onSelected: (_) => controller.setRoleFilter('ALL'),
            ),
            for (final role in AdminRoles.allRoles)
              FilterChip(
                selected: state.roleFilter == role,
                label: Text(
                  '${adminRoleDisplayName(l10n, role)} (${roleCount(role)})',
                ),
                onSelected: (_) => controller.setRoleFilter(role),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (state.hasSelection) ...[
          _BatchActionBar(
            selectedCount: state.selectedIds.length,
            // 选中集混合两种状态时两个动作并存，各自只作用于对应状态的用户。
            hasActive: state.users
                .where((user) => state.selectedIds.contains(user.id))
                .any((user) => user.isActive),
            hasDisabled: state.users
                .where((user) => state.selectedIds.contains(user.id))
                .any((user) => !user.isActive),
            onBatchDisable:
                () => _batchUpdateUserStatus(
                  context,
                  ref,
                  state.users
                      .where(
                        (user) =>
                            state.selectedIds.contains(user.id) &&
                            user.isActive,
                      )
                      .toList(),
                  disabling: true,
                ),
            onBatchEnable:
                () => _batchUpdateUserStatus(
                  context,
                  ref,
                  state.users
                      .where(
                        (user) =>
                            state.selectedIds.contains(user.id) &&
                            !user.isActive,
                      )
                      .toList(),
                  disabling: false,
                ),
            onClear: controller.clearSelection,
          ),
          const SizedBox(height: 12),
        ],
        AdminDataTable(
          // 可排序列的 key 直接使用后端排序字段（白名单内的实体属性名）。
          columns: [
            AdminListColumn(
              key: 'username',
              label: l10n.adminUserColumn,
              flex: 2,
              sortable: true,
            ),
            AdminListColumn(
              key: 'email',
              label: l10n.adminEmail,
              flex: 2,
              sortable: true,
            ),
            AdminListColumn(key: 'roles', label: l10n.adminRole, flex: 1),
            AdminListColumn(
              key: 'createdAt',
              label: l10n.adminUserCreatedAtColumn,
              minWidth: 150,
              sortable: true,
            ),
            AdminListColumn(
              key: 'twoFactor',
              label: l10n.adminUserTwoFactorColumn,
              minWidth: 88,
            ),
            AdminListColumn(
              key: 'usedBytes',
              label: l10n.adminUserQuotaUsageColumn,
              minWidth: 132,
              numeric: true,
              sortable: true,
            ),
            AdminListColumn(
              key: 'status',
              label: l10n.adminStatusColumn,
              minWidth: 96,
              sortable: true,
            ),
          ],
          minTableWidth: 1240,
          actionColumnWidth: 168,
          showCheckboxes: true,
          isChecked:
              (index) => state.selectedIds.contains(state.users[index].id),
          isCheckDisabled: (index) => state.users[index].isSuperAdmin,
          checkDisabledTooltip:
              (index) =>
                  state.users[index].isSuperAdmin
                      ? l10n.adminUserProtectedTooltip
                      : null,
          onRowCheck:
              (index, value) =>
                  controller.toggleSelection(state.users[index].id),
          sort: AdminListSort(
            columnKey: state.sortField,
            ascending: state.sortAscending,
          ),
          onSort:
              (columnKey, ascending) =>
                  controller.setSort(columnKey, ascending),
          allChecked:
              state.users.any((u) => !u.isSuperAdmin) &&
              state.users
                  .where((u) => !u.isSuperAdmin)
                  .every((u) => state.selectedIds.contains(u.id)),
          someChecked: state.hasSelection,
          onCheckAll: (_) => controller.selectAllVisible(),
          rowCount: state.users.length,
          rowCellsBuilder:
              (context, index) => _buildUserCells(context, state.users[index]),
          actionsBuilder:
              (context, index) =>
                  _buildUserActions(context, ref, state.users[index]),
          emptyState: AdminListEmptyState(
            // 区分“系统内暂无用户”与“当前筛选无匹配”两种空态。
            message:
                state.query.isEmpty && state.roleFilter == 'ALL'
                    ? l10n.adminNoUsers
                    : l10n.adminNoMatch,
          ),
        ),
        WorkstationPaginationBar(
          currentPage: state.page,
          totalPages: max(state.totalPages, 1),
          totalElements: state.totalElements,
          rowsPerPage: state.pageSize,
          onPageChanged: controller.setPage,
          onRowsPerPageChanged: controller.setPageSize,
        ),
      ],
    );
  }

  List<Widget> _buildUserCells(BuildContext context, AdminUser user) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final scheme = Theme.of(context).colorScheme;
    return [
      Row(
        children: [
          _UserAvatar(imageUrl: user.avatarUrl, fallbackText: user.title),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminCellText(
                  user.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                AdminCellText(
                  '@${user.username}',
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      AdminCellText(
        user.email ?? l10n.adminNotSetEmail,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: adminColors.onSurfaceVariant),
      ),
      // 多角色只展示首枚徽标 + "+n" 计数（tooltip 罗列全部角色与权限数），
      // 避免 Wrap 换行把行高撑得参差不齐。
      Tooltip(
        message: _rolesTooltipMessage(l10n, user),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.roles.isNotEmpty)
              AdminStatusTag(
                label: adminRoleDisplayName(l10n, user.roles.first),
                tone: _roleTone(user.roles.first),
              ),
            if (user.roles.length > 1) ...[
              const SizedBox(width: 4),
              Text(
                '+${user.roles.length - 1}',
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelSmall,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      AdminCellText(
        _formatCreatedAt(user.createdAt),
        tooltipMessage: user.createdAt,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          color: scheme.onSurfaceVariant,
        ),
      ),
      AdminStatusTag(
        label:
            user.twoFactorEnabled
                ? l10n.profileTwoFactorEnabled
                : l10n.profileTwoFactorDisabled,
        tone:
            user.twoFactorEnabled ? AdminTagTone.success : AdminTagTone.neutral,
      ),
      _QuotaUsageCell(user: user),
      AdminStatusTag(
        label: adminUserStatusDisplayName(l10n, user.status),
        tone: user.isActive ? AdminTagTone.success : AdminTagTone.error,
      ),
    ];
  }

  /// 创建时间紧凑展示：本地时区 yyyy-MM-dd HH:mm；空值占位、解析失败
  /// 回退原文（悬停 tooltip 展示完整 ISO 值）。
  String _formatCreatedAt(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// 角色列 tooltip：全部角色名 + 权限计数；两者皆空时回退占位符，
  /// 避免空文案触发 Tooltip 断言。
  String _rolesTooltipMessage(AppLocalizations l10n, AdminUser user) {
    final parts = [
      for (final role in user.roles) adminRoleDisplayName(l10n, role),
      if (user.permissions.isNotEmpty)
        l10n.adminUserPermissionsCount(user.permissions.length),
    ];
    return parts.isEmpty ? '-' : parts.join(' · ');
  }

  List<Widget> _buildUserActions(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
  ) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (user.isSuperAdmin) {
      return [
        Tooltip(
          message: l10n.adminUserProtectedTooltip,
          child: Text(
            l10n.adminUserProtected,
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    return [
      AdminRowIconAction(
        tooltip: l10n.adminRole,
        icon: Icons.manage_accounts_outlined,
        onTap:
            () => showWorkstationDialog(
              context: context,
              builder: (context) => _EditUserRolesDialog(user: user),
            ),
      ),
      AdminRowIconAction(
        tooltip: l10n.adminQuota,
        icon: Icons.storage_outlined,
        onTap:
            () => showWorkstationDialog(
              context: context,
              builder: (context) => _EditQuotaDialog(user: user),
            ),
      ),
      AdminRowIconAction(
        tooltip: user.isActive ? l10n.adminDisable : l10n.adminEnabled,
        icon: user.isActive ? Icons.block_outlined : Icons.check_circle_outline,
        onTap: () => _confirmToggleStatus(context, ref, user),
      ),
      AdminRowIconAction(
        tooltip: l10n.adminDeleteUser,
        icon: Icons.delete_outline,
        color: context.adminColors.error,
        onTap: () => _confirmDeleteUser(context, ref, user),
      ),
    ];
  }

  Future<void> _confirmToggleStatus(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
  ) async {
    final l10n = AppLocalizations.of(context);
    final disabling = user.isActive;
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title:
          disabling
              ? l10n.adminUserDisableConfirmTitle
              : l10n.adminUserEnableConfirmTitle,
      message:
          disabling
              ? l10n.adminUserDisableConfirmMessage(user.title)
              : l10n.adminUserEnableConfirmMessage(user.title),
      confirmLabel: disabling ? l10n.adminDisable : l10n.adminEnabled,
      destructive: disabling,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(adminUserControllerProvider.notifier)
          .updateUserStatus(
            user.id,
            disabling ? AdminUserStatus.disabled : AdminUserStatus.active,
          );
    } catch (error) {
      if (context.mounted) {
        showOmniFeedback(
          context,
          describeUserFacingError(error, l10n: l10n).message,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  /// 批量启用/禁用：确认后走后端逐项端点，失败项不中断其余用户；
  /// 完成反馈复用任务批量口径（成功/失败计数）。
  Future<void> _batchUpdateUserStatus(
    BuildContext context,
    WidgetRef ref,
    List<AdminUser> targets, {
    required bool disabling,
  }) async {
    if (targets.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title:
          disabling ? l10n.adminBatchDisableUsers : l10n.adminBatchEnableUsers,
      message:
          disabling
              ? l10n.adminBatchDisableConfirmMessage('${targets.length}')
              : l10n.adminBatchEnableConfirmMessage('${targets.length}'),
      confirmLabel: disabling ? l10n.adminDisable : l10n.adminEnabled,
      destructive: disabling,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      final result = await ref
          .read(adminUserControllerProvider.notifier)
          .batchUpdateUserStatus(
            targets.map((user) => user.id).toList(),
            disabling ? AdminUserStatus.disabled : AdminUserStatus.active,
          );
      if (context.mounted) {
        showOmniFeedback(
          context,
          l10n.adminBatchCompleted(
            result.successCount,
            result.failedIds.length,
          ),
          severity:
              result.failedIds.isEmpty
                  ? OmniFeedbackSeverity.success
                  : OmniFeedbackSeverity.warning,
        );
      }
    } catch (error) {
      if (context.mounted) {
        showOmniFeedback(
          context,
          describeUserFacingError(error, l10n: l10n).message,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationDestructiveConfirm(
      context,
      title: l10n.adminDeleteUser,
      message: l10n.adminDeleteUserConfirmMessage(user.title),
      confirmPhrase: user.username,
      confirmLabel: l10n.adminDeleteUser,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(adminUserControllerProvider.notifier).deleteUser(user.id);
    } catch (error) {
      if (context.mounted) {
        showOmniFeedback(
          context,
          describeUserFacingError(error, l10n: l10n).message,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}

AdminTagTone _roleTone(String role) {
  return switch (role) {
    AdminRoles.superAdmin => AdminTagTone.neutral,
    AdminRoles.admin => AdminTagTone.info,
    AdminRoles.member => AdminTagTone.success,
    _ => AdminTagTone.warning,
  };
}

/// 配额使用单元格：`已用 / 上限` mono 数值 + 底部 2px 使用率线。
/// 语义色仅在线上示警（≥85% 绯红、≥70% 琥珀，其余中性填充）；
/// 超级管理员与无上限账户按设计即为 ∞，只显示 `已用 / ∞` 不画线。
class _QuotaUsageCell extends StatelessWidget {
  const _QuotaUsageCell({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final adminColors = context.adminColors;
    final unlimited = user.isSuperAdmin || user.isQuotaUnlimited;
    final text =
        '${formatFileSize(user.usedBytes)} / ${unlimited ? '∞' : formatFileSize(user.quotaBytes)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AdminCellText(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontWeight: FontWeight.w600,
            color: unlimited ? adminColors.onSurfaceVariant : null,
          ),
        ),
        if (!unlimited) ...[
          const SizedBox(height: 3),
          Container(
            height: 2,
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: user.quotaUsage.clamp(0.0, 1.0),
              child: ColoredBox(color: _usageLineColor(adminColors)),
            ),
          ),
        ],
      ],
    );
  }

  /// 使用率线颜色：接近上限才示警，健康区间保持中性填充。
  Color _usageLineColor(AdminColors adminColors) {
    final usage = user.quotaUsage;
    if (usage >= 0.85) {
      return adminColors.error;
    }
    if (usage >= 0.7) {
      return adminColors.warning;
    }
    return adminColors.onSurfaceVariant;
  }
}

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.selectedCount,
    required this.hasActive,
    required this.hasDisabled,
    required this.onBatchDisable,
    required this.onBatchEnable,
    required this.onClear,
  });

  final int selectedCount;

  /// 选中集包含活跃用户：显示“批量禁用”。
  final bool hasActive;

  /// 选中集包含已禁用用户：显示“批量启用”。
  final bool hasDisabled;

  final VoidCallback onBatchDisable;
  final VoidCallback onBatchEnable;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        // 左缘 2px 主色锚定线：选中态在页面中的视觉锚点，其余三边细线。
        border: Border(
          left: BorderSide(width: 2, color: scheme.primary),
          top: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.checklist_rounded, size: 18),
          Text(
            l10n.adminSelectedUsers('$selectedCount'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (hasActive)
            FilledButton.tonalIcon(
              onPressed: onBatchDisable,
              icon: Icon(Icons.block_outlined, size: 16, color: scheme.error),
              label: Text(l10n.adminBatchDisableUsers),
            ),
          if (hasDisabled)
            FilledButton.tonalIcon(
              onPressed: onBatchEnable,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: Text(l10n.adminBatchEnableUsers),
            ),
          FilledButton.tonalIcon(
            onPressed:
                () => showWorkstationDialog(
                  context: context,
                  builder: (context) => const _BatchQuotaDialog(),
                ),
            icon: const Icon(Icons.storage_outlined, size: 16),
            label: Text(l10n.adminBatchQuota),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text(l10n.adminDeselect),
          ),
        ],
      ),
    );
  }
}
