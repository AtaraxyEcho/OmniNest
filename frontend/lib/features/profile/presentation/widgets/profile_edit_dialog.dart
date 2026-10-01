import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

/// 编辑个人资料窗口：显示昵称 + 邮箱，保存走宿主回调（PATCH /me）。
///
/// 校验与后端一致：昵称 1-120 字符；邮箱可留空（清除）或须符合基本格式。
/// 保存失败在窗口内联提示，成功后关闭并交由宿主刷新会话资料。
class ProfileEditDialog extends StatefulWidget {
  const ProfileEditDialog({
    required this.initialDisplayName,
    required this.initialEmail,
    required this.onSave,
    super.key,
  });

  final String initialDisplayName;
  final String initialEmail;

  /// 保存资料；返回是否成功。
  final Future<bool> Function(String displayName, String email) onSave;

  /// 工位弹窗入口：焦点陷阱 / Esc 退栈 / 焦点还原由统一壳承担。
  static Future<void> show(
    BuildContext context, {
    required String initialDisplayName,
    required String initialEmail,
    required Future<bool> Function(String displayName, String email) onSave,
  }) {
    return showWorkstationDialog<void>(
      context: context,
      builder:
          (_) => ProfileEditDialog(
            initialDisplayName: initialDisplayName,
            initialEmail: initialEmail,
            onSave: onSave,
          ),
    );
  }

  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _emailController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialDisplayName,
    );
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _validateDisplayName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      return AppLocalizations.of(context).profileDisplayNameInvalid;
    }
    return null;
  }

  String? _validateEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 255 ||
        !trimmed.contains('@') ||
        trimmed.startsWith('@') ||
        trimmed.endsWith('@') ||
        trimmed.contains(' ')) {
      return AppLocalizations.of(context).profileEmailInvalid;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final displayName = _displayNameController.text.trim();
    final email = _emailController.text.trim();
    final displayNameError = _validateDisplayName(displayName);
    final emailError = _validateEmail(email);
    setState(() {
      _error = displayNameError ?? emailError;
    });
    if (displayNameError != null || emailError != null) {
      return;
    }
    setState(() => _saving = true);
    final success = await widget.onSave(displayName, email);
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = l10n.profileUpdateFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return WorkstationDialogFrame(
      title: l10n.profileEditProfileTitle,
      headerLabel: 'PROFILE',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DialogFieldLabel(l10n.profileDisplayNameLabel),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: TextField(
              controller: _displayNameController,
              autofocus: true,
              style: const TextStyle(fontSize: AppTypography.bodyMedium),
              decoration: workstationInputDecoration(
                context,
                prefixIcon: Icons.person_outline_rounded,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 14),
          _DialogFieldLabel(l10n.profileEmail),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: TextField(
              controller: _emailController,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
              ),
              decoration: workstationInputDecoration(
                context,
                prefixIcon: Icons.mail_outline_rounded,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: scheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child:
              _saving
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(l10n.profileSaveChanges),
        ),
      ],
    );
  }
}

/// 窗口内字段标签：mono 小字，与账号卡字段标签同形。
class _DialogFieldLabel extends StatelessWidget {
  const _DialogFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
