part of 'movie_management.dart';

class _MovieAdminTaskDialog extends ConsumerStatefulWidget {
  const _MovieAdminTaskDialog();

  @override
  ConsumerState<_MovieAdminTaskDialog> createState() =>
      _MovieAdminTaskDialogState();
}

class _MovieAdminTaskDialogState extends ConsumerState<_MovieAdminTaskDialog> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _handleRefreshTick();
    });
  }

  /// 仅存在非终态任务时继续轮询；realtime 已覆盖任务事件，轮询只作
  /// 断线兜底，全部终态即停，避免对话框开着就持续请求。
  void _handleRefreshTick() {
    if (!mounted) {
      return;
    }
    final tasks = ref.read(movieCenterControllerProvider).asData?.value.tasks;
    // 任务列表尚未加载完成时保持轮询等待首份快照；已加载（含空列表）
    // 且全部终态即停止，避免无任务或任务全部完成后仍持续请求。
    if (tasks != null &&
        tasks.every((task) => _isTerminalStatus(task.status))) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    ref.read(movieCenterControllerProvider.notifier).refreshTasksForRealtime();
  }

  static bool _isTerminalStatus(String status) {
    return switch (status.toUpperCase()) {
      'COMPLETED' || 'FAILED' || 'CANCELLED' => true,
      _ => false,
    };
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(
      movieCenterControllerProvider.select(
        (state) => state.asData?.value.tasks,
      ),
    );
    final taskList = tasks ?? const <MovieTask>[];
    return AlertDialog(
      title: Text(l10n.videoTaskProgressDialog),
      content: SizedBox(
        width: 560,
        height: 440,
        child:
            taskList.isEmpty
                ? EmptyMovieState(message: l10n.videoNoTasks)
                : ListView.builder(
                  itemCount: taskList.length,
                  itemBuilder:
                      (context, index) =>
                          _TaskProgressRow(task: taskList[index]),
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.videoClose),
        ),
      ],
    );
  }
}

class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow({required this.task});

  final MovieTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = task.status.toUpperCase();
    final failed = status == 'FAILED';
    final completed = status == 'COMPLETED';
    final running = status == 'RUNNING' || status == 'QUEUED';
    final statusColor =
        failed
            ? Theme.of(context).colorScheme.error
            : completed || running
            ? context.videoColors.primary
            : context.videoColors.onSurfaceVariant;
    final taskLabel = switch (task.taskType) {
      'AUDIO_EXTRACT' => l10n.videoAudioExtract,
      'VIDEO_TRANSCODE' => l10n.videoTranscode,
      'MEDIA_SCRAPE' => l10n.videoMetadataScrape,
      'MEDIA_SCAN' => l10n.videoMediaScan,
      'LOCAL_VIDEO_LIBRARY_DISCOVERY' => l10n.videoLocalDiscoveryTask,
      'LOCAL_VIDEO_LIBRARY_APPLY' => l10n.videoLocalImportTask,
      _ => task.taskType,
    };
    final statusLabel = switch (status) {
      'QUEUED' => l10n.videoQueued,
      'RUNNING' => l10n.videoRunning,
      'COMPLETED' => l10n.videoCompleted,
      'FAILED' => l10n.videoFailed,
      'CANCELLED' => l10n.videoCancelled,
      'DLQ' => l10n.videoDeadLetterQueue,
      _ => task.status,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerHighest.withValues(
          alpha: 0.46,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$taskLabel · $statusLabel',
                  style: TextStyle(
                    color: context.videoColors.onSurface,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${task.progress}%',
                style: TextStyle(
                  color: statusColor,
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: task.progress / 100.0,
              minHeight: 4,
              backgroundColor: context.videoColors.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(
                failed
                    ? Theme.of(context).colorScheme.error
                    : context.videoColors.primary,
              ),
            ),
          ),
          if (task.errorSummary != null && task.errorSummary!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.errorSummary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: AppTypography.bodySmall,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
