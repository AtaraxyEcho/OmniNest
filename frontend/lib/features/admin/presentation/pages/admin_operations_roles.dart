part of 'admin_operations_pages.dart';

class AdminRolesPage extends ConsumerWidget {
  const AdminRolesPage({required this.view, super.key});

  final AdminRoleManagementView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(adminSearchProvider).toLowerCase();
    final filteredRoles =
        (query.isEmpty
                ? view.roles
                : view.roles.where(
                  (role) =>
                      role.code.toLowerCase().contains(query) ||
                      role.name.toLowerCase().contains(query) ||
                      role.description.toLowerCase().contains(query),
                ))
            .toList()
          // 内置角色按 超管→管理员→成员→访客 固定次序，自定义角色按编码序殿后。
          ..sort((a, b) {
            const builtinOrder = [
              AdminRoles.superAdmin,
              AdminRoles.admin,
              AdminRoles.member,
              AdminRoles.guest,
            ];
            final ai = builtinOrder.indexOf(a.code);
            final bi = builtinOrder.indexOf(b.code);
            if (ai != bi) {
              return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
            }
            return a.code.compareTo(b.code);
          });
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
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 新增角色工具行：与下方权限面板同宽、按钮右对齐，紧贴操作对象。
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed:
                  () => showWorkstationDialog(
                    context: context,
                    builder: (context) => const _CreateRoleDialog(),
                  ),
              icon: const Icon(Icons.add_moderator_outlined),
              label: Text(l10n.adminCreateRole),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                      _RoleRow(role: role, permissions: view.permissions),
                  ],
        ),
        const SizedBox(height: 20),
        _PermissionMatrixPreview(permissions: view.permissions),
      ],
    );
  }
}

/// 角色行：名称 + 等宽 code 徽标 + 分类与权限统计一行化，描述单独成行。
class _RoleRow extends ConsumerWidget {
  const _RoleRow({required this.role, required this.permissions});

  final AdminRoleDetail role;
  final List<AdminPermissionDetail> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isSuperAdmin = role.code == AdminRoles.superAdmin;
    final moduleCount =
        permissions
            .where((item) => role.permissions.contains(item.code))
            .map((item) => item.module)
            .toSet()
            .length;
    return _InfoRow(
      leading: role.name,
      codeBadge: role.code,
      // 样板形态：分类徽标与权限统计并入标题行，窄屏随 Wrap 折行。
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonoCodeBadge(
            role.builtIn ? l10n.adminRoleBuiltinTag : l10n.adminRoleCustomTag,
          ),
          const SizedBox(width: 10),
          Text(
            l10n.adminRolePermissionSummary(
              '${role.permissions.length}',
              '$moduleCount',
            ),
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      middle:
          role.description.isEmpty ? l10n.adminSystemRoles : role.description,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSuperAdmin)
            Tooltip(
              message: l10n.adminRoleSuperAdminLocked,
              child: Icon(
                Icons.lock_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            )
          else ...[
            if (!role.builtIn)
              IconButton(
                tooltip: l10n.adminRoleDelete,
                icon: Icon(Icons.delete_outline_rounded, size: 18),
                color: scheme.error,
                onPressed: () => _confirmDelete(context, ref),
              ),
            FilledButton.tonalIcon(
              onPressed:
                  () => showWorkstationDialog(
                    context: context,
                    builder:
                        (context) => _RolePermissionDialog(
                          role: role,
                          permissions: permissions,
                        ),
                  ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: Text(l10n.adminConfigurePermissions),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
          describeUserFacingError(error).message,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}

/// 业务模块权限矩阵预览：按 module 分组派生，纯前端无额外请求。
class _PermissionMatrixPreview extends StatelessWidget {
  const _PermissionMatrixPreview({required this.permissions});

  final List<AdminPermissionDetail> permissions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final modules = <String, List<AdminPermissionDetail>>{};
    for (final item in permissions) {
      modules.putIfAbsent(item.module, () => []).add(item);
    }
    return AdminInfoPanel(
      title: l10n.adminPermissionMatrixTitle,
      subtitle: l10n.adminPermissionMatrixSubtitle,
      trailing: AdminStatusPill(
        label: '${modules.length} / ${permissions.length}',
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1080 ? 3 : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in modules.entries)
                  SizedBox(
                    width:
                        (constraints.maxWidth - 12 * (columns - 1)) / columns,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  adminPermissionModuleLabel(l10n, entry.key),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              // 卡头右侧：模块 mono 编码徽标 + 权限计数。
                              _MonoCodeBadge(entry.key.toUpperCase()),
                              const SizedBox(width: 6),
                              Text(
                                '${entry.value.length}',
                                style: TextStyle(
                                  fontFamily: AppTypography.monoFamily,
                                  fontFamilyFallback:
                                      AppTypography.monoFamilyFallback,
                                  fontSize: AppTypography.labelSmall,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final permission in entry.value.take(3))
                            Text(
                              '${permission.code} · ${permission.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          if (entry.value.length > 3)
                            Text(
                              '+${entry.value.length - 3}',
                              style: TextStyle(
                                fontFamily: AppTypography.monoFamily,
                                fontFamilyFallback:
                                    AppTypography.monoFamilyFallback,
                                fontSize: AppTypography.labelMicro,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 新建自定义角色弹窗：ROLE_ 前缀校验 + 权限模板克隆。
class _CreateRoleDialog extends ConsumerStatefulWidget {
  const _CreateRoleDialog();

  @override
  ConsumerState<_CreateRoleDialog> createState() => _CreateRoleDialogState();
}

/// 新建自定义角色：表单 + 业务模块父子权限树直接选定。
///
/// 提交两步走：先 createRole(baseTemplate: none) 建角色，勾选了权限则
/// 随即 updateRolePermissions 写入所选集合；两个接口均为既有契约。
class _CreateRoleDialogState extends ConsumerState<_CreateRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selected = <String>{};
  bool _submitting = false;
  String? _errorMessage;

  static final RegExp _codePattern = RegExp(r'^ROLE_[A-Z0-9_]{2,61}$');

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<AdminPermissionDetail> get _permissions =>
      ref.watch(adminRolesProvider).asData?.value.permissions ??
      const <AdminPermissionDetail>[];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return WorkstationDialogFrame(
      title: l10n.adminCreateRole,
      width: 640,
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: l10n.adminRoleCode,
                hintText: 'ROLE_MEDIA_OPERATOR',
                helperText: l10n.adminRoleCodeRule,
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                final code = value?.trim() ?? '';
                if (code.isEmpty || !_codePattern.hasMatch(code)) {
                  return l10n.adminRoleCodeRule;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.adminRoleDisplayName),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.adminRoleNameRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: l10n.adminRoleDescription),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: WorkstationDialogSectionLabel(
                    l10n.adminRolePermissionsTitle,
                  ),
                ),
                Text(
                  l10n.adminPermissionSelectedCount(
                    '${_selected.length}',
                    '${_permissions.length}',
                  ),
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: AdminPermissionTreePicker(
                  permissions: _permissions,
                  selected: _selected,
                  onTogglePermission:
                      (permission) => setState(() {
                        if (!_selected.remove(permission.code)) {
                          _selected.add(permission.code);
                        }
                      }),
                  onToggleModule: _toggleModule,
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.adminColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.add_moderator_outlined),
          label: Text(_submitting ? l10n.adminCreating : l10n.adminCreate),
        ),
      ],
    );
  }

  /// 组内存在未勾选项时全选，否则清空该组。
  void _toggleModule(String module) {
    final codes =
        _permissions
            .where((item) => item.module == module && item.enabled)
            .map((item) => item.code)
            .toList();
    final allSelected = codes.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(codes);
      } else {
        _selected.addAll(codes);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final actions = ref.read(adminOperationsActionsProvider);
    try {
      final code = _codeController.text.trim();
      await actions.createRole(
        AdminCreateRoleInput(
          code: code,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          baseTemplate: 'none',
        ),
      );
      if (_selected.isNotEmpty) {
        await actions.updateRolePermissions(code, _selected);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = describeUserFacingError(error).message);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
    final scheme = Theme.of(context).colorScheme;
    final enabledPermissions =
        widget.permissions.where((item) => item.enabled).toList();
    return WorkstationDialogFrame(
      title: l10n.adminConfigureRolePermissions(widget.role.name),
      headerLabel: widget.role.code,
      width: 720,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(
                  l10n.adminPermissionSelectedCount(
                    '${_selected.length}',
                    '${widget.permissions.length}',
                  ),
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed:
                      () => setState(
                        () => _selected.addAll(
                          enabledPermissions.map((item) => item.code),
                        ),
                      ),
                  child: Text(l10n.adminPermissionSelectAll),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: Text(l10n.adminPermissionClear),
                ),
              ],
            ),
          ),
          // 树形权限选择：模块行三态勾选/计数 + 缩进子权限行，
          // 选择仍落回扁平 code 集合（保存逻辑不变）。
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: SingleChildScrollView(
                child: AdminPermissionTreePicker(
                  permissions: widget.permissions,
                  selected: _selected,
                  onTogglePermission:
                      (permission) => setState(() {
                        if (!_selected.remove(permission.code)) {
                          _selected.add(permission.code);
                        }
                      }),
                  onToggleModule: _toggleModule,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.adminColors.error),
            ),
          ],
        ],
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

  /// 组内存在未勾选项时全选，否则清空该组。
  void _toggleModule(String module) {
    final codes =
        widget.permissions
            .where((item) => item.module == module && item.enabled)
            .map((item) => item.code)
            .toList();
    final allSelected = codes.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(codes);
      } else {
        _selected.addAll(codes);
      }
    });
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
