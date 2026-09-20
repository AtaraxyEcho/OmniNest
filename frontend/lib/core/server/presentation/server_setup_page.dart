import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/server/server_setup_controller.dart';
import 'package:omninest/core/widgets/brand_logo.dart';

/// 首启服务器引导页：输入地址 → 探活 → 应用配置。
/// 连接成功后由路由门控自动离开本页，页面自身不做导航。
class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key});

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  final _addressController = TextEditingController();
  final _wsController = TextEditingController();
  final _webController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    _wsController.dispose();
    _webController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    ref
        .read(serverSetupControllerProvider.notifier)
        .updatePreview(
          _addressController.text,
          wsBaseUrl: _wsController.text,
          webBaseUrl: _webController.text,
        );
  }

  Future<void> _connect() {
    return ref
        .read(serverSetupControllerProvider.notifier)
        .connect(
          _addressController.text,
          wsBaseUrl: _wsController.text,
          webBaseUrl: _webController.text,
        )
        .then((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverSetupControllerProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(size: 56, radius: 16),
                const SizedBox(height: 24),
                Text(
                  l10n.serverSetupTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.serverSetupSubtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _addressController,
                  onChanged: (_) => _onInputChanged(),
                  enabled: !state.isProbing,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.url],
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.serverSetupAddressLabel,
                    hintText: l10n.serverSetupAddressHint,
                  ),
                ),
                if (state.preview != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.serverSetupWillConnect(state.preview!.apiBaseUrl),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (state.showsHttpWarning) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.serverSetupHttpWarning,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                _AdvancedFields(
                  wsController: _wsController,
                  webController: _webController,
                  enabled: !state.isProbing,
                  onChanged: _onInputChanged,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText(l10n, state.error),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      state.isProbing ? null : () => unawaited(_connect()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child:
                        state.isProbing
                            ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(l10n.serverSetupConnecting),
                              ],
                            )
                            : Text(l10n.serverSetupConnect),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _errorText(AppLocalizations l10n, ServerSetupError? error) {
    switch (error) {
      case ServerSetupError.invalidAddress:
        return l10n.serverSetupErrorInvalid;
      case ServerSetupError.httpsOnly:
        return l10n.serverSetupErrorHttpsOnly;
      case ServerSetupError.unreachable:
        return l10n.serverSetupErrorUnreachable;
      case ServerSetupError.timeout:
        return l10n.serverSetupErrorTimeout;
      case ServerSetupError.notOmniNest:
        return l10n.serverSetupErrorNotOmniNest;
      case ServerSetupError.rejected:
      case null:
        return l10n.serverSetupErrorRejected;
    }
  }
}

class _AdvancedFields extends StatelessWidget {
  const _AdvancedFields({
    required this.wsController,
    required this.webController,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController wsController;
  final TextEditingController webController;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(
        l10n.serverSetupAdvanced,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        TextField(
          controller: wsController,
          onChanged: (_) => onChanged(),
          enabled: enabled,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.serverSetupWsLabel,
            hintText: l10n.serverSetupWsHint,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: webController,
          onChanged: (_) => onChanged(),
          enabled: enabled,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.serverSetupWebLabel,
            hintText: l10n.serverSetupWebHint,
          ),
        ),
      ],
    );
  }
}
