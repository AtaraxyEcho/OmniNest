import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_scan_job_controller.dart';

/// 本地音乐库扫描页（原型 `music-scan` 工具页的 transfer 形态）：
/// 玻璃横幅 + 扫描/重刮动作 + 进行中的任务进度行。
///
/// 稿子的 `.transfer-summary` 三格是 ACTIVE / REMAINING / ESTIMATED，
/// 后端只回状态、进度百分比与已扫描文件数，凑不出剩余与预计，
/// 因此这里不摆摘要格，避免用假数填版式。
class MusicScanPage extends ConsumerWidget {
  const MusicScanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final scanJob = ref.watch(musicScanJobControllerProvider);
    final activeScan = scanJob.job ?? center?.lastScanJob;

    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: l10n.musicDeckLocalManagement,
            subtitle: l10n.musicLocalManagementSubtitle,
            backTooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onBack: () => Navigator.of(context).maybePop(),
            actions: [
              MobileGlassIconButton(
                tooltip: l10n.musicStartScan,
                icon: Icons.radar_rounded,
                // 轮询中重复点由控制器幂等处理，这里不做禁用态：
                // 壳层玻璃圆钮的 onPressed 非空，禁用要换整套控件。
                onPressed: () => unawaited(_confirmStartScan(context, ref)),
              ),
              MobileGlassIconButton(
                tooltip: l10n.musicScrapeLibrary,
                icon: Icons.travel_explore_rounded,
                onPressed: () => unawaited(_confirmScrapeLibrary(context, ref)),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
              children: [
                if (activeScan == null)
                  EnvEmptyState(
                    icon: OmniIcons.music,
                    title: l10n.musicScanIdleHint,
                  )
                else ...[
                  MobileTransferRow(
                    icon: OmniIcons.queue,
                    title: activeScan.status,
                    detail: l10n.musicScanScannedFiles(activeScan.scannedFiles),
                    progress:
                        activeScan.progress > 0
                            ? activeScan.progress / 100
                            : null,
                    statusLabel: '${activeScan.progress}%',
                    tone:
                        scanJob.polling
                            ? MobileStatusTone.warning
                            : MobileStatusTone.calm,
                  ),
                  if (activeScan.message != null &&
                      activeScan.message!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        activeScan.message!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9, // ignore: font_size_whitelist
                          height: 1.4,
                          color: context.env.inkMuted,
                        ),
                      ),
                    ),
                  if (scanJob.timedOut)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.musicScanPollTimeout,
                        style: TextStyle(
                          fontSize: 9, // ignore: font_size_whitelist
                          height: 1.4,
                          color: context.env.inkMuted,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 扫描与重刮都要二次确认：两者都会整库回写，误触代价高。
  Future<void> _confirmStartScan(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.musicStartScan),
            content: Text(l10n.musicScanStartConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.musicCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.musicStartScan),
              ),
            ],
          ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(musicScanJobControllerProvider.notifier).startScan();
    if (!context.mounted) {
      return;
    }
    await ref.read(musicCenterControllerProvider.notifier).refresh();
  }

  Future<void> _confirmScrapeLibrary(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.musicScrapeLibraryConfirmTitle),
            content: Text(l10n.musicScrapeLibraryConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.musicCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.musicScrapeLibrary),
              ),
            ],
          ),
    );
    if (confirmed != true) {
      return;
    }
    // 失败由命令层写进中心 errorMessage，这里不重复提示。
    await ref
        .read(musicCenterControllerProvider.notifier)
        .scrapeLibrary(force: true);
  }
}
