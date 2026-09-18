/// 图片解码宽度量化工具。
///
/// 窗口最大化、无边框切换与拖拽缩放时，布局约束会连续变化；若
/// `memCacheWidth`/`cacheWidth` 严格跟随当前约束，图片组件会反复更换
/// 解码键并触发重复解码，表现为卡顿。统一将显示尺寸向上量化到离散
/// 档位，同一视觉档位内复用已解码位图。
library;

/// 按步长向上量化逻辑显示宽度对应的解码像素宽。
///
/// [logicalWidth] 为逻辑像素；[devicePixelRatio] 为设备像素比；
/// [scale] 用于超采样（如阅读封面 2x）。非法输入返回 [min]。
int quantizedDecodeWidth({
  required double logicalWidth,
  required double devicePixelRatio,
  int step = 256,
  int min = 128,
  int max = 4096,
  double scale = 1,
}) {
  if (min < 1) {
    min = 1;
  }
  if (max < min) {
    max = min;
  }
  if (step < 1) {
    step = 1;
  }
  if (!logicalWidth.isFinite ||
      logicalWidth <= 0 ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0) {
    return min;
  }
  final raw = logicalWidth * devicePixelRatio * scale;
  if (!raw.isFinite || raw <= 0) {
    return min;
  }
  final stepped = ((raw / step).ceil() * step).round();
  return stepped.clamp(min, max);
}

/// 将像素宽吸附到固定档位列表（取第一个 ≥ [value] 的档位）。
int quantizeDecodeTier(int value, List<int> tiers) {
  if (tiers.isEmpty) {
    return value < 1 ? 1 : value;
  }
  final sorted = List<int>.of(tiers)..sort();
  for (final tier in sorted) {
    if (value <= tier) {
      return tier;
    }
  }
  return sorted.last;
}

/// 像素尺寸 → 按 [step] 向上量化，供已有 int 解码宽调用点使用。
int quantizeDecodePixels(
  int value, {
  int step = 256,
  int min = 128,
  int max = 4096,
}) {
  if (step < 1) {
    step = 1;
  }
  if (min < 1) {
    min = 1;
  }
  if (max < min) {
    max = min;
  }
  if (value <= 0) {
    return min;
  }
  final stepped = ((value / step).ceil() * step);
  return stepped.clamp(min, max);
}
