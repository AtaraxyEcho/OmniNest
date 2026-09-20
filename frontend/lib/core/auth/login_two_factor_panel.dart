import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';

/// 登录页两步验证面板：已启用用户输入验证码/备份码，强制角色未注册走注册引导向导。
class LoginTwoFactorPanel extends ConsumerStatefulWidget {
  const LoginTwoFactorPanel({
    required this.challenge,
    required this.onLoginSucceeded,
    required this.onBackToLogin,
    super.key,
  });

  final AuthChallenge challenge;
  final VoidCallback onLoginSucceeded;
  final VoidCallback onBackToLogin;

  @override
  ConsumerState<LoginTwoFactorPanel> createState() =>
      _LoginTwoFactorPanelState();
}

enum _EnrollStep { password, scan, codes }

class _LoginTwoFactorPanelState extends ConsumerState<LoginTwoFactorPanel> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _codesSaved = false;
  String? _errorMessage;
  _EnrollStep _enrollStep = _EnrollStep.password;
  TwoFactorSetupData? _setupData;
  TwoFactorBootstrapEnableData? _enableData;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(28),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.challenge.isEnrollment
                ? l10n.twoFactorEnrollTitle
                : l10n.loginTwoFactorTitle,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.challenge.isEnrollment
                ? l10n.twoFactorEnrollSubtitle
                : l10n.loginTwoFactorSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (widget.challenge.isEnrollment)
            switch (_enrollStep) {
              _EnrollStep.password => _buildEnrollPasswordStep(l10n),
              _EnrollStep.scan => _buildEnrollScanStep(l10n),
              _EnrollStep.codes => _buildEnrollCodesStep(l10n),
            }
          else
            ..._buildVerifyFields(l10n),
          if (_errorMessage != null) ...[
            const SizedBox(height: 18),
            _ErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _submitting ? null : widget.onBackToLogin,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(l10n.loginTwoFactorBackToLogin),
          ),
        ],
      ),
    );
  }

  // ── 已启用：验证码登录 ──

  List<Widget> _buildVerifyFields(AppLocalizations l10n) {
    return [
      TextFormField(
        key: const Key('twoFactorCodeField'),
        controller: _codeController,
        autofocus: true,
        keyboardType: TextInputType.text,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z\-]')),
        ],
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submitVerifyCode(),
        decoration: InputDecoration(
          labelText: l10n.loginTwoFactorCodeLabel,
          hintText: l10n.loginTwoFactorCodeHint,
          prefixIcon: const Icon(Icons.pin_outlined),
        ),
        validator: (value) {
          final cleaned = (value ?? '').trim();
          if (cleaned.length < 6) {
            return l10n.loginTwoFactorCodeHint;
          }
          return null;
        },
      ),
      const SizedBox(height: 10),
      Text(
        l10n.loginTwoFactorUseBackupHint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        key: const Key('twoFactorVerifyButton'),
        onPressed: _submitting ? null : _submitVerifyCode,
        icon:
            _submitting
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.verified_outlined),
        label: Text(l10n.loginTwoFactorVerifyAndSignIn),
      ),
    ];
  }

  Future<void> _submitVerifyCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(
        () =>
            _errorMessage = AppLocalizations.of(context).loginTwoFactorCodeHint,
      );
      return;
    }
    await _run(
      () => ref
          .read(authSessionProvider.notifier)
          .signInWithTwoFactor(
            challengeToken: widget.challenge.challengeToken,
            code: code,
          ),
      widget.onLoginSucceeded,
    );
  }

  // ── 强制角色：注册引导 ──

  Widget _buildEnrollPasswordStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('twoFactorEnrollPasswordField'),
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.twoFactorEnrollPasswordLabel,
            hintText: l10n.twoFactorEnrollPasswordHint,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip:
                  _obscurePassword
                      ? l10n.loginShowPassword
                      : l10n.loginHidePassword,
              onPressed:
                  () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('twoFactorEnrollContinueButton'),
          onPressed: _submitting ? null : _submitEnrollPassword,
          icon:
              _submitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.qr_code_rounded),
          label: Text(l10n.twoFactorEnrollContinue),
        ),
      ],
    );
  }

  Future<void> _submitEnrollPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(
        () =>
            _errorMessage =
                AppLocalizations.of(context).twoFactorEnrollPasswordHint,
      );
      return;
    }
    await _run(() async {
      _setupData = await ref
          .read(authClientProvider)
          .bootstrapTwoFactorSetup(
            challengeToken: widget.challenge.challengeToken,
            password: password,
          );
      setState(() => _enrollStep = _EnrollStep.scan);
    });
  }

  Widget _buildEnrollScanStep(AppLocalizations l10n) {
    final setup = _setupData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (setup != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                key: const Key('twoFactorEnrollQr'),
                data: setup.otpauthUri,
                size: 176,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.twoFactorEnrollScanHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _copyToClipboard(setup.secret, l10n),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l10n.twoFactorEnrollSecretLabel),
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('twoFactorEnrollCodeField'),
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitEnrollCode(),
            decoration: InputDecoration(
              labelText: l10n.loginTwoFactorCodeLabel,
              hintText: l10n.loginTwoFactorCodeHint,
              prefixIcon: const Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('twoFactorEnrollConfirmButton'),
            onPressed: _submitting ? null : _submitEnrollCode,
            icon:
                _submitting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.check_rounded),
            label: Text(l10n.twoFactorEnrollConfirmCode),
          ),
        ],
      ],
    );
  }

  Future<void> _submitEnrollCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(
        () =>
            _errorMessage = AppLocalizations.of(context).loginTwoFactorCodeHint,
      );
      return;
    }
    await _run(() async {
      _enableData = await ref
          .read(authClientProvider)
          .bootstrapTwoFactorEnable(
            challengeToken: widget.challenge.challengeToken,
            code: code,
          );
      setState(() => _enrollStep = _EnrollStep.codes);
    });
  }

  Widget _buildEnrollCodesStep(AppLocalizations l10n) {
    final enableData = _enableData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (enableData != null) ...[
          Text(
            l10n.twoFactorEnrollBackupTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.twoFactorEnrollBackupHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in enableData.backupCodes)
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                () => _copyToClipboard(enableData.backupCodes.join('\n'), l10n),
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: Text(l10n.twoFactorCopyCodes),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const Key('twoFactorCodesSavedCheck'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _codesSaved,
            onChanged: (value) => setState(() => _codesSaved = value ?? false),
            title: Text(l10n.twoFactorEnrollBackupSavedCheck),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('twoFactorEnrollFinishButton'),
            onPressed:
                (_submitting || !_codesSaved) ? null : _submitEnrollFinish,
            icon:
                _submitting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.login_rounded),
            label: Text(l10n.twoFactorEnrollSavedAndFinish),
          ),
        ],
      ],
    );
  }

  Future<void> _submitEnrollFinish() async {
    final enableData = _enableData;
    if (enableData == null) {
      return;
    }
    await _run(
      () => ref
          .read(authSessionProvider.notifier)
          .completeTwoFactorEnrollment(finalizeToken: enableData.finalizeToken),
      widget.onLoginSucceeded,
    );
  }

  // ── 公共 ──

  Future<void> _run(
    Future<void> Function() action, [
    VoidCallback? onDone,
  ]) async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await action();
      if (onDone != null) {
        onDone();
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

  Future<void> _copyToClipboard(String value, AppLocalizations l10n) async {
    final copied = await copyTextToClipboard(value);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copied ? l10n.twoFactorCopied : l10n.clipboardCopyFailed),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
