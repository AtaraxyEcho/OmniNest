import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/version/app_version_api.dart';
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/errors/error_message.dart';

class ProfileSecurityActionsPanel extends StatelessWidget {
  const ProfileSecurityActionsPanel({
    required this.onChangePassword,
    super.key,
  });

  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(12),
      child: ListTile(
        leading: const Icon(Icons.lock_outline_rounded),
        title: Text(l10n.profileChangePassword),
        subtitle: Text(l10n.profileChangePasswordSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onChangePassword,
      ),
    );
  }
}

class ProfileAboutPanel extends ConsumerStatefulWidget {
  const ProfileAboutPanel({super.key});

  @override
  ConsumerState<ProfileAboutPanel> createState() => _ProfileAboutPanelState();
}

class _ProfileAboutPanelState extends ConsumerState<ProfileAboutPanel> {
  bool _checking = false;
  AppVersionInfo? _result;
  String? _error;

  Future<void> _checkUpdate() async {
    if (_checking) {
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final api = ref.read(appVersionApiProvider);
      final info = await api.version();
      if (mounted) {
        setState(() => _result = info);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = describeUserFacingError(error).message);
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final info = _result;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(size: 40, radius: 10),
          const SizedBox(height: 18),
          Text(
            'OmniNest',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settingsAboutHint,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _checking ? null : _checkUpdate,
            icon:
                _checking
                    ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.system_update_rounded, size: 18),
            label: Text(l10n.settingsCheckUpdate),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.settingsCheckUpdateFailed(_error!),
              style: TextStyle(color: scheme.error),
            ),
          ],
          if (info != null) ...[
            const SizedBox(height: 12),
            if (info.latestVersion == null)
              Text(
                l10n.settingsAlreadyLatest,
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else ...[
              Text(
                l10n.settingsNewVersionFound(info.latestVersion!),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (info.downloadUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.tonal(
                    onPressed:
                        () => unawaited(_openDownloadPage(info.downloadUrl!)),
                    child: Text(l10n.settingsOpenDownloadPage),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _openDownloadPage(String url) async {
    // Web 经条件导入新开下载页；桌面/移动展示地址。
    if (kIsWeb) {
      openDownloadUrl(url);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context).settingsOpenDownloadPage}: $url',
          ),
        ),
      );
    }
  }
}
