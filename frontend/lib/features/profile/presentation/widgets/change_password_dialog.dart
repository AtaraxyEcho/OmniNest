import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';

/// 修改密码对话框。
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return AlertDialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Text(
            l10n.profileChangePassword,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField(
              controller: _oldController,
              label: l10n.changePasswordOldPassword,
              obscure: _obscureOld,
              onToggle: () => setState(() => _obscureOld = !_obscureOld),
            ),
            const SizedBox(height: 14),
            _buildField(
              controller: _newController,
              label: l10n.changePasswordNewPassword,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.changePasswordEnterNew;
                if (v.length < 6) return l10n.changePasswordMinLength;
                if (v.length > 128) return l10n.changePasswordMaxLength;
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildField(
              controller: _confirmController,
              label: l10n.changePasswordConfirmNew,
              obscure: _obscureConfirm,
              onToggle:
                  () => setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) {
                if (v != _newController.text) {
                  return l10n.changePasswordMismatch;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.changePasswordCancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child:
              _loading
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(l10n.changePasswordConfirm),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator:
          validator ??
          (v) {
            if (v == null || v.isEmpty) {
              return l10n.changePasswordEnterField(label);
            }
            return null;
          },
      style: const TextStyle(fontSize: AppTypography.bodyLarge),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: AppTypography.bodyMedium),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          tooltip:
              obscure
                  ? AppLocalizations.of(context).coreShowPassword
                  : AppLocalizations.of(context).coreHidePassword,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      await ref
          .read(profileCommandServiceProvider)
          .changePassword(
            oldPassword: _oldController.text,
            newPassword: _newController.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.changePasswordSuccess)));
      }
    } catch (e) {
      if (mounted) {
        final message =
            e.toString().contains('原密码错误')
                ? l10n.changePasswordWrongOld
                : l10n.changePasswordFailed;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
