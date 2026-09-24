import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';

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

/// 返回当前是否启用了可用的动态背景（Web 壁纸与原生壁纸同源）。
final mobileShellLocalBackdropActiveProvider = Provider<bool>((ref) {
  final state = ref.watch(appBackdropControllerProvider).asData?.value;
  return state?.hasActiveBackdrop == true;
});
