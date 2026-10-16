part of 'file_browser_controller.dart';

/// 分页窗口与元数据的纯映射助手。
///
/// 这两个方法不碰 `state`，放在独立 part 里是为了给主类腾出行预算：主类已贴近 1200 行
/// 架构上限（`test/architecture/dart_source_size_test.dart`），而子页态覆盖缺陷的修复
/// 必须在主类里新增两个要写 `state` 的回写助手（`state` 是受保护成员，只能在类内写）。
extension FileBrowserPageMappers on FileBrowserController {
  /// 续载过的分区按已载入条数整窗重取；未续载时维持当前页窗。
  ///
  /// 跳页与改每页条数都会先把 `meta.page` 归 0，不会误判成续载态。
  ({int page, int size}) _reloadWindow({
    required int loadedCount,
    required FilesSubPageMeta meta,
  }) {
    final accumulated = meta.page > 0 && loadedCount > meta.size;
    return (
      page: accumulated ? 0 : meta.page,
      size: accumulated ? loadedCount : meta.size,
    );
  }

  FilesSubPageMeta _metaOfNodePage(FileNodePage page) {
    return FilesSubPageMeta(
      page: page.page,
      size: page.size,
      totalElements: page.totalElements,
      totalPages: page.totalPages,
    );
  }
}
