import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/version/app_version_api.dart';
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_section_card.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

/// 安全凭证卡内的密码管理行（容器由凭证卡提供）。
class ProfileSecurityActionsPanel extends StatelessWidget {
  const ProfileSecurityActionsPanel({
    required this.onChangePassword,
    super.key,
  });

  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.profilePasswordRowTitle,
                style: TextStyle(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.profileChangePasswordSubtitle,
                style: TextStyle(
                  fontSize: AppTypography.labelSmall,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        WorkstationActionButton(
          label: l10n.profileChangePassword,
          onPressed: onChangePassword,
        ),
      ],
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
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandLogo(size: 36, radius: 0),
              const SizedBox(width: 14),
              Text(
                'OmniNest',
                style: TextStyle(
                  fontSize: AppTypography.titleMedium,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsAboutHint,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          WorkstationActionButton(
            label: l10n.settingsCheckUpdate,
            icon: Icons.system_update_outlined,
            onPressed: _checking ? null : _checkUpdate,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.settingsCheckUpdateFailed(_error!),
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: scheme.error,
              ),
            ),
          ],
          if (info != null) ...[
            const SizedBox(height: 12),
            if (info.latestVersion == null)
              Text(
                l10n.settingsAlreadyLatest,
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                l10n.settingsNewVersionFound(info.latestVersion!),
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (info.downloadUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: WorkstationActionButton(
                    label: l10n.settingsOpenDownloadPage,
                    variant: WorkstationActionButtonVariant.primary,
                    onPressed:
                        () => unawaited(_openDownloadPage(info.downloadUrl!)),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _openDownloadPage(String url) async {
    // Web 经条件导入新开下载页；弹窗拦截时退回展示地址。
    if (kIsWeb && openDownloadUrl(url)) {
      return;
    }
    if (mounted) {
      showOmniFeedback(
        context,
        '${AppLocalizations.of(context).settingsOpenDownloadPage}: $url',
      );
    }
  }
}
