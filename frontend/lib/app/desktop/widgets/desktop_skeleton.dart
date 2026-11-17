import 'package:flutter/material.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 条目级骨架（样例新版 polish.css）：保留真实布局，每个条目画成
/// 「封面 + 两条文本占位」，整块有一次缓慢扫光，而不是页面中央一个转圈。
class DesktopSkeletonBox extends StatefulWidget {
  const DesktopSkeletonBox({
    this.width,
    this.height = 14,
    this.radius = 8,
    this.index = 0,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  /// 条目序号：`:nth-child(2n)` 与 `(3n)` 的 .18/.36s 延迟换算成循环
  /// 动画的相位差，不再为每一格创建 Timer。
  final int index;

  @override
  State<DesktopSkeletonBox> createState() => _DesktopSkeletonBoxState();
}

class _DesktopSkeletonBoxState extends State<DesktopSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.skeletonSweep,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 减弱动效时样例把骨架动画整体关掉，而不是继续无限重复。
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final base = skin.raise2;
    final highlight = Color.lerp(base, skin.text, 0.08)!;
    final childIndex = widget.index + 1;
    final phase =
        childIndex % 3 == 0 ? 0.225 : (childIndex % 2 == 0 ? 0.1125 : 0.0);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final sweep = DesktopMotion.skeletonCurve.transform(
          (_controller.value - phase + 1) % 1,
        );
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + sweep * 3.2, 0),
              end: Alignment(-0.6 + sweep * 3.2, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

/// 照片网格的骨架：两行 justified 占位，高度与真实缩略一致。
class DesktopSkeletonPhotoGrid extends StatelessWidget {
  const DesktopSkeletonPhotoGrid({
    this.targetHeight = 200,
    this.rows = 2,
    super.key,
  });

  final double targetHeight;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var row = 0; row < rows; row++) ...[
            SizedBox(
              height: targetHeight,
              child: Row(
                children: [
                  for (var col = 0; col < 4; col++)
                    Expanded(
                      flex: const [3, 2, 4, 3][col],
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: DesktopSkeletonBox(
                          height: targetHeight - 8,
                          radius: 10,
                          index: row * 4 + col,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// 列表骨架：圆形/方形缩略 + 两条文本条，按行错峰。
class DesktopSkeletonRows extends StatelessWidget {
  const DesktopSkeletonRows({this.count = 6, this.avatar = true, super.key});

  final int count;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                DesktopSkeletonBox(
                  width: avatar ? 36 : 46,
                  height: avatar ? 36 : 32,
                  radius: avatar ? 18 : 9,
                  index: i * 4,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 样例 `polish.css:225-228`：文本条是 66% × 11 与
                      // 40% × 9 的圆头条，宽度按百分比而不是固定 px。
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.66,
                          child: DesktopSkeletonBox(
                            height: 11,
                            radius: 5.5,
                            index: i * 4 + 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.40,
                          child: DesktopSkeletonBox(
                            height: 9,
                            radius: 4.5,
                            index: i * 4 + 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                DesktopSkeletonBox(width: 64, height: 12, index: i * 4 + 3),
              ],
            ),
          ),
      ],
    );
  }
}
