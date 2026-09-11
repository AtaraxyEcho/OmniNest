import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';

/// 移动端壳层展示的通知与后台任务摘要。
class MobileShellActivityState {
  const MobileShellActivityState({
    required this.unreadCount,
    required this.activeTaskCount,
    required this.failedTaskCount,
  });

  final int unreadCount;
  final int activeTaskCount;
  final int failedTaskCount;

  /// 当前是否存在需要在壳层提示的活动。
  bool get isVisible =>
      unreadCount > 0 || activeTaskCount > 0 || failedTaskCount > 0;
}

/// 将文件与照片模块的选择状态聚合为壳层只读状态。
final mobileShellSelectionActiveProvider = Provider.family<bool, int>((
  ref,
  branch,
) {
  return switch (branch) {
    MobileNavigationConfig.filesBranch =>
      ref.watch(fileBrowserControllerProvider).asData?.value.hasSelection ??
          false,
    MobileNavigationConfig.photosBranch =>
      ref.watch(photoCenterControllerProvider).asData?.value.isSelectionMode ??
          false,
    _ => false,
  };
});

/// 将通知与任务模块状态聚合为壳层只读摘要。
final mobileShellActivityProvider = Provider<MobileShellActivityState>((ref) {
  final taskSummary = ref.watch(activeTaskSummaryProvider).asData?.value;
  return MobileShellActivityState(
    unreadCount: ref.watch(unreadCountProvider),
    activeTaskCount: taskSummary?.activeCount ?? 0,
    failedTaskCount: taskSummary?.failedCount ?? 0,
  );
});

/// 返回当前是否启用了可用的动态背景（Web 壁纸与原生壁纸同源）。
final mobileShellLocalBackdropActiveProvider = Provider<bool>((ref) {
  final state = ref.watch(appBackdropControllerProvider).asData?.value;
  return state?.hasActiveBackdrop == true;
});
