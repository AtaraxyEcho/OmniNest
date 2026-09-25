import 'package:flutter/material.dart';

/// AnimatedSwitcher 布局回调：对退场中的旧子树排除语义。
///
/// 默认 AnimatedSwitcher 会把旧子树销毁与新子树创建写进同一批语义更新；
/// Windows 辅助功能桥仍持有旧节点 id 时会报
/// "will not be in the tree and is not the new root"。
/// 这里只排除正在销毁的旧子树，当前子树的语义不受影响。
Stack excludeExitingSemanticsStack(
  Widget? currentChild,
  List<Widget> previousChildren, {
  AlignmentGeometry alignment = AlignmentDirectional.topStart,
  StackFit fit = StackFit.loose,
}) {
  return Stack(
    alignment: alignment,
    fit: fit,
    children: <Widget>[
      for (final child in previousChildren) ExcludeSemantics(child: child),
      if (currentChild != null) currentChild,
    ],
  );
}
