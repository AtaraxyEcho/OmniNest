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

typedef _SharedSpaceCapability =
    ({
      String label,
      bool Function(AdminSharedSpacePermission) read,
      AdminSharedSpacePermission Function(AdminSharedSpacePermission) toggle,
    });

class _SharedSpacePermissionSectionState
    extends ConsumerState<_SharedSpacePermissionSection> {
  Map<String, AdminSharedSpacePermission>? _draft;
  Map<String, AdminSharedSpacePermission> _original = const {};
  bool _saving = false;

  List<_SharedSpaceCapability> _capabilities(AppLocalizations l10n) {
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

  void _resetDraft() {
    if (_saving || _original.isEmpty) {
      return;
    }
    setState(() {
      _draft = Map<String, AdminSharedSpacePermission>.of(_original);
    });
  }

  void _setAllCapabilities(AdminSharedSpacePermission permission, bool value) {
    if (_saving || _draft == null) {
      return;
    }
    setState(() {
      _draft![permission.roleId] = permission.copyWith(
        canBrowse: value,
        canUpload: value,
        canDownload: value,
        canDeleteOwn: value,
        canDeleteAny: value,
        canMoveTo: value,
        canMoveFrom: value,
        canCreateFolder: value,
      );
    });
  }

  Future<bool> _confirmSave(AppLocalizations l10n, int changedCount) async {
    final title = l10n.adminSharedSpaceMatrixSave;
    final message = l10n.adminSharedSpaceMatrixConfirm('$changedCount');
    if (DesktopShellScope.isHosted(context)) {
      final skin = DesktopSkin.of(context);
      final result = await showDesktopDialog<bool>(
        context,
        builder:
            (dialogContext) => DesktopDialog(
              title: title,
              width: 440,
              content: Text(
                message,
                style: DesktopType.body(skin.text2).copyWith(height: 1.55),
              ),
              actions: [
                DesktopButton(
                  label: l10n.coreCancel,
                  variant: DesktopButtonVariant.ghost,
                  onPressed: () => closeDesktopModal(dialogContext, false),
                ),
                DesktopButton(
                  label: l10n.adminSharedSpaceMatrixSave,
                  variant: DesktopButtonVariant.primary,
                  onPressed: () => closeDesktopModal(dialogContext, true),
                ),
              ],
            ),
      );
      return result == true;
    }
    return _confirmMaintenanceAction(context, title: title, message: message);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final changed = _changed();
    if (changed.isEmpty || _saving) {
      return;
    }
    final confirmed = await _confirmSave(l10n, changed.length);
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

  Widget _buildDesktop(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<AdminSharedSpacePermission>> permissionsAsync,
    List<_SharedSpaceCapability> capabilities,
  ) {
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final loadedPermissions = permissionsAsync.asData?.value;
    if (loadedPermissions != null) {
      _syncDraft(loadedPermissions);
    }
    final draft = _draft;
    final changed = _changed();
    final hasChanges = changed.isNotEmpty;

    return AdminCard(
      title: l10n.adminSharedSpaceMatrixTitle,
      count: draft?.length,
      subtitle: l10n.adminSharedSpaceMatrixSubtitle,
      childGap: 14,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasChanges) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: skin.accentWash(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: skin.accentWash(0.32)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: skin.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isZh
                        ? '${changed.length} 项未保存'
                        : '${changed.length} unsaved',
                    style: DesktopType.caption(skin.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          DesktopButton(
            label: isZh ? '还原' : 'Revert',
            icon: DesktopIcons.undo,
            variant: DesktopButtonVariant.ghost,
            onPressed: _saving || !hasChanges ? null : _resetDraft,
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label: l10n.adminSharedSpaceMatrixSave,
            icon: DesktopIcons.check,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed: _saving || !hasChanges ? null : _save,
          ),
        ],
      ),
      child: permissionsAsync.when(
        loading: () => const DesktopSkeletonRows(count: 4),
        error:
            (error, _) => DesktopErrorView(
              message:
                  describeUserFacingError(error, l10n: l10n).displayMessage,
              onRetry: () => ref.invalidate(sharedSpacePermissionsProvider),
              minHeightFactor: 0.2,
            ),
        data: (permissions) {
          _syncDraft(permissions);
          final currentDraft = _draft!;
          if (currentDraft.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  l10n.adminSharedSpaceMatrixEmpty,
                  style: DesktopType.caption(skin.text3),
                ),
              ),
            );
          }
          final roles = currentDraft.values.toList(growable: false);
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1040 ? 2 : 1;
              final cardWidth =
                  (constraints.maxWidth - 14 * (columns - 1)) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final permission in roles)
                    SizedBox(
                      width: cardWidth,
                      child: _DesktopSharedSpaceRoleCard(
                        permission: permission,
                        original: _original[permission.roleId] ?? permission,
                        roleName: _adminRoleName(l10n, permission.roleCode),
                        capabilities: capabilities,
                        saving: _saving,
                        isZh: isZh,
                        onToggleCapability:
                            (capability) => setState(() {
                              _draft![permission.roleId] = capability.toggle(
                                permission,
                              );
                            }),
                        onSetAll:
                            (value) => _setAllCapabilities(permission, value),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final permissionsAsync = ref.watch(sharedSpacePermissionsProvider);
    final capabilities = _capabilities(l10n);
    if (DesktopShellScope.isHosted(context)) {
      return _buildDesktop(context, l10n, permissionsAsync, capabilities);
    }
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

class _DesktopSharedSpaceRoleCard extends StatelessWidget {
  const _DesktopSharedSpaceRoleCard({
    required this.permission,
    required this.original,
    required this.roleName,
    required this.capabilities,
    required this.saving,
    required this.isZh,
    required this.onToggleCapability,
    required this.onSetAll,
  });

  final AdminSharedSpacePermission permission;
  final AdminSharedSpacePermission original;
  final String roleName;
  final List<_SharedSpaceCapability> capabilities;
  final bool saving;
  final bool isZh;
  final ValueChanged<_SharedSpaceCapability> onToggleCapability;
  final ValueChanged<bool> onSetAll;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final enabledCount =
        capabilities.where((cap) => cap.read(permission)).length;
    final allEnabled = enabledCount == capabilities.length;
    final roleDirty = !permission.sameCapabilities(original);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(
          color: roleDirty ? skin.accentWash(0.42) : skin.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  _roleIcon(permission.roleCode),
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
                      roleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.rowTitle(skin.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$enabledCount/${capabilities.length}',
                      style: DesktopType.caption(
                        enabledCount > 0 ? skin.text2 : skin.text3,
                      ),
                    ),
                  ],
                ),
              ),
              DesktopLink(
                label:
                    allEnabled
                        ? (isZh ? '清空' : 'Clear')
                        : (isZh ? '全选' : 'Select all'),
                trailing: false,
                onPressed: saving ? null : () => onSetAll(!allEnabled),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final capability in capabilities)
                _DesktopCapabilityPill(
                  label: capability.label,
                  checked: capability.read(permission),
                  dirty:
                      capability.read(permission) != capability.read(original),
                  enabled: !saving,
                  onTap: () => onToggleCapability(capability),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopCapabilityPill extends StatelessWidget {
  const _DesktopCapabilityPill({
    required this.label,
    required this.checked,
    required this.dirty,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final bool dirty;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      enabled: enabled,
      builder:
          (context, hovered) => GestureDetector(
            onTap: enabled ? onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.55,
              alwaysIncludeSemantics: true,
              child: AnimatedContainer(
                duration: MotionToken.reduced(context, MotionToken.fast),
                curve: MotionToken.curve,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color:
                      checked
                          ? skin.accentWash(hovered ? 0.16 : 0.11)
                          : hovered
                          ? skin.raise2
                          : skin.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        checked
                            ? skin.accentWash(0.45)
                            : hovered
                            ? skin.line2
                            : skin.line,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: MotionToken.reduced(context, MotionToken.fast),
                      curve: MotionToken.curve,
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: checked ? skin.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: checked ? skin.accent : skin.line2,
                          width: 1.2,
                        ),
                      ),
                      child:
                          checked
                              ? Icon(
                                DesktopIcons.check,
                                size: 12,
                                color: skin.accentInk,
                              )
                              : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: DesktopType.dense(
                        checked ? skin.text : skin.text2,
                      ),
                    ),
                    if (dirty) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: skin.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
    );
  }
}
