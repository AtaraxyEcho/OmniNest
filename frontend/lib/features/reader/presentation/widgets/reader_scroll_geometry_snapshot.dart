import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

/// 位置解析的几何来源（方案 §6）。
///
/// [LiveScrollGeometrySource] 读取控制器当前（可变）几何；
/// [SnapshotScrollGeometrySource] 只读 ScrollStart 冻结的不可变快照。
/// ACTIVE_SCROLL 期间解析必须使用快照来源，禁止回退 Live。
sealed class ReaderScrollGeometrySource {
  const ReaderScrollGeometrySource();
}

/// Live 几何：控制器当前窗口几何（可随后台测量变化）。
class LiveScrollGeometrySource extends ReaderScrollGeometrySource {
  const LiveScrollGeometrySource();
}

/// 快照几何：一次滚动手势期间唯一可信坐标系。
class SnapshotScrollGeometrySource extends ReaderScrollGeometrySource {
  const SnapshotScrollGeometrySource(this.snapshot);

  final ReaderGeometrySnapshot snapshot;
}

/// 章节几何快照（方案 §4-5）：块级累积高度的不可变复制。
///
/// cumulativeHeights / blockCharPrefixes / blocks 必须不可变复制，
/// 不与 Live 几何共享可变列表——后台精测原地更新不得穿透快照。
@immutable
class ReaderGeometryEntry {
  const ReaderGeometryEntry({
    required this.chapterId,
    required this.chapterStart,
    required this.totalHeight,
    required this.blockCount,
    required this.cumulativeHeights,
    required this.totalChars,
    required this.blockCharPrefixes,
    required this.isReady,
    required this.blocks,
  });

  final String chapterId;

  /// 章节在窗口坐标中的起点（前缀章高度 + chrome 之前的部分与控制器
  /// prefixHeightOf 同口径）。
  final double chapterStart;

  /// 章体总高度。
  final double totalHeight;

  /// 块数（与 cumulativeHeights 对齐时块级几何可用）。
  final int blockCount;

  /// 块级累积高度（不可变复制）。
  final List<double> cumulativeHeights;

  final int totalChars;

  /// 块级字符前缀（不可变复制，长度 = 块数 + 1）。
  final List<int> blockCharPrefixes;

  final bool isReady;

  /// 内容块（浅不可变复制；块对象本身不原地变更，可安全共享实例）。
  final List<ContentBlock> blocks;

  /// 与控制器 effectiveExtentOf 同口径的章占位高度。
  double get effectiveExtent =>
      ReaderContinuousScrollController.chapterHeaderExtent +
      totalHeight +
      (isReady
          ? ReaderContinuousScrollController.chapterTrailingExtent
          : ReaderContinuousScrollController.chapterTrailingLoadingExtent);

  /// 合成为位置解析所需的章条目视图。
  ContinuousChapterEntry toEntry() {
    return ContinuousChapterEntry(
      chapterId: chapterId,
      title: '',
      blockCount: blockCount,
      cumulativeHeights: cumulativeHeights,
      totalHeight: totalHeight,
      totalChars: totalChars,
      isReady: isReady,
      blocks: blocks,
      blockCharPrefixes: blockCharPrefixes,
    );
  }
}

/// 一次滚动手势期间唯一可信的窗口几何快照（方案 §4）。
///
/// 包含窗口章节顺序（§5）：快照自身保存章节顺序，不能只用 Map。
/// 同一手势期间 Progress 与 Position 必须使用同一份快照（§16）。
@immutable
class ReaderGeometrySnapshot {
  const ReaderGeometrySnapshot({
    required this.revision,
    required this.chapterIds,
    required this.chapters,
  });

  /// 从控制器 Live 几何构建不可变快照（方案 §10：ScrollStart 时生成）。
  factory ReaderGeometrySnapshot.fromController(
    ReaderContinuousScrollController controller, {
    required int revision,
  }) {
    final ids = <String>[];
    final chapters = <String, ReaderGeometryEntry>{};
    for (final entry in controller.entries) {
      ids.add(entry.chapterId);
      chapters[entry.chapterId] = ReaderGeometryEntry(
        chapterId: entry.chapterId,
        chapterStart: controller.prefixHeightOf(entry.chapterId),
        totalHeight: entry.totalHeight,
        blockCount: entry.blockCount,
        cumulativeHeights: List<double>.unmodifiable(entry.cumulativeHeights),
        totalChars: entry.totalChars,
        blockCharPrefixes: List<int>.unmodifiable(entry.blockCharPrefixes),
        isReady: entry.isReady,
        blocks: List<ContentBlock>.unmodifiable(entry.blocks),
      );
    }
    return ReaderGeometrySnapshot(
      revision: revision,
      chapterIds: List<String>.unmodifiable(ids),
      chapters: Map<String, ReaderGeometryEntry>.unmodifiable(chapters),
    );
  }

  /// 快照构建时的几何版本号（诊断 ACTIVE 与 LIVE 是否同源）。
  final int revision;

  /// 窗口章节顺序。
  final List<String> chapterIds;

  final Map<String, ReaderGeometryEntry> chapters;

  bool contains(String chapterId) => chapters.containsKey(chapterId);

  ReaderGeometryEntry? chapterOf(String chapterId) => chapters[chapterId];

  double prefixOf(String chapterId) => chapters[chapterId]?.chapterStart ?? 0;

  /// 章体视觉前缀累计（不含 chrome）：进度分母与 cursor 同口径。
  double bodyStartOf(String chapterId) {
    var sum = 0.0;
    for (final id in chapterIds) {
      if (id == chapterId) {
        break;
      }
      sum += chapters[id]?.totalHeight ?? 0;
    }
    return sum;
  }

  double get totalBodyExtent {
    var sum = 0.0;
    for (final id in chapterIds) {
      sum += chapters[id]?.totalHeight ?? 0;
    }
    return sum;
  }
}
