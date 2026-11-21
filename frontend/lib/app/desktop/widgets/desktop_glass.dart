import 'dart:ui' show BlurStyle, ImageFilter, MaskFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

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
        child: RepaintBoundary(
          // 子内容单独成层：按钮 hover、进度更新这类局部重绘不会再顺着
          // `BackdropFilter` 把这一格的背板重新取样 + 重新高斯一遍。
          child: child,
        ),
      ),
    );
  }
}

/// CSS `box-shadow` 语义的外侧投影：模糊只落在边框盒之外，盒内不染色。
///
/// [BoxShadow] 走的是 `BlurStyle.normal`：模糊后的**实心**形状连内部一起
/// 铺满，填充不透明时被盖住看不出来，一旦填充透明（首页 Hero 在壁纸态
/// 就是 `background: transparent`），两条阴影合起来相当于在整张卡上盖了
/// 一层 76% 的黑纱——即「黑色遮罩玻璃」的来源。浏览器不会这样：
/// `box-shadow` 按规范被裁在 border-box 外侧。
///
/// 这里在独立图层里画完阴影，再把边框盒圆角以内的部分 `clear` 掉，等价于
/// 浏览器的裁剪。只用 `BlurStyle.outer` 不够：负 spread 会把阴影形状缩到
/// 盒内，外扩的模糊带仍会从左右两侧的内边渗进来。
class DesktopOutsetShadow extends StatelessWidget {
  const DesktopOutsetShadow({
    required this.borderRadius,
    required this.shadows,
    required this.child,
    super.key,
  });

  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OutsetShadowPainter(
        borderRadius: borderRadius,
        shadows: shadows,
      ),
      child: child,
    );
  }
}

class _OutsetShadowPainter extends CustomPainter {
  const _OutsetShadowPainter({
    required this.borderRadius,
    required this.shadows,
  });

  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) {
      return;
    }
    final resolved = borderRadius.resolve(TextDirection.ltr);
    final base = Rect.fromLTWH(0, 0, size.width, size.height);
    RRect boxFor(BoxShadow shadow) {
      // 与 CSS 一致：spread 同时收缩盒边与圆角，圆角最小到 0。
      final spread = shadow.spreadRadius;
      final rect = base.shift(shadow.offset).inflate(spread);
      return RRect.fromRectAndCorners(
        rect,
        topLeft: _corner(resolved.topLeft, spread),
        topRight: _corner(resolved.topRight, spread),
        bottomLeft: _corner(resolved.bottomLeft, spread),
        bottomRight: _corner(resolved.bottomRight, spread),
      );
    }

    // 图层要裹住所有阴影的外扩范围，否则模糊带会被自身边界裁断。
    Rect layerBounds = base;
    for (final shadow in shadows) {
      layerBounds = layerBounds.expandToInclude(
        boxFor(shadow).outerRect.inflate(shadow.blurRadius * 3),
      );
    }

    canvas.saveLayer(layerBounds, Paint());
    for (final shadow in shadows) {
      canvas.drawRRect(
        boxFor(shadow),
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma),
      );
    }
    // 内部挖空：只留边框盒外侧的模糊带，不给透明填充染底色。
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        base,
        topLeft: resolved.topLeft,
        topRight: resolved.topRight,
        bottomLeft: resolved.bottomLeft,
        bottomRight: resolved.bottomRight,
      ),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  Radius _corner(Radius radius, double spread) {
    final value = (radius.x + spread).clamp(0.0, double.infinity);
    return Radius.circular(value);
  }

  @override
  bool shouldRepaint(_OutsetShadowPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        !listEquals(oldDelegate.shadows, shadows);
  }
}
