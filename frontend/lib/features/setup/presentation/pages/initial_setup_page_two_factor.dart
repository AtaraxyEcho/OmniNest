part of 'initial_setup_page.dart';

/// 安装向导的两步验证分区：生成秘钥（QR/手输）、确认码与一次性备份码面板。
///
/// 这些构件只读 `_totpSetup`/`_totpLoading` 等瞬时状态并回写表单控制器，
/// 与账户表单本身的校验流程互不依赖，因此从页面主体拆出。
extension _InitialSetupPageTwoFactor on _InitialSetupPageState {
  List<Widget> _twoFactorSection(AppLocalizations l10n) {
    final setup = _totpSetup;
    return [
      const SizedBox(height: 6),
      _sectionHeader(
        context,
        l10n.setupTwoFactorSection,
        Icons.phonelink_lock_outlined,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.setupTwoFactorHint,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      if (setup == null)
        FilledButton.tonalIcon(
          key: const Key('setupTwoFactorGenerateButton'),
          onPressed: _totpLoading ? null : _fetchTotpSecret,
          icon:
              _totpLoading
                  ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.qr_code_rounded),
          label: Text(l10n.setupTwoFactorGenerate),
        )
      else ...[
        Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
              key: const Key('setupTwoFactorQr'),
              data: setup.otpauthUri,
              size: 168,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.twoFactorEnrollScanHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final copied = await copyTextToClipboard(setup.secret);
            if (!mounted) return;
            showOmniFeedback(
              context,
              copied ? l10n.twoFactorCopied : l10n.clipboardCopyFailed,
              severity:
                  copied
                      ? OmniFeedbackSeverity.success
                      : OmniFeedbackSeverity.error,
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(l10n.twoFactorEnrollSecretLabel),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _totpLoading ? null : _fetchTotpSecret,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(l10n.setupTwoFactorRegenerate),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('setupTwoFactorCodeField'),
          controller: _totpCodeController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: l10n.loginTwoFactorCodeLabel,
            hintText: l10n.loginTwoFactorCodeHint,
            prefixIcon: const Icon(Icons.pin_outlined),
          ),
          validator: (value) {
            if (value == null || value.trim().length != 6) {
              return l10n.loginTwoFactorCodeHint;
            }
            return null;
          },
        ),
      ],
    ];
  }

  /// 备份码确认面板：安装启用两步验证后的一次性备份码展示与保存确认。
  Widget _backupCodesPanel(BuildContext context, List<String> codes) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: WorkbenchPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.twoFactorEnrollBackupTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.twoFactorEnrollBackupHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [for (final code in codes) SelectableText(code)],
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final copied = await copyTextToClipboard(codes.join('\n'));
                    if (!context.mounted) {
                      return;
                    }
                    showOmniFeedback(
                      context,
                      copied ? l10n.twoFactorCopied : l10n.clipboardCopyFailed,
                      severity:
                          copied
                              ? OmniFeedbackSeverity.success
                              : OmniFeedbackSeverity.error,
                    );
                  },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: Text(l10n.twoFactorCopyCodes),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  key: const Key('setupBackupCodesSavedCheck'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _codesSaved,
                  onChanged:
                      (value) =>
                          _updateState(() => _codesSaved = value ?? false),
                  title: Text(l10n.twoFactorEnrollBackupSavedCheck),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('setupBackupCodesDoneButton'),
                  onPressed: _codesSaved ? _finishBackupCodes : null,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(l10n.setupTwoFactorGoLogin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
