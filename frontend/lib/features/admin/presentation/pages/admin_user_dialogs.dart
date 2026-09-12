part of 'admin_users_page.dart';

double _dialogWidth(BuildContext context, double preferred) {
  final screenW = MediaQuery.of(context).size.width;
  return min(preferred, screenW - 48);
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
    return AlertDialog(
      title: Text(l10n.adminBatchSetStorageQuota('${selectedIds.length}')),
      content: SizedBox(
        width: _dialogWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.adminBatchQuotaHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.adminColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.adminQuotaGib,
                hintText: l10n.adminQuotaHint,
                suffixText: 'GiB',
              ),
              autofocus: true,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminUsersQuotaUpdated('$updated'))),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
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
    return AlertDialog(
      title: Text(l10n.adminEditQuota(widget.user.title)),
      content: SizedBox(
        width: _dialogWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.adminCurrentUsage(
                '${usedGiB.toStringAsFixed(2)} GiB',
                quotaText,
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.adminNewQuotaGib,
                hintText: l10n.adminQuotaHint,
                suffixText: 'GiB',
              ),
              autofocus: true,
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
        setState(() => _errorMessage = error.toString());
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
  late final Set<String> _roles =
      widget.user.roles
          .where((role) => AdminRoles.manageableRoles.contains(role))
          .toSet();
  bool _submitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminEditRoles(widget.user.title)),
      content: SizedBox(
        width: _dialogWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in AdminRoles.manageableRoles)
                  FilterChip(
                    selected: _roles.contains(role),
                    label: Text(adminRoleDisplayName(l10n, role)),
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
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = AdminRoles.member;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminCreateUser),
      content: SizedBox(
        width: _dialogWidth(context, 460),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(labelText: l10n.adminUsername),
                  validator: _requiredValidator(l10n.adminEnterUsername),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: InputDecoration(labelText: l10n.adminDisplayName),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(labelText: l10n.adminEmail),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.adminInitialPassword,
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.adminEnterInitialPassword;
                    }
                    if (value.length < 8) {
                      return l10n.adminPasswordMinChars;
                    }
                    if (value.length > 24) {
                      return l10n.adminPasswordMaxChars;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.adminRoleLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon:
              _submitting
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.person_add_alt_1_rounded),
          label: Text(_submitting ? l10n.adminCreating : l10n.adminCreate),
        ),
      ],
    );
  }

  String? Function(String?) _requiredValidator(String message) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
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
              username: _usernameController.text.trim(),
              displayName: _blankToNull(_displayNameController.text),
              email: _blankToNull(_emailController.text),
              password: _passwordController.text,
              roles: {_role},
            ),
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

Color _roleColor(String role, AdminColors adminColors) {
  return switch (role) {
    AdminRoles.superAdmin => adminColors.tertiary,
    AdminRoles.admin => adminColors.info,
    AdminRoles.member => adminColors.primary,
    AdminRoles.guest => adminColors.success,
    _ => adminColors.onSurfaceVariant,
  };
}
