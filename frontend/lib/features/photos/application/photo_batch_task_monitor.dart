import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo_batch_task.dart';

enum PhotoBatchTaskMonitorIssue { notFound, timedOut }

class PhotoBatchTaskMonitorState {
  const PhotoBatchTaskMonitorState({this.task, this.refreshError, this.issue});

  final PhotoBatchTask? task;
  final Object? refreshError;
  final PhotoBatchTaskMonitorIssue? issue;

  bool get isTerminal =>
      task?.isCompleted == true || task?.isFailed == true || issue != null;
}

class PhotoBatchTaskMonitorPolicy {
  const PhotoBatchTaskMonitorPolicy({
    this.maximumDuration = const Duration(minutes: 30),
    this.baseDelay = const Duration(seconds: 2),
  });

  final Duration maximumDuration;
  final Duration baseDelay;

  Duration delayFor(int consecutiveFailures) {
    final multiplier = switch (consecutiveFailures) {
      0 => 1,
      1 => 2,
      2 => 3,
      _ => 6,
    };
    return baseDelay * multiplier;
  }
}

final photoBatchTaskMonitorPolicyProvider = Provider(
  (_) => const PhotoBatchTaskMonitorPolicy(),
);

/// 串行监控批量任务，避免 Widget Timer 产生重叠请求或吞掉刷新错误。
final photoBatchTaskMonitorProvider = StreamProvider.autoDispose
    .family<PhotoBatchTaskMonitorState, String>((ref, taskId) async* {
      final repository = ref.watch(photoRepositoryProvider);
      final policy = ref.watch(photoBatchTaskMonitorPolicyProvider);
      PhotoBatchTask? lastTask;
      var consecutiveFailures = 0;
      final startedAt = DateTime.now();

      while (ref.mounted) {
        if (DateTime.now().difference(startedAt) >= policy.maximumDuration) {
          yield PhotoBatchTaskMonitorState(
            task: lastTask,
            issue: PhotoBatchTaskMonitorIssue.timedOut,
          );
          return;
        }
        try {
          final task = await repository.getBatchTask(taskId);
          if (!ref.mounted) {
            return;
          }
          lastTask = task;
          consecutiveFailures = 0;
          yield PhotoBatchTaskMonitorState(task: task);
          if (task.isCompleted || task.isFailed) {
            return;
          }
        } on Object catch (error) {
          if (!ref.mounted) {
            return;
          }
          if (_isNotFound(error)) {
            yield PhotoBatchTaskMonitorState(
              task: lastTask,
              refreshError: error,
              issue: PhotoBatchTaskMonitorIssue.notFound,
            );
            return;
          }
          consecutiveFailures++;
          yield PhotoBatchTaskMonitorState(task: lastTask, refreshError: error);
        }

        await Future<void>.delayed(policy.delayFor(consecutiveFailures));
      }
    });

bool _isNotFound(Object error) {
  if (error is! AppException) {
    return false;
  }
  final code = error.code.toUpperCase();
  return code == 'NOT_FOUND' || code == 'TASK_NOT_FOUND' || code == '404';
}
