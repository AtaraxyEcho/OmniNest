import 'package:omninest/features/reader/presentation/widgets/reader_block_text.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 窗口内一章的搜索源。
class WindowSearchChapter {
  const WindowSearchChapter({
    required this.chapterId,
    required this.title,
    required this.plainText,
  });

  factory WindowSearchChapter.fromBlocks({
    required String chapterId,
    required String title,
    required List<ContentBlock> blocks,
  }) {
    return WindowSearchChapter(
      chapterId: chapterId,
      title: title,
      plainText: plainTextFromBlocks(blocks),
    );
  }

  final String chapterId;
  final String title;
  final String plainText;
}

/// 窗口搜索命中的章内位置。
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
          chapterId: chapter.chapterId,
          title: chapter.title,
          globalStart: bodyStart,
          globalEnd: buffer.length,
          textLength: chapter.plainText.length,
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
        final local = globalOffset - seg.globalStart;
        return WindowSearchHit(
          chapterId: seg.chapterId,
          localOffset: local.clamp(0, seg.textLength),
          chapterTitle: seg.title,
        );
      }
    }
    // 落在末尾换行或最后一章边界。
    final last = _segments.last;
    return WindowSearchHit(
      chapterId: last.chapterId,
      localOffset: last.textLength,
      chapterTitle: last.title,
    );
  }

  /// 章标题（供结果列表展示）。
  String titleOf(int globalOffset) => resolve(globalOffset)?.chapterTitle ?? '';
}

class _WindowSearchSegment {
  const _WindowSearchSegment({
    required this.chapterId,
    required this.title,
    required this.globalStart,
    required this.globalEnd,
    required this.textLength,
  });

  final String chapterId;
  final String title;
  final int globalStart;
  final int globalEnd;
  final int textLength;
}
