import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// CSS `backdrop-filter: blur(Npx) saturate(s) brightness(b)` 的等价组合。
///
/// σ 与 CSS blur px 1:1，不乘换算系数；先模糊背景再套色彩矩阵，顺序与
/// 浏览器合成一致（外层 colorFilter、内层 blur）。矩阵前 3 行是标准
/// saturate 系数，brightness 只缩放 RGB 系数、不动 alpha 与平移列。
List<double> desktopColorMatrix({
  double saturation = 1,
  double brightness = 1,
}) {
  final s = saturation;
  final matrix = <double>[
    0.213 + 0.787 * s,
    0.715 - 0.715 * s,
    0.072 - 0.072 * s,
    0,
    0,
    0.213 - 0.213 * s,
    0.715 + 0.285 * s,
    0.072 - 0.072 * s,
    0,
    0,
    0.213 - 0.213 * s,
    0.715 - 0.715 * s,
    0.072 + 0.928 * s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
  if (brightness != 1) {
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        matrix[row * 5 + col] *= brightness;
      }
    }
  }
  return matrix;
}

/// 背景图的 `filter: saturate(s) brightness(b)`，不含 blur。
ColorFilter desktopColorGrade({double saturation = 1, double brightness = 1}) =>
    ColorFilter.matrix(
      desktopColorMatrix(saturation: saturation, brightness: brightness),
    );

ImageFilter desktopGlassFilter({
  required double blur,
  double saturation = 1,
  double brightness = 1,
}) {
  final blurFilter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
  // 无调色时不要套 compose：`ImageFilter.compose` 会多一层离屏 pass，
  // 在 4K 窗口 + 动态背景下这层 pass 与 blur 同量级，而像素与单层 blur
  // 完全一致（saturate(1) brightness(1) 是恒等矩阵）。
  if ((saturation - 1).abs() < 1e-3 && (brightness - 1).abs() < 1e-3) {
    return blurFilter;
  }
  return ImageFilter.compose(
    outer: desktopColorGrade(saturation: saturation, brightness: brightness),
    inner: blurFilter,
  );
}

/// 半透明面板的通用玻璃层：只模糊背后的内容，不裁剪子内容的阴影。
///
/// 走 `BackdropFilter.grouped`：有祖先 [BackdropGroup] 时同组共享一次
/// backdrop 取样，N 个面板不再各自捕获一遍背后的场景。各面板仍用自己
/// 的 σ / 色彩矩阵，所以 30/36/24 可以共存。无祖先组时回退为普通
/// backdrop（单测与独立使用不受影响）。
///
/// 不要为了「缩小回读面积」把满幅条单独摘出组：真机 A/B（4K、150 帧、
/// FrameTiming，见 `docs/2026-11-16/003` §11.2）实测不分组 4.15ms、
/// 分组 1.52ms——成本由**捕获次数**主导，联合包围盒变大远不如多捕获一次贵。
class DesktopGlassSurface extends StatelessWidget {
  const DesktopGlassSurface({
    required this.child,
    required this.borderRadius,
    this.blur = 24,
    this.saturation = 1.3,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final double saturation;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter.grouped(
        // 组合滤镜（blur + saturate）用默认构造包原 filter，像素与
        // `filter:` 完全一致；bounded 与 compose 不可组合，故不迁移到
        // `ImageFilterConfig.blur`。
        filterConfig: ImageFilterConfig(
          desktopGlassFilter(blur: blur, saturation: saturation),
        ),
        child: child,
      ),
    );
  }
}
