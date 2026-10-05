import 'package:flutter/widgets.dart';

/// 模块分段区的左右滑动切换：横向快速滑动切换相邻分段。
///
/// 采用手势竞技场让位策略——页内的横向滚动轨道（海报/专辑轨）优先
/// 消费拖动，只有落在非滚动区域的手势才触发分段切换，避免与内容
/// 轨道抢手势。纵向滚动不受影响。
class MobileSectionSwipe extends StatelessWidget {
  const MobileSectionSwipe({
    required this.child,
    required this.onSwipe,
    super.key,
  });

  /// true = 向左滑（下一栏），false = 向右滑（上一栏）。
  final Widget child;
  final ValueChanged<bool> onSwipe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -380) {
          onSwipe(true);
        } else if (velocity > 380) {
          onSwipe(false);
        }
      },
      child: child,
    );
  }
}

/// 按分段次序切到相邻项；返回 null 表示已在边缘。
T? adjacentSection<T>(List<T> sections, T current, bool toNext) {
  final index = sections.indexOf(current);
  if (index < 0) {
    return null;
  }
  final next = toNext ? index + 1 : index - 1;
  if (next < 0 || next >= sections.length) {
    return null;
  }
  return sections[next];
}
