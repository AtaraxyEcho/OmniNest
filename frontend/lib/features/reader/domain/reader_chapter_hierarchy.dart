import 'package:omninest/features/reader/domain/reader_models.dart';

/// 统一处理阅读目录的父子层级与折叠可见性。
abstract final class ReaderChapterHierarchy {
  /// 返回考虑所有折叠祖先后的可见章节。
  static List<ReaderChapter> visibleChapters(
    List<ReaderChapter> chapters,
    Set<String> collapsedIds,
  ) {
    final visible = <ReaderChapter>[];
    final ancestors = <ReaderChapter>[];

    for (final chapter in chapters) {
      while (ancestors.isNotEmpty && ancestors.last.level >= chapter.level) {
        ancestors.removeLast();
      }

      final hidden = ancestors.any(
        (ancestor) => collapsedIds.contains(ancestor.id),
      );
      if (!hidden) {
        visible.add(chapter);
      }
      ancestors.add(chapter);
    }

    return visible;
  }

  /// 判断指定章节后是否紧跟更深层级的子章节。
  static bool hasChildren(List<ReaderChapter> chapters, ReaderChapter chapter) {
    final index = chapters.indexOf(chapter);
    if (index < 0 || index >= chapters.length - 1) {
      return false;
    }
    return chapters[index + 1].level > chapter.level;
  }
}
