import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;

/// 自绘底部面板的模态语义。
///
/// Material 的 `showModalBottomSheet` 不给面板内容挂任何 role（`bottom_sheet.dart`
/// 里只有 `Semantics` 的传播与命中行为设置），读屏因此听不到"这是一个对话框"。
/// 走 `WorkstationDialogFrame` 的面板已由该框架补上 role；其余各模块自己画内容的
/// 面板在 builder 根节点包本组件，语义与工位弹窗一致。
///
/// 只进语义树，不参与布局与绘制，视觉零位移。
class MobileSheetSemantics extends StatelessWidget {
  const MobileSheetSemantics({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      role: SemanticsRole.dialog,
      child: child,
    );
  }
}
