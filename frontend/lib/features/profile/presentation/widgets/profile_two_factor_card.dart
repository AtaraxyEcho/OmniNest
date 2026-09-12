import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:qr_flutter/qr_flutter.dart';

final profileTwoFactorStatusProvider =
    FutureProvider.autoDispose<TwoFactorStatusData>(
      (ref) => ref.watch(meApiProvider).twoFactorStatus(),
    );

/// 个人资料安全分区的两步验证管理卡：状态展示、自助开启向导、密码复核关闭。
class ProfileTwoFactorCard extends ConsumerWidget {
  const ProfileTwoFactorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(profileTwoFactorStatusProvider);
    return status.when(
      loading:
          () => const WorkbenchPanel(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      error:
          (_, _) => WorkbenchPanel(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.error_outline_rounded),
              title: Text(l10n.profileTwoFactorTitle),
              subtitle: Text(l10n.profileTwoFactorLoadFailed),
              trailing: IconButton(
                tooltip: l10n.coreRetry,
                onPressed: () => ref.invalidate(profileTwoFactorStatusProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
      data:
          (value) => WorkbenchPanel(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              leading: Icon(
                value.enabled
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
                color:
                    value.enabled
                        ? Theme.of(context).colorScheme.primary
                        : null,
              ),
              title: Text(l10n.profileTwoFactorTitle),
              subtitle: Text(
                value.enabled
                    ? l10n.profileTwoFactorEnabled
                    : (value.required
                        ? l10n.profileTwoFactorRequiredBadge
                        : l10n.profileTwoFactorDisabled),
              ),
              trailing:
                  value.enabled
                      ? OutlinedButton(
                        onPressed: () => _showDisableDialog(context, ref),
                        child: Text(l10n.profileTwoFactorDisableAction),
                      )
                      : FilledButton.tonal(
                        onPressed: () => _showEnableDialog(context, ref),
                        child: Text(l10n.profileTwoFactorEnableAction),
                      ),
            ),
          ),
    );
  }

  Future<void> _showEnableDialog(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TwoFactorEnableDialog(),
    );
  }

  Future<void> _showDisableDialog(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _TwoFactorDisableDialog(),
    );
  }
}

enum _EnableStep { password, scan, codes }

class _TwoFactorEnableDialog extends ConsumerStatefulWidget {
  const _TwoFactorEnableDialog();

  @override
  ConsumerState<_TwoFactorEnableDialog> createState() =>
      _TwoFactorEnableDialogState();
}

class _TwoFactorEnableDialogState
    extends ConsumerState<_TwoFactorEnableDialog> {
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  _EnableStep _step = _EnableStep.password;
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _codesSaved = false;
  String? _error;
  TwoFactorSetupData? _setup;
  List<String> _codes = const [];

  @override
  void dispose() {
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.profileTwoFactorTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              switch (_step) {
                _EnableStep.password => TextFormField(
                  key: const Key('profileTwoFactorPasswordField'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.twoFactorEnrollPasswordLabel,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: l10n.loginShowPassword,
                      onPressed:
                          () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                _EnableStep.scan => _buildScanStep(l10n),
                _EnableStep.codes => _buildCodesStep(l10n),
              },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        if (_step == _EnableStep.password)
          FilledButton(
            key: const Key('profileTwoFactorNextButton'),
            onPressed: _submitting ? null : _submitPassword,
            child: Text(l10n.twoFactorEnrollContinue),
          ),
        if (_step == _EnableStep.scan)
          FilledButton(
            key: const Key('profileTwoFactorEnableButton'),
            onPressed: _submitting ? null : _submitCode,
            child: Text(l10n.twoFactorEnrollConfirmCode),
          ),
        if (_step == _EnableStep.codes)
          FilledButton(
            key: const Key('profileTwoFactorDoneButton'),
            onPressed: (_submitting || !_codesSaved) ? null : _finish,
            child: Text(l10n.twoFactorEnrollSavedAndFinish),
          ),
      ],
    );
  }

  Widget _buildScanStep(AppLocalizations l10n) {
    final setup = _setup;
    if (setup == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(data: setup.otpauthUri, size: 168),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.twoFactorEnrollScanHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _copy(setup.secret, l10n),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(l10n.twoFactorEnrollSecretLabel),
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('profileTwoFactorCodeField'),
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: l10n.loginTwoFactorCodeLabel,
            hintText: l10n.loginTwoFactorCodeHint,
            prefixIcon: const Icon(Icons.pin_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildCodesStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.twoFactorEnrollBackupTitle),
        const SizedBox(height: 6),
        Text(l10n.twoFactorEnrollBackupHint),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final code in _codes) SelectableText(code)],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _copy(_codes.join('\n'), l10n),
          icon: const Icon(Icons.copy_all_rounded, size: 18),
          label: Text(l10n.twoFactorCopyCodes),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _codesSaved,
          onChanged: (value) => setState(() => _codesSaved = value ?? false),
          title: Text(l10n.twoFactorEnrollBackupSavedCheck),
        ),
      ],
    );
  }

  Future<void> _submitPassword() async {
    await _run(() async {
      _setup = await ref
          .read(meApiProvider)
          .twoFactorSetup(password: _passwordController.text);
      setState(() => _step = _EnableStep.scan);
    });
  }

  Future<void> _submitCode() async {
    await _run(() async {
      _codes = await ref
          .read(meApiProvider)
          .twoFactorEnable(code: _codeController.text.trim());
      setState(() => _step = _EnableStep.codes);
    });
  }

  Future<void> _finish() async {
    ref.invalidate(profileTwoFactorStatusProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _copy(String value, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.twoFactorCopied)));
    }
  }
}

class _TwoFactorDisableDialog extends ConsumerStatefulWidget {
  const _TwoFactorDisableDialog();

  @override
  ConsumerState<_TwoFactorDisableDialog> createState() =>
      _TwoFactorDisableDialogState();
}

class _TwoFactorDisableDialogState
    extends ConsumerState<_TwoFactorDisableDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.profileTwoFactorDisableAction),
      content: SizedBox(
        width: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.twoFactorDisableHint),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('profileTwoFactorDisablePasswordField'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.twoFactorEnrollPasswordLabel,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: l10n.loginShowPassword,
                  onPressed:
                      () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          key: const Key('profileTwoFactorDisableButton'),
          onPressed: _submitting ? null : _submit,
          child: Text(l10n.profileTwoFactorDisableConfirm),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(meApiProvider)
          .twoFactorDisable(password: _passwordController.text);
      ref.invalidate(profileTwoFactorStatusProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
