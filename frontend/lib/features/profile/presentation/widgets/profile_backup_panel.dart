import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:omninest/features/photos/presentation/widgets/battery_optimization_card.dart';

/// 备份设置分区：照片后台备份开关与 Android 电池优化引导。
class ProfileBackupPanel extends ConsumerWidget {
  const ProfileBackupPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final backupEnabled = ref.watch(photoBackupPreferencesControllerProvider);

    return WorkbenchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.profileSectionBackup, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.photoBackupBackgroundTitle),
            subtitle: Text(l10n.photoBackupBackgroundSubtitle),
            value: backupEnabled.asData?.value ?? false,
            onChanged:
                backupEnabled.isLoading
                    ? null
                    : (value) {
                      ref
                          .read(
                            photoBackupPreferencesControllerProvider.notifier,
                          )
                          .setEnabled(value);
                    },
          ),
          const SizedBox(height: 12),
          const BatteryOptimizationCard(),
        ],
      ),
    );
  }
}
