import 'package:omninest/features/reader/domain/comic_models.dart';

/// 目录节点应落到的页索引。
///
/// 页面的 `catalogNodeId` 只绑在叶子节点上：点季、卷这类聚合节点时按页面找
/// 必然落空，回退到旧进度就等于"点了目录没反应"。聚合节点用 `pageStartIndex`
/// 表达自己从第几页开始，这里按它兜底；越界的起点视为不可用，由调用方决定
/// 是保持原位还是按旧进度走，直接返回 0 会把读者扔到第一页。
int? resolveComicCatalogStartPage(ComicManifest manifest, String nodeId) {
  final directIdx = manifest.pages.indexWhere(
    (page) => page.catalogNodeId == nodeId,
  );
  if (directIdx >= 0) return directIdx;
  for (final node in manifest.catalog) {
    final start = node.pageStartIndex;
    if (node.id == nodeId && start != null && start >= 0) {
      return start < manifest.totalPages ? start : null;
    }
  }
  return null;
}

/// 滚动模式下跳页是否是无操作。
///
/// 只看页码会把"停在第 0 页下半截按 Home 回页首"一起短路掉：页码相同但页内偏移
/// 还没归零时，目标位置其实变了。翻页模式一屏就是一页，页码相同即无操作。
bool comicJumpIsNoOp({
  required int targetIndex,
  required int currentPageIndex,
  required double intraPageOffset,
  required bool isPageMode,
}) {
  if (targetIndex != currentPageIndex) {
    return false;
  }
  return isPageMode || intraPageOffset <= _topOfPageTolerance;
}

/// 页首判定容差：滚动恢复与进度落库都有亚像素抖动，按零判会永远回不到页首。
const double _topOfPageTolerance = 0.01;
