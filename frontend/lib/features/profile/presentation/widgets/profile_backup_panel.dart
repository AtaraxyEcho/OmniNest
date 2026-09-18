import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:omninest/features/photos/presentation/widgets/battery_optimization_card.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_backup_enable_flow.dart';

/// 备份设置分区：照片后台备份开关与 Android 电池优化引导。
///
/// 开关交互（二次确认 + 范围选择）统一走 [showPhotoBackupEnableFlow]。
class ProfileBackupPanel extends ConsumerWidget {
  const ProfileBackupPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final backupAsync = ref.watch(photoBackupPreferencesControllerProvider);
    final settings = backupAsync.asData?.value;
    final isAllScope =
        settings == null || settings.scope == PhotoBackupScope.all;
    final scopeLabel =
        isAllScope
            ? l10n.photoBackupScopeSummaryAll
            : l10n.photoBackupScopeSummarySelected(
              settings.selectedAlbumIds.length,
            );
    final subtitleText =
        isAllScope
            ? l10n.photoBackupBackgroundSubtitle
            : l10n.photoBackupBackgroundSubtitleScoped;

    return WorkbenchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.profileSectionBackup, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.photoBackupBackgroundTitle),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitleText),
                const SizedBox(height: 2),
                Text(
                  scopeLabel,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.70,
                    ),
                    fontSize: AppTypography.labelSmall,
                  ),
                ),
              ],
            ),
            value: settings?.enabled ?? false,
            onChanged:
                backupAsync.isLoading || !isAndroidPlatform
                    ? null
                    : (value) =>
                        showPhotoBackupEnableFlow(context, ref, enable: value),
          ),
          if (settings?.enabled ?? false)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.photoBackupWifiOnlyTitle),
              subtitle: Text(l10n.photoBackupWifiOnlySubtitle),
              value: settings?.networkPolicy != PhotoBackupNetworkPolicy.any,
              onChanged:
                  backupAsync.isLoading || !isAndroidPlatform
                      ? null
                      : (value) => ref
                          .read(
                            photoBackupPreferencesControllerProvider.notifier,
                          )
                          .setNetworkPolicy(
                            value
                                ? PhotoBackupNetworkPolicy.wifiOnly
                                : PhotoBackupNetworkPolicy.any,
                          ),
            ),
          const SizedBox(height: 12),
          const BatteryOptimizationCard(),
        ],
      ),
    );
  }
}
