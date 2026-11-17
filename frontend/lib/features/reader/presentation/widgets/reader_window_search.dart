import 'package:omninest/features/reader/presentation/widgets/reader_block_text.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 窗口内一章的搜索源。
class WindowSearchChapter {
  const WindowSearchChapter({
    required this.chapterId,
    required this.title,
    required this.plainText,
    this.corpus,
  });

  factory WindowSearchChapter.fromBlocks({
    required String chapterId,
    required String title,
    required List<ContentBlock> blocks,
  }) {
    final corpus = ChapterSearchCorpus.fromBlocks(blocks);
    return WindowSearchChapter(
      chapterId: chapterId,
      title: title,
      plainText: corpus.plainText,
      corpus: corpus,
    );
  }

  final String chapterId;
  final String title;
  final String plainText;

  /// 由块构建时携带的源字符域映射；手搓检索串（测试夹具）时为 null。
  final ChapterSearchCorpus? corpus;

  /// 把本章检索串下标换算成块源字符域偏移。
  int toCharOffset(int localPlainIndex) {
    final corpus = this.corpus;
    if (corpus == null) {
      return localPlainIndex;
    }
    return corpus.toCharOffset(localPlainIndex);
  }
}

/// 窗口搜索命中的章内位置。
///
/// [localOffset] 是**块源字符域**偏移（分页、滚动定位与批注同一口径），可以直接交给
/// `computePage` / `restoreScrollPositionFromOffset`。由 [WindowSearchChapter.fromBlocks]
/// 构建的章走映射表；只用检索串手工构造的章没有块模型，下标原样透出。
class WindowSearchHit {
  const WindowSearchHit({
    required this.chapterId,
    required this.localOffset,
    required this.chapterTitle,
  });

  final String chapterId;
  final int localOffset;
  final String chapterTitle;
}

/// 把连续滚动窗口内的多章纯文本拼成可检索文档，并映射回章内 offset。
class ReaderWindowSearchIndex {
  ReaderWindowSearchIndex(List<WindowSearchChapter> chapters)
    : chapters = List.unmodifiable(chapters) {
    final buffer = StringBuffer();
    final segments = <_WindowSearchSegment>[];
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (i > 0) {
        buffer.writeln();
        buffer.writeln();
      }
      final bodyStart = buffer.length;
      buffer.write(chapter.plainText);
      segments.add(
        _WindowSearchSegment(
          chapter: chapter,
          globalStart: bodyStart,
          globalEnd: buffer.length,
        ),
      );
    }
    combinedText = buffer.toString();
    _segments = segments;
  }

  final List<WindowSearchChapter> chapters;
  late final String combinedText;
  late final List<_WindowSearchSegment> _segments;

  bool get isEmpty => combinedText.isEmpty;

  /// 全局 offset → 章内 hit。
  WindowSearchHit? resolve(int globalOffset) {
    if (_segments.isEmpty || globalOffset < 0) {
      return null;
    }
    for (final seg in _segments) {
      if (globalOffset >= seg.globalStart && globalOffset < seg.globalEnd) {
        final chapter = seg.chapter;
        final local = (globalOffset - seg.globalStart).clamp(
          0,
          chapter.plainText.length,
        );
        return WindowSearchHit(
          chapterId: chapter.chapterId,
          localOffset: chapter.toCharOffset(local),
          chapterTitle: chapter.title,
        );
      }
    }
    // 落在末尾换行或最后一章边界。
    final last = _segments.last.chapter;
    return WindowSearchHit(
      chapterId: last.chapterId,
      localOffset: last.toCharOffset(last.plainText.length),
      chapterTitle: last.title,
    );
  }

  /// 章标题（供结果列表展示）。
  String titleOf(int globalOffset) => resolve(globalOffset)?.chapterTitle ?? '';
}

class _WindowSearchSegment {
  const _WindowSearchSegment({
    required this.chapter,
    required this.globalStart,
    required this.globalEnd,
  });

  final WindowSearchChapter chapter;
  final int globalStart;
  final int globalEnd;
}
