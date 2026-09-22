import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/tasks/data/task_api.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

final taskApiProvider = Provider<TaskApi>((ref) {
  return TaskApi(ref.watch(apiClientProvider));
});

final taskListProvider = NotifierProvider<TaskListNotifier, List<TaskRecord>>(
  TaskListNotifier.new,
);

/// 独立读取全局任务条所需摘要，不依赖任务页面分页状态。
final activeTaskSummaryProvider = FutureProvider<ActiveTaskSummary>((
  ref,
) async {
  ref.watch(sessionEpochProvider);
  final tasks = await ref.watch(taskApiProvider).list(page: 0, size: 100);
  return ActiveTaskSummary.fromRecords(tasks);
});

class TaskListNotifier extends Notifier<List<TaskRecord>> {
  @override
  List<TaskRecord> build() {
    ref.watch(sessionEpochProvider);
    return [];
  }

  int _page = 0;
  bool _hasMore = true;
  bool _reloadRequested = false;
  Future<void>? _activeOperation;

  TaskApi get _api => ref.read(taskApiProvider);

  Future<void> load() async {
    if (!ref.mounted) {
      return;
    }
    _reloadRequested = true;
    while (_reloadRequested && ref.mounted) {
      final active = _activeOperation;
      if (active != null) {
        await active;
        if (!ref.mounted) {
          return;
        }
        continue;
      }
      _reloadRequested = false;
      final operation = _loadFirstPage();
      _activeOperation = operation;
      try {
        await operation;
      } finally {
        if (identical(_activeOperation, operation)) {
          _activeOperation = null;
        }
      }
    }
  }

  Future<void> loadMore() async {
    if (!ref.mounted || !_hasMore) {
      return;
    }
    final active = _activeOperation;
    if (active != null) {
      await active;
      return;
    }
    final operation = _loadNextPage();
    _activeOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    }
  }

  Future<void> _loadFirstPage() async {
    _page = 0;
    _hasMore = true;
    final items = await _api.list(page: 0);
    if (!ref.mounted) {
      return;
    }
    state = items;
    _hasMore = items.length >= 20;
    _page = 1;
  }

  Future<void> _loadNextPage() async {
    final items = await _api.list(page: _page);
    if (!ref.mounted) {
      return;
    }
    state = [...state, ...items];
    _hasMore = items.length >= 20;
    _page++;
  }

  Future<void> retry(String taskId) async {
    await _api.retry(taskId);
    if (!ref.mounted) {
      return;
    }
    state = [
      for (final t in state)
        if (t.id == taskId)
          TaskRecord(
            id: t.id,
            taskType: t.taskType,
            status: 'PENDING',
            phase: t.phase,
            progress: t.progress,
            resourceType: t.resourceType,
            resourceId: t.resourceId,
            routingKey: t.routingKey,
            result: t.result,
            errorMessage: t.errorMessage,
            retryCount: t.retryCount + 1,
            maxRetries: t.maxRetries,
            startedAt: t.startedAt,
            completedAt: t.completedAt,
            createdAt: t.createdAt,
          )
        else
          t,
    ];
    ref.invalidate(activeTaskSummaryProvider);
  }
}
