import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';

/// 壳层的按分支决策全部落在本文件：新增一级分支时必须在这里逐条表态，
/// 未登记的分支编号会在调试构建当场抛错（见 [MobileNavigationConfig.undeclaredBranch]），
/// 不再静默取 false。
///
/// 将文件空间的选择状态聚合为壳层只读状态。
///
/// 照片多选只存在于全屏照片模块页（无壳层 chrome），不再参与壳层抑制。
final mobileShellSelectionActiveProvider = Provider.family<bool, int>((
  ref,
  branch,
) {
  return switch (branch) {
    MobileNavigationConfig.filesBranch =>
      ref.watch(fileBrowserControllerProvider).asData?.value.hasSelection ??
          false,
    // 其余三个空间没有壳层内的多选态（照片多选只存在于全屏模块页），
    // 逐条写死而不是用通配兜底，见 MobileNavigationConfig.undeclaredBranch。
    MobileNavigationConfig.portalBranch ||
    MobileNavigationConfig.libraryBranch ||
    MobileNavigationConfig.readerBranch => false,
    _ => MobileNavigationConfig.undeclaredBranch(branch, '多选占用', false),
  };
});

/// 文件分支的子页态：样例 `.module-overlay` 是 `inset: 0` 的整屏层，
/// 自带 90 高页头与返回钮，不应再叠一层壳层顶栏与底部 tab。
/// 照片/音乐/影视走根级路由天然无壳层 chrome，文件分区是 `/files`
/// branch 内的 `state.section`，只能由壳层显式让位。
final mobileShellSubpageActiveProvider = Provider.family<bool, int>((
  ref,
  branch,
) {
  return switch (branch) {
    MobileNavigationConfig.filesBranch =>
      ref.watch(fileBrowserControllerProvider).asData?.value.mobileSubpage ??
          false,
    MobileNavigationConfig.portalBranch ||
    MobileNavigationConfig.libraryBranch ||
    MobileNavigationConfig.readerBranch => false,
    _ => MobileNavigationConfig.undeclaredBranch(branch, '子页让位', false),
  };
});

/// 返回当前是否启用了可用的动态背景（Web 壁纸与原生壁纸同源）。
final mobileShellLocalBackdropActiveProvider = Provider<bool>((ref) {
  final state = ref.watch(appBackdropControllerProvider).asData?.value;
  return state?.hasActiveBackdrop == true;
});
