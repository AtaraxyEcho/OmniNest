import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';

class StorageOverviewWidget extends StatefulWidget {
  const StorageOverviewWidget({required this.stats, super.key});
  final FileStorageStats stats;

  @override
  State<StorageOverviewWidget> createState() => _StorageOverviewWidgetState();
}

class _StorageOverviewWidgetState extends State<StorageOverviewWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnim;
  double _prevRatio = 0;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: MotionToken.resolveForPlatform(MotionToken.chart),
      vsync: this,
    );
    _progressAnim = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    );
    _prevRatio = widget.stats.isQuotaUnlimited ? 0.0 : widget.stats.usageRatio;
    _progressController.value = _prevRatio;
  }

  @override
  void didUpdateWidget(StorageOverviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRatio =
        widget.stats.isQuotaUnlimited ? 0.0 : widget.stats.usageRatio;
    if ((newRatio - _prevRatio).abs() > 0.001) {
      _progressAnim = Tween<double>(begin: _prevRatio, end: newRatio).animate(
        CurvedAnimation(
          parent: _progressController,
          curve: Curves.easeOutCubic,
        ),
      );
      _progressController.forward(from: 0);
      _prevRatio = newRatio;
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final usedGiB = widget.stats.usedBytes / (1024 * 1024 * 1024);
    final quotaGiB = widget.stats.quotaBytes / (1024 * 1024 * 1024);
    final ratio = widget.stats.usageRatio;
    final color =
        ratio >= 0.95
            ? colorScheme.error
            : ratio >= 0.80
            ? colorScheme.tertiary
            : colorScheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/files'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.portalStorageTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AnimatedBuilder(
                  animation: _progressAnim,
                  builder: (context, _) {
                    return LinearProgressIndicator(
                      value:
                          widget.stats.isQuotaUnlimited
                              ? 0.0
                              : _progressAnim.value,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      color: color,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: widget.stats.isQuotaUnlimited ? 0.0 : ratio * 100,
                ),
                duration: MotionToken.reduced(context, MotionToken.chart),
                curve: Curves.easeOutCubic,
                builder: (context, percent, _) {
                  return Text(
                    widget.stats.isQuotaUnlimited
                        ? l10n.portalStorageUnlimited(
                          usedGiB.toStringAsFixed(1),
                        )
                        : '${usedGiB.toStringAsFixed(1)} / ${quotaGiB.toStringAsFixed(1)} GiB · ${percent.round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
