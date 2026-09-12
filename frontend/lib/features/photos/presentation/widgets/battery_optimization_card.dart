import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/platform/android/battery_optimization_service.dart';

/// 后台运行引导卡片：Android 显示电池优化白名单引导，其它平台不占位。
///
/// 供照片备份设置（F9 设置集中化后位于设置-备份分区）使用。
class BatteryOptimizationCard extends StatefulWidget {
  const BatteryOptimizationCard({super.key});

  @override
  State<BatteryOptimizationCard> createState() =>
      _BatteryOptimizationCardState();
}

class _BatteryOptimizationCardState extends State<BatteryOptimizationCard> {
  bool? _ignoring;

  @override
  void initState() {
    super.initState();
    BatteryOptimizationService.instance().isIgnoringBatteryOptimizations().then(
      (value) {
        if (mounted) {
          setState(() => _ignoring = value);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_ignoring == null) {
      return const SizedBox.shrink();
    }
    final granted = _ignoring!;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          granted ? Icons.battery_saver_rounded : Icons.battery_alert_rounded,
          color:
              granted
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
        ),
        title: Text(l10n.batteryOptimizationTitle),
        subtitle: Text(
          granted
              ? l10n.batteryOptimizationGranted
              : l10n.batteryOptimizationHint,
        ),
        trailing:
            granted
                ? Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                )
                : FilledButton.tonal(
                  onPressed: () async {
                    await BatteryOptimizationService.instance()
                        .requestIgnoreBatteryOptimizations();
                    final value =
                        await BatteryOptimizationService.instance()
                            .isIgnoringBatteryOptimizations();
                    if (mounted) {
                      setState(() => _ignoring = value);
                    }
                  },
                  child: Text(l10n.batteryOptimizationAllow),
                ),
      ),
    );
  }
}
