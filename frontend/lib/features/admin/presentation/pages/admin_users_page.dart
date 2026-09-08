import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';

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

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({required this.state, super.key});

  final AdminUserState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: l10n.adminUserManagement,
          subtitle: l10n.adminUserManagementSubtitle,
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 980 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.9,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                AdminMetricCard(
                  title: l10n.adminTotalUsers,
                  value: state.users.length.toString(),
                  detail: l10n.adminDatabaseAccounts,
                  icon: Icons.group_outlined,
                ),
                AdminMetricCard(
                  title: l10n.adminSuperAdmin,
                  value: state.countByRole(AdminRoles.superAdmin).toString(),
                  detail: l10n.adminHighestPrivilege,
                  icon: Icons.workspace_premium_outlined,
                  accent: adminColors.tertiary,
                ),
                AdminMetricCard(
                  title: l10n.adminRoleAdmin,
                  value: state.countByRole(AdminRoles.admin).toString(),
                  detail: l10n.adminSystemMaintenance,
                  icon: Icons.admin_panel_settings_outlined,
                  accent: adminColors.info,
                ),
                AdminMetricCard(
                  title: l10n.adminMemberGuest,
                  value:
                      '${state.countByRole(AdminRoles.member)} / '
                      '${state.countByRole(AdminRoles.guest)}',
                  detail: l10n.adminBusinessAccess,
                  icon: Icons.groups_2_outlined,
                  accent: adminColors.success,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _UserManagementPanel(state: state),
      ],
    );
  }
}

class _UserManagementPanel extends ConsumerWidget {
  const _UserManagementPanel({required this.state});

  final AdminUserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AdminInfoPanel(
      title: l10n.adminAccountList,
      subtitle: l10n.adminAccountListSubtitle,
      trailing: FilledButton.icon(
        onPressed:
            () => showDialog<void>(
              context: context,
              builder: (context) => const _CreateUserDialog(),
            ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.adminCreateUser),
      ),
      children: [
        if (state.hasSelection)
          _BatchActionBar(
            selectedCount: state.selectedIds.length,
            onClear:
                ref.read(adminUserControllerProvider.notifier).clearSelection,
          ),
        if (state.hasSelection) const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            final searchField = TextField(
              onChanged:
                  ref.read(adminUserControllerProvider.notifier).setSearchTerm,
              decoration: InputDecoration(
                hintText: l10n.adminSearchUsers,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            );
            final filters = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: state.roleFilter == null,
                  label: Text(l10n.adminAll),
                  onSelected:
                      (_) => ref
                          .read(adminUserControllerProvider.notifier)
                          .setRoleFilter(null),
                ),
                for (final role in AdminRoles.allRoles)
                  FilterChip(
                    selected: state.roleFilter == role,
                    label: Text(adminRoleDisplayName(l10n, role)),
                    onSelected:
                        (_) => ref
                            .read(adminUserControllerProvider.notifier)
                            .setRoleFilter(role),
                  ),
              ],
            );

            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [searchField, const SizedBox(height: 12), filters],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 360, child: searchField),
                const SizedBox(width: 18),
                Expanded(child: filters),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        if (state.visibleUsers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(48),
            child: Text(l10n.adminNoMatchingUsers),
          )
        else ...[
          _UserTable(users: state.visibleUsers, selectedIds: state.selectedIds),
          if (state.hasMoreUsers)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed:
                      () =>
                          ref
                              .read(adminUserControllerProvider.notifier)
                              .loadMoreUsers(),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    l10n.adminLoadMore(
                      '${state.users.length}',
                      '${state.total}',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _UserTable extends ConsumerWidget {
  const _UserTable({required this.users, required this.selectedIds});

  final List<AdminUser> users;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.adminColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceContainerLow.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: ListView.separated(
        itemCount: users.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        separatorBuilder:
            (context, index) => Divider(
              height: 1,
              color: c.outlineVariant.withValues(alpha: 0.16),
            ),
        itemBuilder: (context, index) {
          final user = users[index];
          return _UserRow(
            user: user,
            isSelected: selectedIds.contains(user.id),
            onToggleSelection:
                () => ref
                    .read(adminUserControllerProvider.notifier)
                    .toggleSelection(user.id),
          );
        },
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({
    required this.user,
    required this.isSelected,
    required this.onToggleSelection,
  });

  final AdminUser user;
  final bool isSelected;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;
          // 身份信息 + 状态标签
          final checkbox = Checkbox(
            value: isSelected,
            onChanged: user.isSuperAdmin ? null : (_) => onToggleSelection(),
          );

          final identity = Row(
            children: [
              CircleAvatar(
                backgroundColor: _roleColor(
                  user.role,
                  adminColors,
                ).withValues(alpha: 0.18),
                child: Text(
                  user.username.isEmpty ? '?' : user.username[0].toUpperCase(),
                  style: TextStyle(color: _roleColor(user.role, adminColors)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.title,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 状态标签（仅在宽屏时放在同行）
                        if (isWide)
                          AdminStatusPill(
                            label: adminUserStatusDisplayName(
                              l10n,
                              user.status,
                            ),
                            color:
                                user.isActive
                                    ? adminColors.success
                                    : adminColors.error,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: adminColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final roles = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final role in user.roles)
                _RoleChip(role: role, color: _roleColor(role, adminColors)),
            ],
          );

          final quota = SizedBox(
            width: isWide ? 120 : double.infinity,
            child:
                user.isQuotaUnlimited
                    ? Text(
                      l10n.adminUnlimited,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: adminColors.onSurfaceVariant,
                      ),
                    )
                    : LinearProgressIndicator(
                      value: user.quotaUsage,
                      minHeight: 5,
                      backgroundColor: adminColors.surfaceContainerHighest,
                    ),
          );

          final actions = _UserActions(user: user); // 不再包含状态 pill

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [checkbox, Expanded(child: identity)]),
                const SizedBox(height: 12),
                // 非宽屏模式下，状态标签单独一行
                AdminStatusPill(
                  label: adminUserStatusDisplayName(l10n, user.status),
                  color:
                      user.isActive ? adminColors.success : adminColors.error,
                ),
                const SizedBox(height: 12),
                Text(
                  user.email ?? l10n.adminNotSetEmail,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: adminColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                roles,
                const SizedBox(height: 12),
                quota,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            children: [
              checkbox,
              Expanded(flex: 3, child: identity),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  user.email ?? l10n.adminNotSetEmail,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: adminColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: roles),
              const SizedBox(width: 12),
              SizedBox(width: 100, child: quota),
              const SizedBox(width: 12),
              Flexible(flex: 3, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _UserActions extends ConsumerWidget {
  const _UserActions({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilledButton.tonalIcon(
          onPressed:
              user.isSuperAdmin
                  ? null
                  : () => ref
                      .read(adminUserControllerProvider.notifier)
                      .updateUserStatus(
                        user.id,
                        user.isActive
                            ? AdminUserStatus.disabled
                            : AdminUserStatus.active,
                      ),
          icon: Icon(
            user.isActive
                ? Icons.block_outlined
                : Icons.check_circle_outline_rounded,
          ),
          label: Text(user.isActive ? l10n.adminDisable : l10n.adminEnabled),
        ),
        FilledButton.tonalIcon(
          onPressed:
              user.isSuperAdmin
                  ? null
                  : () => showDialog<void>(
                    context: context,
                    builder: (context) => _EditUserRolesDialog(user: user),
                  ),
          icon: const Icon(Icons.badge_outlined),
          label: Text(l10n.adminRole),
        ),
        FilledButton.tonalIcon(
          onPressed:
              user.isSuperAdmin
                  ? null
                  : () => showDialog<void>(
                    context: context,
                    builder: (context) => _EditQuotaDialog(user: user),
                  ),
          icon: const Icon(Icons.storage_outlined),
          label: Text(l10n.adminQuota),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.color});

  final String role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          adminRoleDisplayName(AppLocalizations.of(context), role),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({required this.selectedCount, required this.onClear});

  final int selectedCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.tertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.checklist_rounded, color: c.tertiary, size: 20),
            Text(
              l10n.adminSelectedUsers('$selectedCount'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: c.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  () => showDialog<void>(
                    context: context,
                    builder: (context) => const _BatchQuotaDialog(),
                  ),
              icon: const Icon(Icons.storage_outlined),
              label: Text(l10n.adminBatchQuota),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(l10n.adminDeselect),
            ),
          ],
        ),
      ),
    );
  }
}
