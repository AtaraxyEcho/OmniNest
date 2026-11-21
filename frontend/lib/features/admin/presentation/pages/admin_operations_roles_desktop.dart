part of 'admin_operations_pages.dart';

/// 角色分区的桌面排版（样例 `AdminIdentity.tsx` 的 Roles / Permissions 两张卡）：
/// 角色卡网格（图标 + 描述 + 权限比 + 模块标签）+ 业务模块权限矩阵。
/// 权限编辑、新建与删除仍走既有对话框，不复制业务逻辑。
class _DesktopRolesPanel extends ConsumerStatefulWidget {
  const _DesktopRolesPanel({required this.view});

  final AdminRoleManagementView view;

  @override
  ConsumerState<_DesktopRolesPanel> createState() => _DesktopRolesPanelState();
}

class _DesktopRolesPanelState extends ConsumerState<_DesktopRolesPanel> {
  String? _selectedRoleCode;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final canManageSharedSpace = permissions.contains('system:config:manage');
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final roles =
        query.isEmpty
            ? view.roles
            : view.roles
                .where(
                  (role) =>
                      role.code.toLowerCase().contains(query) ||
                      role.name.toLowerCase().contains(query) ||
                      role.description.toLowerCase().contains(query),
                )
                .toList();
    final total = view.permissions.length;
    final selectedRole =
        _selectedRoleCode == null
            ? null
            : view.roles
                .where((role) => role.code == _selectedRoleCode)
                .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(
          title: l10n.adminRoles,
          count: roles.length,
          subtitle: l10n.adminRolePermissionsSubtitle,
          action: DesktopButton(
            label: l10n.adminCreateRole,
            icon: DesktopIcons.plus,
            variant: DesktopButtonVariant.soft,
            onPressed:
                () => showDesktopDrawer<void>(
                  context,
                  width: 620,
                  builder: (_) => const _CreateRoleDialog(drawerMode: true),
                ),
          ),
          child:
              roles.isEmpty
                  ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        query.isEmpty ? l10n.adminNoRoles : l10n.adminNoMatch,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ),
                  )
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >= 1180
                              ? 3
                              : constraints.maxWidth >= 760
                              ? 2
                              : 1;
                      final width =
                          (constraints.maxWidth - 14 * (columns - 1)) / columns;
                      return Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          for (var i = 0; i < roles.length; i++)
                            SizedBox(
                              width: width,
                              child: DesktopStagger(
                                index: i,
                                child: _DesktopRoleCard(
                                  role: roles[i],
                                  permissions: view.permissions,
                                  total: total,
                                  selected: selectedRole?.code == roles[i].code,
                                  onSelect:
                                      () => setState(() {
                                        _selectedRoleCode =
                                            _selectedRoleCode == roles[i].code
                                                ? null
                                                : roles[i].code;
                                      }),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
        ),
        const SizedBox(height: 14),
        AdminCard(
          title:
              selectedRole == null
                  ? l10n.adminPermissionMatrixTitle
                  : '${l10n.adminPermissionMatrixTitle} · ${selectedRole.name}',
          subtitle: l10n.adminPermissionMatrixSubtitle,
          action:
              selectedRole == null
                  ? null
                  : DesktopLink(
                    label: l10n.desktopFilesClear,
                    onPressed: () => setState(() => _selectedRoleCode = null),
                  ),
          child: _DesktopPermissionMatrix(
            permissions: view.permissions,
            roleCount: view.roles.length,
            selectedRole: selectedRole,
          ),
        ),
        if (canManageSharedSpace) ...[
          const SizedBox(height: 14),
          const _SharedSpacePermissionSection(),
        ],
      ],
    );
  }
}

class _DesktopRoleCard extends ConsumerWidget {
  const _DesktopRoleCard({
    required this.role,
    required this.permissions,
    required this.total,
    this.selected = false,
    this.onSelect,
  });

  final AdminRoleDetail role;
  final List<AdminPermissionDetail> permissions;
  final int total;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final locked = role.code == AdminRoles.superAdmin;
    final modules = <String>{
      for (final item in permissions)
        if (role.permissions.contains(item.code)) item.module,
    };
    final ratio = total == 0 ? 0.0 : role.permissions.length / total;

    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onSelect,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: DesktopMotion.ease,
              transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color:
                    selected
                        ? skin.accentWash(0.10)
                        : hovered
                        ? skin.raise2
                        : skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
                border: Border.all(
                  color:
                      selected
                          ? skin.accent
                          : hovered
                          ? skin.line2
                          : skin.line,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: skin.accentWash(0.14),
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radiusSmall,
                          ),
                        ),
                        child: Icon(
                          _roleIcon(role.code),
                          size: 17,
                          color: skin.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              role.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.rowTitle(skin.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              role.builtIn
                                  ? l10n.adminRoleBuiltinTag
                                  : l10n.adminRoleCustomTag,
                              style: DesktopType.micro(skin.text3),
                            ),
                          ],
                        ),
                      ),
                      if (locked)
                        Tooltip(
                          message: l10n.adminRoleSuperAdminLocked,
                          child: Icon(
                            DesktopIcons.lock,
                            size: 15,
                            color: skin.text3,
                          ),
                        )
                      else if (!role.builtIn)
                        DesktopIconButton(
                          icon: DesktopIcons.trash,
                          size: 26,
                          iconSize: 14,
                          color: skin.bad,
                          tooltip: l10n.adminRoleDelete,
                          onPressed:
                              () => _confirmDeleteRole(context, ref, role),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    role.description.isEmpty
                        ? l10n.adminSystemRoles
                        : role.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text2),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(color: skin.raise3),
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: ratio.clamp(0.0, 1.0),
                                child: ColoredBox(color: skin.accent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.adminPermissionSelectedCount(
                            '${role.permissions.length}',
                            '$total',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.micro(skin.text3),
                        ),
                      ),
                      DesktopLink(
                        label: l10n.adminConfigurePermissions,
                        onPressed:
                            locked
                                ? null
                                : () => showDesktopDrawer<void>(
                                  context,
                                  width: 620,
                                  builder:
                                      (_) => _RolePermissionDialog(
                                        role: role,
                                        permissions: permissions,
                                        drawerMode: true,
                                      ),
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final module in modules.take(3))
                        DesktopChip(adminPermissionModuleLabel(l10n, module)),
                      if (modules.length > 3)
                        DesktopChip('+${modules.length - 3}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

IconData _roleIcon(String code) {
  return switch (code) {
    AdminRoles.superAdmin => Icons.verified_user_outlined,
    AdminRoles.admin => Icons.key_outlined,
    AdminRoles.member => Icons.groups_2_outlined,
    AdminRoles.guest => Icons.person_outline_rounded,
    _ => Icons.badge_outlined,
  };
}

Future<void> _confirmDeleteRole(
  BuildContext context,
  WidgetRef ref,
  AdminRoleDetail role,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showWorkstationConfirmDialog(
    context,
    title: l10n.adminRoleDelete,
    message: l10n.adminRoleDeleteConfirmMessage(role.name, role.code),
    destructive: true,
    confirmLabel: l10n.adminRoleDelete,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  try {
    await ref.read(adminOperationsActionsProvider).deleteRole(role.code);
  } catch (error) {
    if (context.mounted) {
      showOmniFeedback(
        context,
        errorReason(error, l10n),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

/// 业务模块权限矩阵：样例 `.perm-group`（模块眉标 + n/m + 权限码列表）。
class _DesktopPermissionMatrix extends StatelessWidget {
  const _DesktopPermissionMatrix({
    required this.permissions,
    required this.roleCount,
    this.selectedRole,
  });

  final List<AdminPermissionDetail> permissions;
  final int roleCount;
  final AdminRoleDetail? selectedRole;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final grantedSet = selectedRole?.permissions.toSet();
    final modules = <String, List<AdminPermissionDetail>>{};
    for (final item in permissions) {
      modules.putIfAbsent(item.module, () => []).add(item);
    }
    if (modules.isEmpty) {
      return Text(l10n.adminNoMatch, style: DesktopType.caption(skin.text3));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1180
                ? 3
                : constraints.maxWidth >= 760
                ? 2
                : 1;
        final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final entry in modules.entries)
              Builder(
                builder: (context) {
                  final grantedInModule =
                      grantedSet == null
                          ? entry.value.length
                          : entry.value
                              .where((p) => grantedSet.contains(p.code))
                              .length;
                  final hasGranted = grantedSet != null && grantedInModule > 0;
                  return SizedBox(
                    width: width,
                    child: AnimatedContainer(
                      duration: DesktopMotion.of(context, DesktopMotion.fast),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: hasGranted ? skin.accentWash(0.08) : skin.raise2,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radius,
                        ),
                        border: Border.all(
                          color: hasGranted ? skin.accentWash(0.35) : skin.line,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  adminPermissionModuleLabel(
                                    l10n,
                                    entry.key,
                                  ).toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.eyebrow(
                                    hasGranted ? skin.accent : skin.text3,
                                  ),
                                ),
                              ),
                              Text(
                                grantedSet == null
                                    ? '${entry.value.length} / ${permissions.length}'
                                    : '$grantedInModule / ${entry.value.length}',
                                style: DesktopType.numeric(
                                  hasGranted ? skin.accent : skin.text3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final permission in entry.value.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  if (grantedSet != null) ...[
                                    Icon(
                                      grantedSet.contains(permission.code)
                                          ? DesktopIcons.check
                                          : DesktopIcons.close,
                                      size: 11,
                                      color:
                                          grantedSet.contains(permission.code)
                                              ? skin.accent
                                              : skin.text3.withValues(
                                                alpha: 0.45,
                                              ),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Expanded(
                                    child: Text(
                                      permission.code,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DesktopType.mono(
                                        grantedSet == null
                                            ? skin.text2
                                            : grantedSet.contains(
                                              permission.code,
                                            )
                                            ? skin.accent
                                            : skin.text3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (entry.value.length > 3)
                            Text(
                              '+${entry.value.length - 3}',
                              style: DesktopType.micro(skin.text3),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
