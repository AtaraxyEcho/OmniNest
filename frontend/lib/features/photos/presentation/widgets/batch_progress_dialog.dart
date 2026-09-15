import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/application/photo_batch_task_monitor.dart';
import 'package:omninest/features/photos/platform/photo_batch_web_download.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';

/// 批量任务进度对话框（Frame 极简风格）。
class BatchProgressDialog extends ConsumerStatefulWidget {
  const BatchProgressDialog({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<BatchProgressDialog> createState() =>
      _BatchProgressDialogState();
}

class _BatchProgressDialogState extends ConsumerState<BatchProgressDialog> {
  bool _isDownloading = false;
  bool _refreshedAfterTerminal = false;

  Future<void> _downloadArchive() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final ticket = await controller.getBatchDownloadTicket(widget.taskId);
      if (kIsWeb) {
        await downloadPhotoBatchInBrowser(
          url: ticket.url,
          fileName: ticket.fileName,
        );
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.photosDownloadStarted)),
          );
        }
        return;
      }
      final savedPath = await controller.saveBatchArchiveToDisk(ticket);
      if (savedPath == null) return;
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.photosArchiveSaved(savedPath))),
        );
      }
    } on Exception {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.photosArchiveDownloadFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 改动型批量任务到达终态后立即刷新照片数据，不依赖 realtime 失效
    // 事件兜底；下载任务只产出压缩包，不改动照片数据，无需刷新。失败
    // 任务也可能已应用部分修改，同样刷新。
    ref.listen<AsyncValue<PhotoBatchTaskMonitorState>>(
      photoBatchTaskMonitorProvider(widget.taskId),
      (previous, next) {
        final task = next.asData?.value.task;
        if (task == null || task.taskType == 'DOWNLOAD') {
          return;
        }
        if (!task.isCompleted && !task.isFailed) {
          return;
        }
        if (_refreshedAfterTerminal) {
          return;
        }
        _refreshedAfterTerminal = true;
        unawaited(ref.read(photoCenterControllerProvider.notifier).refresh());
      },
    );
    final monitor = ref.watch(photoBatchTaskMonitorProvider(widget.taskId));
    final snapshot = monitor.asData?.value;
    final task = snapshot?.task;
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    final photosColors = context.photosColors;
    return AlertDialog(
      backgroundColor: colors.searchFill,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        task == null ? l10n.photosLoading : _taskTitle(l10n, task.taskType),
        style: TextStyle(
          fontFamily: FramePalette.serifFamily,
          fontFamilyFallback: FramePalette.serifFallback,
          color: colors.ink,
          fontSize: AppTypography.titleLarge,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task == null) ...[
            if (monitor.hasError)
              Text(
                l10n.photosTaskFailed,
                style: TextStyle(color: photosColors.danger),
              )
            else
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ] else if (task.isFailed) ...[
            Icon(Icons.error_outline, color: photosColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(
              task.errorMessage ??
                  AppLocalizations.of(context).photosTaskFailed,
              style: TextStyle(color: colors.sub),
              textAlign: TextAlign.center,
            ),
          ] else if (task.isCompleted) ...[
            Icon(
              Icons.check_circle_outline,
              color: photosColors.success,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(
                context,
              ).photosProcessedItems(task.processedItems),
              style: TextStyle(color: colors.sub),
            ),
          ] else ...[
            LinearProgressIndicator(
              value: task.progress,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: colors.hover,
              color: colors.accent,
            ),
            const SizedBox(height: 12),
            Text(
              '${task.processedItems} / ${task.totalItems}',
              style: TextStyle(
                color: colors.sub,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
          ],
          if (snapshot?.refreshError != null) ...[
            const SizedBox(height: 12),
            Text(
              switch (snapshot?.issue) {
                PhotoBatchTaskMonitorIssue.notFound => l10n.photosTaskNotFound,
                PhotoBatchTaskMonitorIssue.timedOut =>
                  l10n.photosTaskMonitorTimedOut,
                null => l10n.photosTaskStatusRefreshFailed,
              },
              style: TextStyle(color: photosColors.danger),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (snapshot?.issue != null || snapshot?.refreshError != null)
          TextButton.icon(
            onPressed:
                () => ref.invalidate(
                  photoBatchTaskMonitorProvider(widget.taskId),
                ),
            style: TextButton.styleFrom(foregroundColor: colors.sub),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.photosRetryStatus),
          ),
        if (task == null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: colors.sub),
            child: Text(l10n.photosDone),
          )
        else if (task.isCompleted && task.taskType == 'DOWNLOAD') ...[
          TextButton(
            onPressed: _isDownloading ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: colors.sub),
            child: Text(AppLocalizations.of(context).photosDone),
          ),
          FrameDialogActionButton(
            label: AppLocalizations.of(context).photosSaveZip,
            onPressed: _isDownloading ? null : _downloadArchive,
          ),
        ] else if (task.isCompleted || task.isFailed)
          FrameDialogActionButton(
            label: AppLocalizations.of(context).photosDone,
            onPressed: () => Navigator.pop(context),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: colors.sub),
            child: Text(AppLocalizations.of(context).photosRunInBackground),
          ),
      ],
    );
  }

  String _taskTitle(AppLocalizations l10n, String taskType) {
    return switch (taskType) {
      'TAG' => l10n.photosBatchAddTag,
      'MOVE' => l10n.photosMove,
      'UPDATE_DATE' => l10n.photosUpdateDate,
      'DOWNLOAD' => l10n.photosExportZip,
      _ => l10n.photosLoading,
    };
  }
}
