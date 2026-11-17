import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/core/notifications/system_notifier.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

/// 任务系统通知开关（设备级偏好，默认关闭）。
final taskNotificationEnabledProvider =
    AsyncNotifierProvider<TaskNotificationEnabledController, bool>(
      TaskNotificationEnabledController.new,
    );

class TaskNotificationEnabledController extends AsyncNotifier<bool> {
  static const _key = 'task_system_notifications_enabled';

  @override
  Future<bool> build() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = AsyncData(value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, value);
  }
}

/// 任务终态迁移检测结果。
class TaskTerminalTransition {
  const TaskTerminalTransition({
    required this.taskId,
    required this.taskType,
    required this.failed,
    required this.summary,
  });

  final String taskId;
  final String taskType;
  final bool failed;
  final String summary;
}

/// 检测任务从"活跃"进入"终态"的迁移，保证同一任务只通知一次。
class TaskTerminalTransitionDetector {
  final Set<String> _activeIds = <String>{};
  final Set<String> _notifiedIds = <String>{};

  List<TaskTerminalTransition> consume(
    List<TaskRecord> previous,
    List<TaskRecord> next,
  ) {
    final events = <TaskTerminalTransition>[];
    final nextIds = <String>{};
    for (final task in next) {
      nextIds.add(task.id);
      if (!task.isTerminal) {
        _activeIds.add(task.id);
        continue;
      }
      final wasActive =
          previous.any((item) => item.id == task.id && !item.isTerminal) ||
          _activeIds.contains(task.id);
      if (wasActive && _notifiedIds.add(task.id)) {
        events.add(
          TaskTerminalTransition(
            taskId: task.id,
            taskType: task.taskType,
            failed: task.isFailed,
            summary:
                task.isFailed
                    ? (task.errorMessage ?? task.result ?? '')
                    : (task.result ?? ''),
          ),
        );
      }
      _activeIds.remove(task.id);
    }
    return events;
  }
}

/// 挂接任务列表监听，把终态迁移转为系统通知。
///
/// 在应用根 provider 中 watch 一次即可持续生效。
final taskSystemNotificationBindingProvider = Provider<void>((ref) {
  final detector = TaskTerminalTransitionDetector();
  ref.listen(taskListProvider, (previous, next) {
    final enabled = ref.read(taskNotificationEnabledProvider).asData?.value;
    if (enabled != true) {
      return;
    }
    final events = detector.consume(previous ?? const [], next);
    if (events.isEmpty) {
      return;
    }
    final languageCode = ref.read(localeControllerProvider);
    final l10n = lookupAppLocalizations(Locale(languageCode));
    for (final event in events) {
      unawaited(
        SystemNotifier.instance.show(
          id: event.taskId.hashCode & 0x7fffffff,
          title:
              event.failed
                  ? l10n.taskNotifyTitleFailed
                  : l10n.taskNotifyTitleCompleted,
          body:
              '${event.taskType}${event.summary.isEmpty ? '' : ': ${event.summary}'}',
        ),
      );
    }
  });
});
