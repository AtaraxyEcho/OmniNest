import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';

/// 阅读器护眼暖色与亮度滤镜（1:1 对齐样例 `.bk-dim` 与 `.bk-warm`，z-index: 2）。
///
/// 重要：只包裹阅读正文画布层，位于顶底栏（z=3）、毛玻璃浮层（z=6）与划词工具条（z=90）
/// 之下，确保亮度调至 30% 时控制栏与设置滑块依然清晰可读。
/// 暖色采用 `ColorFiltered(BlendMode.modulate)` 直接调制正文内容，数学上等价于
/// CSS `mix-blend-mode: multiply`，绝不产生不透明橙色遮罩。
class ReaderComfortFilter extends StatelessWidget {
  const ReaderComfortFilter({
    required this.brightness,
    required this.warmth,
    required this.child,
    super.key,
  });

  /// 亮度 30..100（100 为原始亮度）。
  final int brightness;

  /// 护眼暖色 0..60（0 为关闭）。
  final int warmth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clampedBright = brightness.clamp(30, 100);
    final clampedWarm = warmth.clamp(0, 60);
    final warmAlpha = (clampedWarm / 100.0) * 0.34;
    final dimAlpha = ((100 - clampedBright) / 100.0) * 0.70;
    final warmTint =
        Color.lerp(
          Colors.white,
          ReaderReadingPalette.comfortWarmTint,
          warmAlpha,
        )!;

    Widget content = child;
    if (warmAlpha > 0.001) {
      content = ColorFiltered(
        colorFilter: ColorFilter.mode(warmTint, BlendMode.modulate),
        child: content,
      );
    }

    if (dimAlpha <= 0.001) {
      return content;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        IgnorePointer(
          child: AnimatedContainer(
            duration: MotionToken.reduced(
              context,
              const Duration(milliseconds: 260),
            ),
            color: Colors.black.withValues(alpha: dimAlpha),
          ),
        ),
      ],
    );
  }
}
