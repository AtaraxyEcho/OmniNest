part of 'admin_operations_pages.dart';

class AdminRolesPage extends ConsumerWidget {
  const AdminRolesPage({required this.view, super.key});

  final AdminRoleManagementView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final filteredRoles =
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
    final permissionTotal = filteredRoles.fold<int>(
      0,
      (total, role) => total + role.permissions.length,
    );
    return _PageEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminRoleManagement,
          subtitle: l10n.adminRoleManagementSubtitle,
          trailing: AdminStatusPill(
            label: l10n.adminPermissionCount('${view.permissions.length}'),
          ),
        ),
        const SizedBox(height: 24),
        _MetricGrid(
          children: [
            AdminMetricCard(
              title: l10n.adminRoles,
              value: view.roles.length.toString(),
              detail: l10n.adminSystemRoles,
              icon: Icons.verified_user_outlined,
            ),
            AdminMetricCard(
              title: l10n.adminPermissionBindings,
              value: permissionTotal.toString(),
              detail: l10n.adminRolePermissions,
              icon: Icons.key_outlined,
              accent: adminColors.info,
            ),
            AdminMetricCard(
              title: l10n.adminPermissionModules,
              value:
                  view.permissions
                      .map((item) => item.module)
                      .toSet()
                      .length
                      .toString(),
              detail: l10n.adminBusinessDomains,
              icon: Icons.account_tree_outlined,
              accent: context.adminColors.tertiary,
            ),
          ],
        ),
        const SizedBox(height: 24),
        AdminInfoPanel(
          title: l10n.adminRolePermissionsTitle,
          subtitle: l10n.adminRolePermissionsSubtitle,
          children:
              filteredRoles.isEmpty
                  ? [
                    _EmptyText(
                      query.isEmpty ? l10n.adminNoRoles : l10n.adminNoMatch,
                    ),
                  ]
                  : [
                    for (final role in filteredRoles)
                      _InfoRow(
                        leading: '${role.name} (${role.code})',
                        middle:
                            role.description.isEmpty
                                ? l10n.adminPermissionCountInline(
                                  '${role.permissions.length}',
                                )
                                : '${role.description}\n${l10n.adminPermissionCountInline('${role.permissions.length}')}',
                        trailing: FilledButton.tonalIcon(
                          onPressed:
                              role.code == AdminRoles.superAdmin
                                  ? null
                                  : () => showDialog<void>(
                                    context: context,
                                    builder:
                                        (context) => _RolePermissionDialog(
                                          role: role,
                                          permissions: view.permissions,
                                        ),
                                  ),
                          icon: const Icon(Icons.tune_rounded),
                          label: Text(l10n.adminConfigurePermissions),
                        ),
                      ),
                  ],
        ),
      ],
    );
  }
}

class _RolePermissionDialog extends ConsumerStatefulWidget {
  const _RolePermissionDialog({required this.role, required this.permissions});

  final AdminRoleDetail role;
  final List<AdminPermissionDetail> permissions;

  @override
  ConsumerState<_RolePermissionDialog> createState() =>
      _RolePermissionDialogState();
}

class _RolePermissionDialogState extends ConsumerState<_RolePermissionDialog> {
  late final Set<String> _selected = widget.role.permissions.toSet();
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modules = widget.permissions.map((item) => item.module).toSet();
    return AlertDialog(
      title: Text(l10n.adminConfigureRolePermissions(widget.role.name)),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final module in modules) ...[
                Text(module, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final permission in widget.permissions.where(
                      (item) => item.module == module,
                    ))
                      FilterChip(
                        selected: _selected.contains(permission.code),
                        label: Text(permission.name),
                        onSelected:
                            permission.enabled
                                ? (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selected.add(permission.code);
                                    } else {
                                      _selected.remove(permission.code);
                                    }
                                  });
                                }
                                : null,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.adminColors.error,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(_submitting ? l10n.adminSaving : l10n.adminSave),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .updateRolePermissions(widget.role.code, _selected);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = describeUserFacingError(error).message);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
