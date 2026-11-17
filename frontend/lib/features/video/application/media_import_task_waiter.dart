import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';

/// 媒体导入结果等待器的应用层入口。
///
/// 这里只拿任务能力，不引用任务模块的数据类型：跨 feature 只允许依赖
/// application 层，数据层类型由任务模块自己持有。
final mediaImportTaskWaiterProvider = Provider<MediaImportTaskWaiter>((ref) {
  return MediaImportTaskWaiter(
    (taskId) => ref.read(taskApiProvider).waitForTerminal(
      taskId,
      timeout: const Duration(minutes: 2),
      interval: const Duration(seconds: 2),
    ),
  );
});

/// 等待媒体自动导入任务进入终态。
///
/// 轮询节奏属于产品口径而不是页面细节：超时 2 分钟、间隔 2 秒在这里定义，
/// 桌面与移动两个外壳不再各写一份常量。
class MediaImportTaskWaiter {
  const MediaImportTaskWaiter(this._waitForTerminal);

  final Future<void> Function(String taskId) _waitForTerminal;

  Future<void> waitForTerminal(String taskId) => _waitForTerminal(taskId);
}
