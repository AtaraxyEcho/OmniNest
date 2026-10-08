import 'dart:math' as math;
import 'dart:typed_data';

/// 环境壁纸的明暗极性：决定环境面用哪一极的色栈。
///
/// 判据来自实测：暗栈遇亮壁纸与浅栈遇暗壁纸都在**薄幕布带**（immersive 顶部 α 最低处）
/// 塌成 1.8–2.4:1，方向相反而病因同一个，所以极性必须由壁纸亮度决定，
/// 不能由"设置里选了浅色"决定（docs/2026-10-08/015 §四）。
enum AppBackdropPolarity { light, dark }

/// 壁纸分带的相对亮度（0–1，WCAG 定义）。
class AppBackdropTone {
  const AppBackdropTone({
    required this.topLuminance,
    required this.bottomLuminance,
  });

  /// 上带亮度：首页时钟与眉标所在的薄幕布区，主判据。
  final double topLuminance;

  /// 下带亮度：幕布最厚处，只用于确认整幅不是"上亮下暗"的逆光构图。
  final double bottomLuminance;

  /// 白字要到 4.5:1，背景亮度需 ≤ 0.161；深墨字要到 4.5:1，背景需 ≥ 0.236。
  /// 两者之间存在谁都够不着的中间带，因此默认留在暗基准（既有设计基线），
  /// 只有上带明确够亮、且整幅不逆光时才翻浅。
  static const double lightThreshold = 0.30;
  static const double reverseLightRatio = 0.75;

  AppBackdropPolarity get polarity {
    final brightEnough = topLuminance >= lightThreshold;
    final notBacklit = bottomLuminance >= topLuminance * reverseLightRatio;
    return brightEnough && notBacklit
        ? AppBackdropPolarity.light
        : AppBackdropPolarity.dark;
  }

  @override
  String toString() =>
      'AppBackdropTone(top: ${topLuminance.toStringAsFixed(3)}, '
      'bottom: ${bottomLuminance.toStringAsFixed(3)}, $polarity)';
}

/// sRGB 相对亮度通道。
double relativeLuminanceChannel(double srgb8bit) {
  final v = srgb8bit / 255.0;
  return v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double relativeLuminance(num r, num g, num b) {
  return 0.2126 * relativeLuminanceChannel(r.toDouble()) +
      0.7152 * relativeLuminanceChannel(g.toDouble()) +
      0.0722 * relativeLuminanceChannel(b.toDouble());
}

/// 把 RGBA 像素按行切成上下两带求平均亮度。
///
/// 采样尺寸固定很小（个位数宽），所以这里按行遍历即可，不做分块优化。
AppBackdropTone toneFromRgba({
  required Uint8List rgba,
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return const AppBackdropTone(topLuminance: 0, bottomLuminance: 0);
  }
  final splitRow = height ~/ 2;
  var topSum = 0.0;
  var bottomSum = 0.0;
  var topCount = 0;
  var bottomCount = 0;
  for (var y = 0; y < height; y++) {
    final rowBase = y * width * 4;
    for (var x = 0; x < width; x++) {
      final i = rowBase + x * 4;
      final l = relativeLuminance(rgba[i], rgba[i + 1], rgba[i + 2]);
      if (y < splitRow) {
        topSum += l;
        topCount++;
      } else {
        bottomSum += l;
        bottomCount++;
      }
    }
  }
  return AppBackdropTone(
    topLuminance: topCount == 0 ? 0 : topSum / topCount,
    bottomLuminance: bottomCount == 0 ? 0 : bottomSum / bottomCount,
  );
}
