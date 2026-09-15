import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

/// 全书视觉进度表（方案 §46 idle 显示路径 / §81 状态自 Widget 迁入）。
///
/// 窗口章用实测高度，缓存章用已测高度，其余按已测「高度/字符」比率
/// 折算；窗口条目身份变化时重建。视觉进度基于窗口几何而非
/// maxScrollExtent（动态窗口下后者不可用）；图片内部滚动时连续变化，
/// 逻辑进度可以保持不变。
class ReaderVisualExtentTable {
  Object? _cacheSource;
  List<String> _chapterIds = const [];
  List<double> _starts = const [];
  double _total = 0;
  Map<String, int>? _indexById;

  /// 全书视觉总高；未构建或无数据时为 0。
  double get totalExtent => _total;

  /// 是否已构建出可用区间。
  bool get isBuilt => _chapterIds.isNotEmpty && _total > 0;

  /// 构建/复用全书视觉进度表。
  ///
  /// [cacheSource] 为缓存判据（通常传窗口条目列表本身）；
  /// [windowEntries] 为窗口章条目，用于计算已测「高度/字符」比率；
  /// [chapterIds] 为全书章序；[measuredHeightOf] 提供章已测高度
  /// （窗口章与缓存章，无则 null）；[charCountOf] 提供解析期字数
  /// （无则 null）；[fallbackExtent] 为无任何数据章的兜底占位高度。
  void rebuildIfStale({
    required Object cacheSource,
    required List<ContinuousChapterEntry> windowEntries,
    required List<String> chapterIds,
    required double? Function(String chapterId) measuredHeightOf,
    required int? Function(String chapterId) charCountOf,
    required double fallbackExtent,
  }) {
    if (identical(_cacheSource, cacheSource)) {
      return;
    }
    _cacheSource = cacheSource;
    _indexById = null;
    double measuredExtent = 0;
    var measuredChars = 0;
    for (final entry in windowEntries) {
      if (entry.totalChars > 0 && entry.isReady && entry.totalHeight > 0) {
        measuredExtent += entry.totalHeight;
        measuredChars += entry.totalChars;
      }
    }
    final heightPerChar =
        measuredChars > 0 ? measuredExtent / measuredChars : 0.0;
    final ids = <String>[];
    final starts = <double>[];
    var running = 0.0;
    for (final id in chapterIds) {
      ids.add(id);
      starts.add(running);
      running += _extentOf(
        id,
        measuredHeightOf,
        charCountOf,
        heightPerChar,
        fallbackExtent,
      );
    }
    _chapterIds = ids;
    _starts = starts;
    _total = running;
  }

  double _extentOf(
    String chapterId,
    double? Function(String chapterId) measuredHeightOf,
    int? Function(String chapterId) charCountOf,
    double heightPerChar,
    double fallbackExtent,
  ) {
    final height = measuredHeightOf(chapterId);
    if (height != null && height > 0) {
      return height;
    }
    final chars = charCountOf(chapterId);
    if (chars != null && chars > 0 && heightPerChar > 0) {
      return chars * heightPerChar;
    }
    return fallbackExtent;
  }

  /// 章 + 章体视觉游标 → 全书视觉进度；表未构建或章未知时返回 null。
  double? progressFor(String chapterId, double chapterVisualCursor) {
    if (!isBuilt) {
      return null;
    }
    final idx = _chapterIds.indexOf(chapterId);
    if (idx < 0) {
      return null;
    }
    final start = _starts[idx];
    final end = idx + 1 < _starts.length ? _starts[idx + 1] : _total;
    final extent = end - start;
    return ((start + chapterVisualCursor.clamp(0.0, extent)) / _total).clamp(
      0.0,
      1.0,
    );
  }

  /// 章的视觉区间跨度；表未构建或章未知时返回 null。
  double? extentFor(String chapterId) {
    if (!isBuilt) {
      return null;
    }
    final idx = _chapterIds.indexOf(chapterId);
    if (idx < 0) {
      return null;
    }
    final start = _starts[idx];
    final end = idx + 1 < _starts.length ? _starts[idx + 1] : _total;
    return end - start;
  }

  /// 视觉比例 →（目标章，章体视觉游标）；表未构建时返回 null。
  (String, double)? locate(double ratio) {
    if (!isBuilt) {
      return null;
    }
    final target = ratio.clamp(0.0, 1.0) * _total;
    var idx = 0;
    while (idx < _chapterIds.length - 1 && target >= _starts[idx + 1]) {
      idx++;
    }
    final chapterStart = _starts[idx];
    final chapterEnd = idx + 1 < _starts.length ? _starts[idx + 1] : _total;
    final cursor = (target - chapterStart).clamp(
      0.0,
      chapterEnd - chapterStart,
    );
    return (_chapterIds[idx], cursor);
  }

  /// 窗口章的全书视觉进度锚点（章体起始/结束进度）。
  ///
  /// 供事务冻结映射（ReaderVisualProgressMap）把窗口物理区间锚定到
  /// 全书尺度，事务期与空闲期发布同一分母的进度；任一窗口章不在表内
  /// 时返回 null，调用方回退窗口相对映射。
  Map<String, ReaderChapterProgressAnchor>? anchorsFor(
    List<String> windowChapterIds,
  ) {
    if (!isBuilt || windowChapterIds.isEmpty) {
      return null;
    }
    final index =
        _indexById ??= {
          for (var i = 0; i < _chapterIds.length; i++) _chapterIds[i]: i,
        };
    Map<String, ReaderChapterProgressAnchor>? anchors;
    for (final id in windowChapterIds) {
      final idx = index[id];
      if (idx == null) {
        return null;
      }
      final start = _starts[idx];
      final end = idx + 1 < _starts.length ? _starts[idx + 1] : _total;
      anchors ??= <String, ReaderChapterProgressAnchor>{};
      anchors[id] = ReaderChapterProgressAnchor(
        start: _total > 0 ? (start / _total).clamp(0.0, 1.0) : 0.0,
        end: _total > 0 ? (end / _total).clamp(0.0, 1.0) : 0.0,
      );
    }
    return anchors;
  }
}
