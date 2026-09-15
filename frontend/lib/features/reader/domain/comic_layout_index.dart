import 'package:omninest/features/reader/domain/comic_models.dart';

/// 漫画页面布局索引 — 维护每页的高度和偏移。
///
/// 图片未加载前用宽高比预估，加载后用真实布局高度修正。
/// 用于滚动模式精确定位当前页和页内偏移。
class ComicLayoutIndex {
  ComicLayoutIndex(this._pages, {double contentWidth = 800.0})
    : _contentWidth = contentWidth;

  final List<ComicPage> _pages;

  /// 实际渲染内容宽度（用于估算页面高度）。
  double _contentWidth;

  /// 当前内容宽度。
  double get contentWidth => _contentWidth;

  /// 更新内容宽度，宽度变化时清空偏移缓存。
  ///
  /// 返回 true 表示宽度发生了显著变化（调用方应重新定位锚点）。
  bool updateContentWidth(double newWidth) {
    if ((_contentWidth - newWidth).abs() < 1.0) return false;
    _contentWidth = newWidth;
    // 宽度变化，估算高度全部失效
    _offsets = null;
    return true;
  }

  /// 每页的布局高度（0 表示未测量）。
  final List<double> _heights = [];

  /// 累积偏移缓存（惰性计算，高度变化时失效）。
  List<double>? _offsets;
  double _totalHeight = 0;

  int get length => _pages.length;

  /// 总内容高度。
  double get totalHeight {
    _ensureOffsets();
    return _totalHeight;
  }

  /// 更新指定页的真实布局高度。
  void updateHeight(int index, double height) {
    if (index < 0 || index >= _pages.length) return;
    while (_heights.length < _pages.length) {
      _heights.add(0);
    }
    if ((_heights[index] - height).abs() > 0.5) {
      _heights[index] = height;
      // 失效缓存
      _offsets = null;
    }
  }

  /// 获取指定页的高度。
  double pageHeight(int index, double viewportHeight) {
    if (index >= 0 && index < _heights.length && _heights[index] > 0) {
      return _heights[index];
    }
    return _estimatedHeight(index, viewportHeight);
  }

  /// 根据滚动偏移计算当前页和页内偏移。
  (int pageIndex, double intraOffset) hitTest(
    double scrollOffset,
    double viewportHeight,
  ) {
    _ensureOffsets();
    if (_offsets!.isEmpty) return (0, 0.0);

    // 二分查找包含 scrollOffset 的页
    var lo = 0;
    var hi = _offsets!.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final pageTop = _offsets![mid];
      final pageBottom =
          mid + 1 < _offsets!.length ? _offsets![mid + 1] : _totalHeight;

      if (scrollOffset >= pageTop && scrollOffset < pageBottom) {
        final h = pageBottom - pageTop;
        final intra =
            h > 0 ? ((scrollOffset - pageTop) / h).clamp(0.0, 1.0) : 0.0;
        return (mid, intra);
      }
      if (scrollOffset < pageTop) {
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }

    // 超出范围
    if (scrollOffset >= _totalHeight) {
      return (_offsets!.length - 1, 1.0);
    }
    return (0, 0.0);
  }

  /// 根据 pageIndex + intraOffset 计算目标滚动偏移。
  double scrollTo(int pageIndex, double intraOffset, double viewportHeight) {
    _ensureOffsets();
    if (_offsets!.isEmpty) return 0;
    final clampedIndex = pageIndex.clamp(0, _offsets!.length - 1);
    final pageTop = _offsets![clampedIndex];
    final h = pageHeight(clampedIndex, viewportHeight);
    return (pageTop + h * intraOffset).clamp(0.0, _totalHeight);
  }

  /// 确保累积偏移已计算。
  void _ensureOffsets() {
    if (_offsets != null && _offsets!.length == _pages.length) return;
    _offsets = List.filled(_pages.length, 0.0);
    double acc = 0;
    for (var i = 0; i < _pages.length; i++) {
      _offsets![i] = acc;
      acc += _heightForEstimation(i);
    }
    _totalHeight = acc;
  }

  /// 获取用于估算的高度（真实高度或基于宽高比的预估）。
  double _heightForEstimation(int index) {
    if (index < _heights.length && _heights[index] > 0) {
      return _heights[index];
    }
    return _estimatedHeight(index, contentWidth);
  }

  /// 基于图片宽高比预估页面高度。
  ///
  /// 高度 = contentWidth × (imageHeight / imageWidth)。
  /// 无尺寸信息时使用 3:4 默认比例。
  double _estimatedHeight(int index, double viewportHeight) {
    if (index < 0 || index >= _pages.length) return viewportHeight;
    final page = _pages[index];
    if (page.width != null &&
        page.height != null &&
        page.width! > 0 &&
        page.height! > 0) {
      return contentWidth * (page.height! / page.width!);
    }
    // 无尺寸信息：默认 3:4 竖图
    return contentWidth * (4.0 / 3.0);
  }
}
