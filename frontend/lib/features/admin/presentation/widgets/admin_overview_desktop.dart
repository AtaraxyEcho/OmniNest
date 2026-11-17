import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_desktop_kit.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';

/// 概览的桌面排版（样例 `Admin.tsx` 的 `Overview`）：
/// 四张指标卡 + 系统健康 + 角色 + 存储资产，全部用桌面卡片与衬线数值。
///
/// 数据只取 `AdminConsoleSummary`；没有数据源的区块（样例的 14 天上传柱图、
/// 存储重算动作）不摆空壳。
class DesktopAdminOverview extends StatelessWidget {
  const DesktopAdminOverview({required this.summary, super.key});

  final AdminConsoleSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final users = summary.users;
    final tasks = summary.tasks;
    final storage = summary.storage;
    final stats = <(String, String, String)>[
      (
        l10n.adminUsers,
        '${users.total}',
        '${users.active} ${l10n.adminActive.toLowerCase()}',
      ),
      (
        l10n.adminItems,
        '${storage.fileCount}',
        '${storage.folderCount} ${l10n.filesFolders.toLowerCase()}',
      ),
      (
        l10n.adminNavTasks,
        '${tasks.running}',
        '${tasks.queued} ${l10n.adminQueued.toLowerCase()}',
      ),
      (
        l10n.desktopStorage,
        formatFileSize(storage.usedBytes),
        '${storage.objectCount} objects',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100 ? 4 : 2;
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
        const SizedBox(height: 18),
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
        const SizedBox(height: 14),
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
        const SizedBox(height: 14),
        AdminCard(
          title: l10n.adminStorageOverview,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatFileSize(storage.usedBytes),
                    style: DesktopType.adminStatValue(skin.text),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.adminStorageFileCount(storage.fileCount),
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DesktopKeyValues(
                entries: [
                  MapEntry(l10n.filesFolders, '${storage.folderCount}'),
                  MapEntry('Objects', '${storage.objectCount}'),
                  MapEntry(
                    l10n.filesExternalStorage,
                    '${storage.externalAccountCount}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
