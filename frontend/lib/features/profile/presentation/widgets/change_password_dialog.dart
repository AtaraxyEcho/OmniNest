import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

/// 修改密码工位窗口：直角表单 + 焦点陷阱，成功/失败经 OmniFeedback 反馈。
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  /// 工位弹窗入口：Esc 退栈 / 焦点陷阱 / 焦点还原由统一壳承担。
  static Future<void> show(BuildContext context) {
    return showWorkstationDialog<void>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

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
    return WorkstationDialogFrame(
      title: l10n.profileChangePassword,
      headerLabel: 'PASSWORD',
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildField(
              controller: _oldController,
              label: l10n.changePasswordOldPassword,
              prefixIcon: Icons.lock_outline_rounded,
              obscure: _obscureOld,
              onToggle: () => setState(() => _obscureOld = !_obscureOld),
            ),
            const SizedBox(height: 14),
            _buildField(
              controller: _newController,
              label: l10n.changePasswordNewPassword,
              prefixIcon: Icons.vpn_key_outlined,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.changePasswordEnterNew;
                if (v.length < 8) return l10n.changePasswordMinLength;
                if (v.length > 24) return l10n.changePasswordMaxLength;
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildField(
              controller: _confirmController,
              label: l10n.changePasswordConfirmNew,
              prefixIcon: Icons.vpn_key_outlined,
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
                  ? const SizedBox.square(
                    dimension: 16,
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
    required IconData prefixIcon,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
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
          style: const TextStyle(fontSize: AppTypography.bodyMedium),
          decoration: workstationInputDecoration(
            context,
            prefixIcon: prefixIcon,
          ).copyWith(
            suffixIcon: IconButton(
              tooltip: obscure ? l10n.coreShowPassword : l10n.coreHidePassword,
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 16,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
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
        showOmniFeedback(
          context,
          l10n.changePasswordSuccess,
          severity: OmniFeedbackSeverity.success,
        );
      }
    } catch (e) {
      if (mounted) {
        final code = describeUserFacingError(e).code;
        final message =
            code == AppErrorCodes.oldPasswordInvalid
                ? l10n.changePasswordWrongOld
                : l10n.changePasswordFailed;
        showOmniFeedback(context, message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
