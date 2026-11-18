part of 'admin_users_page.dart';

Widget _adminQuotaInput(
  BuildContext context, {
  required TextEditingController controller,
  required String label,
  required String hint,
  bool autofocus = false,
}) {
  const keyboardType = TextInputType.numberWithOptions(decimal: true);
  if (Theme.of(context).extension<DesktopSkin>() != null) {
    return DesktopTextField(
      controller: controller,
      label: label,
      hint: hint,
      autofocus: autofocus,
      keyboardType: keyboardType,
      trailing: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          'GiB',
          style: DesktopType.caption(DesktopSkin.of(context).text3),
        ),
      ),
    );
  }
  return TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: 'GiB',
    ),
  );
}

class _BatchQuotaDialog extends ConsumerStatefulWidget {
  const _BatchQuotaDialog();

  @override
  ConsumerState<_BatchQuotaDialog> createState() => _BatchQuotaDialogState();
}

class _BatchQuotaDialogState extends ConsumerState<_BatchQuotaDialog> {
  late final TextEditingController _controller;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '10.0');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedIds =
        ref.watch(adminUserControllerProvider).value?.selectedIds ?? {};
    return WorkstationDialogFrame(
      title: l10n.adminBatchSetStorageQuota('${selectedIds.length}'),
      width: 460,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.adminBatchQuotaHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.adminColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _adminQuotaInput(
            context,
            controller: _controller,
            label: l10n.adminQuotaGib,
            hint: l10n.adminQuotaHint,
            autofocus: true,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final gibValue = double.tryParse(_controller.text.trim());
    if (gibValue == null || gibValue < 0) {
      setState(() => _errorMessage = l10n.adminValidQuotaRequired);
      return;
    }
    final quotaBytes = (gibValue * 1024 * 1024 * 1024).round();
    final selectedIds =
        ref.read(adminUserControllerProvider).value?.selectedIds ?? {};
    if (selectedIds.isEmpty) {
      setState(() => _errorMessage = l10n.adminNoUsersSelected);
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final userController = ref.read(adminUserControllerProvider.notifier);
    try {
      final updated = await userController.batchUpdateQuota(
        selectedIds.toList(),
        quotaBytes,
      );
      userController.clearSelection();
      if (mounted) {
        Navigator.of(context).pop();
        showOmniFeedback(
          context,
          l10n.adminUsersQuotaUpdated('$updated'),
          severity: OmniFeedbackSeverity.success,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = userFacingErrorText(error, l10n: l10n));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _EditQuotaDialog extends ConsumerStatefulWidget {
  const _EditQuotaDialog({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_EditQuotaDialog> createState() => _EditQuotaDialogState();
}

class _EditQuotaDialogState extends ConsumerState<_EditQuotaDialog> {
  late final TextEditingController _controller;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text:
          widget.user.isQuotaUnlimited
              ? ''
              : _bytesToGiB(widget.user.quotaBytes).toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final usedGiB = _bytesToGiB(widget.user.usedBytes);
    final quotaText =
        widget.user.isQuotaUnlimited
            ? l10n.adminUnlimited
            : '${_bytesToGiB(widget.user.quotaBytes).toStringAsFixed(1)} GiB';
    return WorkstationDialogFrame(
      title: l10n.adminEditQuota(widget.user.title),
      width: 460,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.adminCurrentUsage(
              '${usedGiB.toStringAsFixed(2)} GiB',
              quotaText,
            ),
          ),
          const SizedBox(height: 16),
          _adminQuotaInput(
            context,
            controller: _controller,
            label: l10n.adminNewQuotaGib,
            hint: l10n.adminQuotaHint,
            autofocus: true,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final gibValue = double.tryParse(_controller.text.trim());
    if (gibValue == null || gibValue < 0) {
      setState(() => _errorMessage = l10n.adminValidQuotaRequired);
      return;
    }
    final quotaBytes = (gibValue * 1024 * 1024 * 1024).round();
    if (quotaBytes < widget.user.usedBytes) {
      setState(
        () =>
            _errorMessage = l10n.adminQuotaMinError(
              _bytesToGiB(widget.user.usedBytes).toStringAsFixed(2),
            ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(adminUserControllerProvider.notifier)
          .updateUserQuota(widget.user.id, quotaBytes);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = userFacingErrorText(error, l10n: l10n));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  double _bytesToGiB(int bytes) => bytes / (1024 * 1024 * 1024);
}

class _EditUserRolesDialog extends ConsumerStatefulWidget {
  const _EditUserRolesDialog({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_EditUserRolesDialog> createState() =>
      _EditUserRolesDialogState();
}

class _EditUserRolesDialogState extends ConsumerState<_EditUserRolesDialog> {
  /// 完整保留用户现有角色（含自定义角色）：旧实现先按内置清单过滤，
  /// 保存时会把 FAMILY_MEMBER/AUDITOR 之一静默清空。
  late final Set<String> _roles = {...widget.user.roles};
  bool _submitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rolesAsync = ref.watch(adminRolesProvider);
    final roleLabels = <String, String>{};
    for (final role in rolesAsync.asData?.value.roles ?? const []) {
      roleLabels[role.code] = role.name;
    }
    // 角色清单加载中/失败时退回“内置角色 + 用户已有角色”，保证任何情况下都能保存。
    final selectableRoles =
        <String>{
            for (final role in AdminRoles.allRoles)
              if (role != AdminRoles.superAdmin) role,
            ...roleLabels.keys.where((role) => role != AdminRoles.superAdmin),
            ...widget.user.roles.where((role) => role != AdminRoles.superAdmin),
            ..._roles.where((role) => role != AdminRoles.superAdmin),
          }.toList()
          ..sort();
    return WorkstationDialogFrame(
      title: l10n.adminEditRoles(widget.user.title),
      width: 460,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.adminEditRolesHint),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in selectableRoles)
                FilterChip(
                  selected: _roles.contains(role),
                  label: Text(
                    roleLabels[role] ?? adminRoleDisplayName(l10n, role),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _roles.add(role);
                      } else {
                        _roles.remove(role);
                      }
                    });
                  },
                ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (_roles.isEmpty) {
      setState(() => _errorMessage = l10n.adminSelectAtLeastOneRole);
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(adminUserControllerProvider.notifier)
          .updateUserRoles(widget.user.id, _roles);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = userFacingErrorText(error, l10n: l10n));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

/// 移动管理页沿用全屏宽度的表单对话框；桌面入口使用右侧抽屉。
class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = AdminRoles.member;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkstationDialogFrame(
      title: l10n.adminCreateUser,
      width: 480,
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _username,
              decoration: InputDecoration(labelText: l10n.adminUsername),
              validator:
                  (value) =>
                      value == null || value.trim().isEmpty
                          ? l10n.adminEnterUsername
                          : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _displayName,
              decoration: InputDecoration(labelText: l10n.adminDisplayName),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: l10n.adminEmail),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(labelText: l10n.adminInitialPassword),
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.adminEnterInitialPassword;
                }
                if (value.length < 8) return l10n.adminPasswordMinChars;
                if (value.length > 64) return l10n.adminPasswordMaxChars;
                return null;
              },
            ),
            const SizedBox(height: 18),
            WorkstationDialogSectionLabel(l10n.adminRoleLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in AdminRoles.manageableRoles)
                  ChoiceChip(
                    selected: _role == role,
                    label: Text(adminRoleDisplayName(l10n, role)),
                    onSelected: (_) => setState(() => _role = role),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
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
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? l10n.adminCreating : l10n.adminCreate),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(adminUserControllerProvider.notifier)
          .createUser(
            AdminCreateUserInput(
              username: _username.text.trim(),
              displayName: _nullable(_displayName.text),
              email: _nullable(_email.text),
              password: _password.text,
              roles: {_role},
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingErrorText(error, l10n: l10n));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
}

class _CreateUserDrawer extends ConsumerStatefulWidget {
  const _CreateUserDrawer();

  @override
  ConsumerState<_CreateUserDrawer> createState() => _CreateUserDrawerState();
}

class _CreateUserDrawerState extends ConsumerState<_CreateUserDrawer> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _quotaController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = AdminRoles.member;
  bool _enabled = true;
  bool _requirePasswordChange = true;
  bool _showPassword = false;
  bool _submitting = false;
  bool _quotaInitialized = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _quotaController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final configState = ref.watch(adminConfigsProvider);
    if (!_quotaInitialized && configState.asData != null) {
      final defaultValue =
          configState.asData!.value.items
              .where((entry) => entry.key == 'storage.quota.default')
              .firstOrNull
              ?.value;
      final defaultGiB = int.tryParse(defaultValue ?? '10');
      if (defaultGiB != null && defaultGiB >= 1 && defaultGiB <= 10000) {
        _quotaController.text = '$defaultGiB';
      }
      _quotaInitialized = true;
    }
    final rolesAsync = ref.watch(adminRolesProvider);
    final availableRoles =
        rolesAsync.asData?.value.roles
            .where((role) => role.enabled && role.code != AdminRoles.superAdmin)
            .toList() ??
        const <AdminRoleDetail>[];
    final roleCodes =
        availableRoles.isEmpty
            ? AdminRoles.manageableRoles
            : availableRoles.map((role) => role.code).toList();
    if (!roleCodes.contains(_role) && roleCodes.isNotEmpty) {
      _role = roleCodes.first;
    }
    final selectedRole =
        availableRoles.where((role) => role.code == _role).firstOrNull;
    final accountText = _usernameController.text.trim();
    final accountValid = RegExp(
      r'^[a-z][a-z0-9._-]{2,23}$',
    ).hasMatch(accountText.toLowerCase());
    return DesktopDrawerFrame(
      eyebrow: l10n.adminCreateAccountEyebrow,
      title: l10n.adminCreateUser,
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DesktopButton(
            label: l10n.coreCancel,
            variant: DesktopButtonVariant.ghost,
            onPressed: _submitting ? null : () => closeDesktopModal(context),
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label: l10n.adminCreateUser,
            icon: DesktopIcons.plus,
            variant: DesktopButtonVariant.primary,
            busy: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopTextField(
            controller: _displayNameController,
            label: l10n.adminDisplayName,
            required: true,
            maxLength: 120,
            keyName: 'admin-create-display-name',
            error:
                _displayNameController.text.trim().isEmpty &&
                        _errorMessage == l10n.adminEnterDisplayName
                    ? l10n.adminEnterDisplayName
                    : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _usernameController,
            label: l10n.adminAccount,
            required: true,
            maxLength: 24,
            keyName: 'admin-create-username',
            error:
                _errorMessage == l10n.adminEnterUsername
                    ? l10n.adminEnterUsername
                    : accountText.isNotEmpty && !accountValid
                    ? l10n.adminAccountFormatError
                    : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _emailController,
            label: l10n.adminEmail,
            keyboardType: TextInputType.emailAddress,
            maxLength: 255,
            keyName: 'admin-create-email',
          ),
          const SizedBox(height: 14),
          Text(l10n.adminRoleLabel, style: DesktopType.bodyStrong(skin.text)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final role in roleCodes)
                DesktopChipButton(
                  label:
                      availableRoles
                          .where((item) => item.code == role)
                          .firstOrNull
                          ?.name ??
                      adminRoleDisplayName(l10n, role),
                  selected: _role == role,
                  onTap: () => setState(() => _role = role),
                ),
            ],
          ),
          if (selectedRole != null && selectedRole.description.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              selectedRole.description,
              style: DesktopType.caption(skin.text3),
            ),
          ],
          const SizedBox(height: 20),
          DesktopTextField(
            controller: _quotaController,
            label: l10n.adminQuotaGib,
            hint: l10n.adminQuotaHint,
            helper: l10n.adminQuotaDefaultHint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            keyName: 'admin-create-quota',
            error:
                _errorMessage == l10n.adminQuotaRangeError
                    ? _errorMessage
                    : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.adminInitialPassword,
            style: DesktopType.caption(skin.text),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DesktopTextField(
                  controller: _passwordController,
                  obscure: !_showPassword,
                  maxLength: 64,
                  keyName: 'admin-create-password',
                  error:
                      _errorMessage == l10n.adminEnterInitialPassword ||
                              _errorMessage == l10n.adminPasswordMinChars ||
                              _errorMessage == l10n.adminPasswordMaxChars
                          ? _errorMessage
                          : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 7),
              DesktopButton(
                label:
                    _showPassword
                        ? l10n.adminHidePassword
                        : l10n.adminShowPassword,
                variant: DesktopButtonVariant.soft,
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              const SizedBox(width: 6),
              DesktopButton(
                label: l10n.adminGeneratePassword,
                icon: DesktopIcons.retry,
                variant: DesktopButtonVariant.soft,
                onPressed: _generatePassword,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            l10n.adminPasswordShareHint,
            style: DesktopType.caption(skin.text3),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: skin.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.adminRequirePasswordChangeLabel,
                        style: DesktopType.rowTitle(skin.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.adminRequirePasswordChangeHint,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ),
                ),
                DesktopToggle(
                  value: _requirePasswordChange,
                  label: l10n.adminRequirePasswordChangeLabel,
                  onChanged:
                      (value) => setState(() => _requirePasswordChange = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: skin.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.adminAccountEnabled,
                        style: DesktopType.rowTitle(skin.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.adminDisabledAccountsCannotSignIn,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ),
                ),
                DesktopToggle(
                  value: _enabled,
                  label: l10n.adminAccountEnabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),
          if (_errorMessage != null &&
              _errorMessage != l10n.adminEnterUsername &&
              _errorMessage != l10n.adminEnterDisplayName &&
              _errorMessage != l10n.adminAccountFormatError &&
              _errorMessage != l10n.adminQuotaRangeError &&
              _errorMessage != l10n.adminEnterInitialPassword &&
              _errorMessage != l10n.adminPasswordMinChars &&
              _errorMessage != l10n.adminPasswordMaxChars) ...[
            const SizedBox(height: 14),
            Text(_errorMessage!, style: DesktopType.caption(skin.bad)),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();
    final account = _usernameController.text.trim().toLowerCase();
    final quotaText = _quotaController.text.trim();
    final quotaGiB = quotaText.isEmpty ? null : double.tryParse(quotaText);
    if (displayName.isEmpty) {
      setState(() => _errorMessage = l10n.adminEnterDisplayName);
      return;
    }
    if (_usernameController.text.trim().isEmpty) {
      setState(() => _errorMessage = l10n.adminEnterUsername);
      return;
    }
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,23}$').hasMatch(account)) {
      setState(() => _errorMessage = l10n.adminAccountFormatError);
      return;
    }
    if (quotaText.isNotEmpty &&
        (quotaGiB == null || quotaGiB < 1 || quotaGiB > 10000)) {
      setState(() => _errorMessage = l10n.adminQuotaRangeError);
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = l10n.adminEnterInitialPassword);
      return;
    }
    if (password.length < 8) {
      setState(() => _errorMessage = l10n.adminPasswordMinChars);
      return;
    }
    if (password.length > 64) {
      setState(() => _errorMessage = l10n.adminPasswordMaxChars);
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(adminUserControllerProvider.notifier)
          .createUser(
            AdminCreateUserInput(
              username: account,
              displayName: displayName,
              email: _blankToNull(_emailController.text),
              password: _passwordController.text,
              roles: {_role},
              quotaBytes:
                  quotaGiB == null
                      ? null
                      : (quotaGiB * 1024 * 1024 * 1024).round(),
              status:
                  _enabled ? AdminUserStatus.active : AdminUserStatus.disabled,
              requirePasswordChange: _requirePasswordChange,
            ),
          );
      if (mounted) {
        closeDesktopModal(context, true);
        showOmniFeedback(
          context,
          l10n.adminUserCreated,
          severity: OmniFeedbackSeverity.success,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = userFacingErrorText(error, l10n: l10n));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _generatePassword() {
    const alphabet =
        'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%';
    final random = Random.secure();
    setState(() {
      _passwordController.text =
          List.generate(
            16,
            (_) => alphabet[random.nextInt(alphabet.length)],
          ).join();
      _showPassword = true;
      _errorMessage = null;
    });
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
