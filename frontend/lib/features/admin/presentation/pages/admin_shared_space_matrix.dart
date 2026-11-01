part of 'admin_operations_pages.dart';

/// 角色编码到本地化名称；未知编码原样展示。
String _adminRoleName(AppLocalizations l10n, String role) {
  return switch (role) {
    AdminRoles.superAdmin => l10n.adminRoleSuperAdmin,
    AdminRoles.admin => l10n.adminRoleAdmin,
    AdminRoles.member => l10n.adminRoleMember,
    AdminRoles.guest => l10n.adminRoleGuest,
    _ => role,
  };
}

/// 共享空间角色能力矩阵：本地勾选、整批保存。
///
/// 服务端按角色逐条写入，因此保存前必须确认；保存过程中禁用勾选，
/// 成功后只失效一次矩阵 provider，避免逐角色刷新造成草稿被回灌。
class _SharedSpacePermissionSection extends ConsumerStatefulWidget {
  const _SharedSpacePermissionSection();

  @override
  ConsumerState<_SharedSpacePermissionSection> createState() =>
      _SharedSpacePermissionSectionState();
}

class _SharedSpacePermissionSectionState
    extends ConsumerState<_SharedSpacePermissionSection> {
  Map<String, AdminSharedSpacePermission>? _draft;
  Map<String, AdminSharedSpacePermission> _original = const {};
  bool _saving = false;

  List<
    ({
      String label,
      bool Function(AdminSharedSpacePermission) read,
      AdminSharedSpacePermission Function(AdminSharedSpacePermission) toggle,
    })
  >
  _capabilities(AppLocalizations l10n) {
    return [
      (
        label: l10n.adminSharedSpaceCapabilityBrowse,
        read: (permission) => permission.canBrowse,
        toggle:
            (permission) =>
                permission.copyWith(canBrowse: !permission.canBrowse),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityUpload,
        read: (permission) => permission.canUpload,
        toggle:
            (permission) =>
                permission.copyWith(canUpload: !permission.canUpload),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityDownload,
        read: (permission) => permission.canDownload,
        toggle:
            (permission) =>
                permission.copyWith(canDownload: !permission.canDownload),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityDeleteOwn,
        read: (permission) => permission.canDeleteOwn,
        toggle:
            (permission) =>
                permission.copyWith(canDeleteOwn: !permission.canDeleteOwn),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityDeleteAny,
        read: (permission) => permission.canDeleteAny,
        toggle:
            (permission) =>
                permission.copyWith(canDeleteAny: !permission.canDeleteAny),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityMoveTo,
        read: (permission) => permission.canMoveTo,
        toggle:
            (permission) =>
                permission.copyWith(canMoveTo: !permission.canMoveTo),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityMoveFrom,
        read: (permission) => permission.canMoveFrom,
        toggle:
            (permission) =>
                permission.copyWith(canMoveFrom: !permission.canMoveFrom),
      ),
      (
        label: l10n.adminSharedSpaceCapabilityCreateFolder,
        read: (permission) => permission.canCreateFolder,
        toggle:
            (permission) => permission.copyWith(
              canCreateFolder: !permission.canCreateFolder,
            ),
      ),
    ];
  }

  void _syncDraft(List<AdminSharedSpacePermission> permissions) {
    if (_draft != null) {
      return;
    }
    _original = {for (final item in permissions) item.roleId: item};
    _draft = {for (final item in permissions) item.roleId: item};
  }

  List<AdminSharedSpacePermission> _changed() {
    final draft = _draft;
    if (draft == null) {
      return const [];
    }
    return [
      for (final entry in draft.entries)
        if (!(entry.value.sameCapabilities(
          _original[entry.key] ?? entry.value,
        )))
          entry.value,
    ];
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final changed = _changed();
    if (changed.isEmpty || _saving) {
      return;
    }
    final confirmed = await _confirmMaintenanceAction(
      context,
      title: l10n.adminSharedSpaceMatrixSave,
      message: l10n.adminSharedSpaceMatrixConfirm('${changed.length}'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(adminOperationsActionsProvider)
          .updateSharedSpaceRolePermissions(changed);
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = null;
        _saving = false;
      });
      showOmniFeedback(
        context,
        l10n.adminSharedSpaceMatrixSaved,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      showOmniFeedback(
        context,
        describeUserFacingError(error, l10n: l10n).displayMessage,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final permissionsAsync = ref.watch(sharedSpacePermissionsProvider);
    final capabilities = _capabilities(l10n);
    return AdminInfoPanel(
      title: l10n.adminSharedSpaceMatrixTitle,
      subtitle: l10n.adminSharedSpaceMatrixSubtitle,
      headerDivider: true,
      trailing: FilledButton.icon(
        onPressed: _saving || _changed().isEmpty ? null : _save,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: Text(l10n.adminSharedSpaceMatrixSave),
      ),
      children: [
        permissionsAsync.when(
          loading: () => const _MaintenanceLoading(rows: 4),
          error:
              (error, _) => AppErrorView(
                message:
                    describeUserFacingError(error, l10n: l10n).displayMessage,
                onRetry: () => ref.invalidate(sharedSpacePermissionsProvider),
              ),
          data: (permissions) {
            _syncDraft(permissions);
            final draft = _draft!;
            if (draft.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.adminSharedSpaceMatrixEmpty),
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(l10n.adminSharedSpaceRole)),
                  for (final capability in capabilities)
                    DataColumn(label: Text(capability.label)),
                ],
                rows: [
                  for (final permission in draft.values)
                    DataRow(
                      cells: [
                        DataCell(
                          Text(_adminRoleName(l10n, permission.roleCode)),
                        ),
                        for (final capability in capabilities)
                          DataCell(
                            Checkbox(
                              value: capability.read(permission),
                              onChanged:
                                  _saving
                                      ? null
                                      : (_) => setState(() {
                                        _draft![permission.roleId] = capability
                                            .toggle(permission);
                                      }),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
