import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';

/// 天气降级态提示：区分未启用、位置解析失败与上游故障，并提供重试入口。
class WeatherDegradedNotice extends ConsumerWidget {
  const WeatherDegradedNotice({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, message) = switch (status) {
      WeatherData.statusDisabled => (
        Icons.cloud_off_outlined,
        l10n.weatherStatusDisabled,
      ),
      WeatherData.statusLocationNotFound => (
        Icons.location_off_outlined,
        l10n.weatherStatusLocationMissing,
      ),
      _ => (Icons.cloud_off_outlined, l10n.weatherStatusUpstreamFailed),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: AppTypography.bodyMedium,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              ref.invalidate(realtimeWeatherProvider);
              Navigator.of(context).maybePop();
            },
            child: Text(l10n.weatherStatusRetry),
          ),
        ],
      ),
    );
  }
}
