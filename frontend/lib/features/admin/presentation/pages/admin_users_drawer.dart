part of 'admin_users_page.dart';

/// 用户编辑抽屉（样例 `AdminIdentity` 的 `Drawer`）：角色与配额同屏，
/// 保存时只提交真正变化的字段。姓名/邮箱后端没有更新接口，不摆假字段。
class _EditUserDrawer extends ConsumerStatefulWidget {
  const _EditUserDrawer({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_EditUserDrawer> createState() => _EditUserDrawerState();
}

class _EditUserDrawerState extends ConsumerState<_EditUserDrawer> {
  late final Set<String> _roles = {...widget.user.roles};
  late final TextEditingController _quota = TextEditingController(
    text:
        widget.user.isQuotaUnlimited
            ? ''
            : _gib(widget.user.quotaBytes).toStringAsFixed(1),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
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
    final quotaText = _quota.text.trim();
    final quotaGiB = quotaText.isEmpty ? null : double.tryParse(quotaText);
    if (quotaText.isNotEmpty && (quotaGiB == null || quotaGiB < 0)) {
      setState(() => _error = l10n.adminQuotaHint);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final controller = ref.read(adminUserControllerProvider.notifier);
    try {
      if (!_setEquals(_roles, widget.user.roles)) {
        await controller.updateUserRoles(widget.user.id, _roles);
      }
      final targetBytes =
          quotaGiB == null ? null : (quotaGiB * 1024 * 1024 * 1024).round();
      if (targetBytes != null && targetBytes != widget.user.quotaBytes) {
        await controller.updateUserQuota(widget.user.id, targetBytes);
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
