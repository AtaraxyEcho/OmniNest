part of 'admin_users_page.dart';

/// 用户编辑抽屉（样例 `AdminIdentity` 的 `Drawer`）：资料、角色、配额与状态同屏，
/// 保存时只提交真正变化的字段。
class _EditUserDrawer extends ConsumerStatefulWidget {
  const _EditUserDrawer({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_EditUserDrawer> createState() => _EditUserDrawerState();
}

class _EditUserDrawerState extends ConsumerState<_EditUserDrawer> {
  late final Set<String> _roles = {...widget.user.roles};
  late final TextEditingController _displayName = TextEditingController(
    text: widget.user.displayName ?? widget.user.username,
  );
  late final TextEditingController _account = TextEditingController(
    text: widget.user.username,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.user.email ?? '',
  );
  late final TextEditingController _quota = TextEditingController(
    text:
        widget.user.isQuotaUnlimited
            ? ''
            : _gib(widget.user.quotaBytes).toStringAsFixed(1),
  );
  late bool _enabled = widget.user.status == AdminUserStatus.active;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _account.dispose();
    _email.dispose();
    _quota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final rolesAsync = ref.watch(adminRolesProvider);
    final labels = <String, String>{
      for (final role in rolesAsync.asData?.value.roles ?? const [])
        role.code: role.name,
    };
    final selectable =
        <String>{
            for (final role in AdminRoles.allRoles)
              if (role != AdminRoles.superAdmin) role,
            ...labels.keys.where((role) => role != AdminRoles.superAdmin),
            ...widget.user.roles.where((role) => role != AdminRoles.superAdmin),
          }.toList()
          ..sort();
    return DesktopDrawerFrame(
      eyebrow: l10n.adminEditUser,
      title: widget.user.title,
      subtitle: '@${widget.user.username}',
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DesktopButton(
            label: l10n.adminCancel,
            variant: DesktopButtonVariant.ghost,
            onPressed: _saving ? null : () => closeDesktopModal(context),
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label: l10n.adminSave,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopTextField(
            controller: _displayName,
            label: l10n.adminDisplayName,
            required: true,
            maxLength: 120,
            keyName: 'admin-edit-display-name',
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _account,
            label: l10n.adminAccount,
            enabled: false,
            keyName: 'admin-edit-account',
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _email,
            label: l10n.adminEmail,
            keyboardType: TextInputType.emailAddress,
            maxLength: 255,
            keyName: 'admin-edit-email',
          ),
          const SizedBox(height: 22),
          Text(l10n.adminRole, style: DesktopType.bodyStrong(skin.text)),
          const SizedBox(height: 4),
          Text(l10n.adminEditRolesHint, style: DesktopType.caption(skin.text3)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in selectable)
                DesktopChipButton(
                  label: labels[role] ?? adminRoleDisplayName(l10n, role),
                  selected: _roles.contains(role),
                  onTap:
                      () => setState(() {
                        if (_roles.contains(role)) {
                          _roles.remove(role);
                        } else {
                          _roles.add(role);
                        }
                      }),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            l10n.adminEditQuota(widget.user.title),
            style: DesktopType.bodyStrong(skin.text),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.adminCurrentUsage(
              '${_gib(widget.user.usedBytes).toStringAsFixed(2)} GiB',
              widget.user.isQuotaUnlimited
                  ? l10n.adminUnlimited
                  : '${_gib(widget.user.quotaBytes).toStringAsFixed(1)} GiB',
            ),
            style: DesktopType.caption(skin.text3),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: DesktopTextField(
              controller: _quota,
              height: 38,
              hint: l10n.adminQuotaHint,
              keyName: 'adminUserQuota',
            ),
          ),
          const SizedBox(height: 6),
          Text(l10n.adminQuotaUnlimited, style: DesktopType.nano(skin.text3)),
          const SizedBox(height: 16),
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
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: DesktopType.caption(skin.bad)),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_roles.isEmpty) {
      setState(() => _error = l10n.adminSelectAtLeastOneRole);
      return;
    }
    if (_displayName.text.trim().isEmpty) {
      setState(() => _error = l10n.adminEnterDisplayName);
      return;
    }
    final quotaText = _quota.text.trim();
    final quotaGiB = quotaText.isEmpty ? null : double.tryParse(quotaText);
    if (quotaText.isNotEmpty &&
        (quotaGiB == null || quotaGiB < 1 || quotaGiB > 10000)) {
      setState(() => _error = l10n.adminQuotaRangeError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final controller = ref.read(adminUserControllerProvider.notifier);
    try {
      final nextDisplayName = _displayName.text.trim();
      final nextEmail = _email.text.trim();
      if (nextDisplayName !=
              (widget.user.displayName ?? widget.user.username) ||
          nextEmail != (widget.user.email ?? '')) {
        await controller.updateUserProfile(
          userId: widget.user.id,
          displayName: nextDisplayName,
          email: nextEmail.isEmpty ? null : nextEmail,
        );
      }
      if (!_setEquals(_roles, widget.user.roles)) {
        await controller.updateUserRoles(widget.user.id, _roles);
      }
      final targetBytes =
          quotaGiB == null ? null : (quotaGiB * 1024 * 1024 * 1024).round();
      if (targetBytes != null && targetBytes != widget.user.quotaBytes) {
        await controller.updateUserQuota(widget.user.id, targetBytes);
      }
      final nextStatus =
          _enabled ? AdminUserStatus.active : AdminUserStatus.disabled;
      if (nextStatus != widget.user.status) {
        await controller.updateUserStatus(widget.user.id, nextStatus);
      }
      if (mounted) {
        closeDesktopModal(context, true);
        showOmniFeedback(
          context,
          l10n.adminUserSaved,
          severity: OmniFeedbackSeverity.success,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userFacingErrorText(error, l10n: l10n);
        });
      }
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.every(b.contains);

  double _gib(int bytes) => bytes / (1024 * 1024 * 1024);
}
