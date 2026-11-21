import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/desktop/widgets/desktop_chart_tooltip.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_desktop_kit.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';

/// 概览的桌面排版（样例 `Admin.tsx` 的 `Overview`）：
/// 四张指标卡、真实上传趋势、系统健康、角色与存储重算操作。
class DesktopAdminOverview extends ConsumerWidget {
  const DesktopAdminOverview({
    required this.summary,
    this.analytics,
    this.analyticsError,
    this.onRetryAnalytics,
    super.key,
  });

  final AdminConsoleSummary summary;
  final AdminAnalytics? analytics;
  final String? analyticsError;
  final VoidCallback? onRetryAnalytics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final users = summary.users;
    final tasks = summary.tasks;
    final storage = summary.storage;
    final accountStorage = ref.watch(fileStorageStatsProvider).asData?.value;
    final uploadMetrics = analytics?.dailyUploads ?? const <DailyMetric>[];
    final uploadsThisWeek = uploadMetrics
        .skip(uploadMetrics.length > 7 ? uploadMetrics.length - 7 : 0)
        .fold<int>(0, (total, item) => total + item.value);
    final stats = <(String, String, String)>[
      (
        l10n.adminUsers,
        '${users.total}',
        '${users.active} ${l10n.adminActive.toLowerCase()}',
      ),
      (
        l10n.adminItems,
        '${storage.fileCount}',
        analytics == null
            ? '— ${l10n.desktopStatThisWeek}'
            : '+$uploadsThisWeek ${l10n.desktopStatThisWeek}',
      ),
      (
        l10n.adminRunningTasksStat,
        '${tasks.running}',
        '${tasks.queued} ${l10n.adminQueued.toLowerCase()}',
      ),
      (
        l10n.adminStorageLabel,
        storage.usedBytes > 0 || storage.fileCount > 0
            ? formatFileSize(storage.usedBytes)
            : accountStorage == null
            ? formatFileSize(storage.usedBytes)
            : formatFileSize(accountStorage.usedBytes),
        storage.usedBytes > 0 || storage.fileCount > 0
            ? '${storage.fileCount} ${l10n.filesCount} · '
                '${storage.folderCount} ${l10n.desktopFilesFilterFolders}'
            : accountStorage == null
            ? '${storage.fileCount} ${l10n.filesCount}'
            : accountStorage.isQuotaUnlimited
            ? l10n.desktopStorageUnlimited(
              formatFileSize(accountStorage.usedBytes),
            )
            : l10n.desktopStatOfTotal(
              formatFileSize(accountStorage.quotaBytes),
            ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 960 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < stats.length; i++)
                  SizedBox(
                    width: width,
                    child: DesktopStagger(
                      index: i,
                      child: AdminStatCard(
                        label: stats[i].$1,
                        value: stats[i].$2,
                        hint: stats[i].$3,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _UploadsCard(
          analytics: analytics,
          error: analyticsError,
          onRetry: onRetryAnalytics,
        ),
        const SizedBox(height: 16),
        AdminCard(
          title: l10n.adminSystemHealth,
          action: DesktopLink(
            label: l10n.adminViewLogs,
            onPressed: () => context.push('/admin/logs'),
          ),
          child:
              summary.health.isEmpty
                  ? Text(
                    l10n.adminNoComponentHealth,
                    style: DesktopType.caption(skin.text3),
                  )
                  : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in summary.health)
                        _HealthChip(item: item),
                    ],
                  ),
        ),
        const SizedBox(height: 16),
        AdminCard(
          title: l10n.adminRoles,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in summary.roles)
                DesktopChip('${role.name} · ${users.roleCount(role.code)}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _RecalculateStorageCard(),
      ],
    );
  }
}

class _UploadsCard extends StatelessWidget {
  const _UploadsCard({required this.analytics, this.error, this.onRetry});

  final AdminAnalytics? analytics;
  final String? error;
  final VoidCallback? onRetry;

  static String _shortDate(String iso) {
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    return '$month/$day';
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final metrics = analytics?.dailyUploads ?? const <DailyMetric>[];
    final maxCount = metrics.fold<int>(
      0,
      (current, item) => item.value > current ? item.value : current,
    );
    if (error != null) {
      return AdminCard(
        title: l10n.adminUploads14Days,
        action: DesktopLink(label: l10n.coreRetry, onPressed: onRetry),
        child: Text(error!, style: DesktopType.caption(skin.bad)),
      );
    }
    if (metrics.isEmpty) {
      return AdminCard(
        title: l10n.adminUploads14Days,
        child: SizedBox(
          height: 112,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < 14; index++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 3,
                      right: index == 13 ? 0 : 3,
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: DesktopSkeletonBox(
                        height: 18 + ((index * 23) % 66),
                        radius: 5,
                        index: index + 30,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final items = <DesktopChartBarItem>[
      for (final metric in metrics)
        DesktopChartBarItem(
          fraction:
              maxCount == 0 ? 0.02 : (metric.value / maxCount).clamp(0.02, 1.0),
          color: skin.accent,
          secondaryColor: skin.accent.withValues(alpha: 0.36),
          tipTitle: metric.date,
          tipValue: '${metric.value}',
        ),
    ];
    return AdminCard(
      title: l10n.adminUploads14Days,
      child: DesktopInteractiveBarChart(
        items: items,
        height: 112,
        barSpacing: 6,
        minFraction: 0.02,
        barBorderRadius: const BorderRadius.vertical(
          top: Radius.circular(6),
          bottom: Radius.circular(2),
        ),
        axisStartLabel: _shortDate(metrics.first.date),
        axisEndLabel: _shortDate(metrics.last.date),
        axisLabelStyle: DesktopType.micro(skin.text3),
      ),
    );
  }
}

class _RecalculateStorageCard extends ConsumerStatefulWidget {
  const _RecalculateStorageCard();

  @override
  ConsumerState<_RecalculateStorageCard> createState() =>
      _RecalculateStorageCardState();
}

class _RecalculateStorageCardState
    extends ConsumerState<_RecalculateStorageCard> {
  bool _busy = false;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final count =
          await ref.read(adminOperationsActionsProvider).recalculateStorage();
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminRecalculateDone(count),
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        userFacingErrorText(error, l10n: l10n),
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(DesktopMetrics.radiusCard);
    return DesktopGlassSurface(
      borderRadius: radius,
      blur: 24,
      saturation: 1.3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: skin.panel,
          borderRadius: radius,
          border: Border.all(color: skin.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.adminRecalculateStorageTitle,
                    style: DesktopType.cardTitle(skin.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.adminRecalculateStorageSubtitle,
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            DesktopButton(
              label: l10n.adminRecalculate,
              busy: _busy,
              onPressed: _busy ? null : _run,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.item});

  final AdminHealthItem item;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final ok =
        item.status.toUpperCase() == 'UP' ||
        item.status.toUpperCase() == 'HEALTHY' ||
        item.status.toUpperCase() == 'OK';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            ok
                ? skin.accentWash(0.12)
                : DesktopPalette.bad.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
        border: Border.all(
          color:
              ok
                  ? skin.accentWash(0.3)
                  : DesktopPalette.bad.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        item.detail.isEmpty ? item.name : '${item.name} · ${item.detail}',
        style: DesktopType.caption(ok ? skin.accent : DesktopPalette.bad),
      ),
    );
  }
}
