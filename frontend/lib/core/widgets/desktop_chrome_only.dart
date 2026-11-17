import 'package:flutter/widgets.dart';

import 'package:omninest/core/widgets/desktop_shell_scope.dart';

/// 只在「模块自带壳」时渲染的控件。
///
/// 桌面统一壳已经提供品牌、门户入口、通知、字号与账户；模块顶栏里的
/// 同名控件在托管态必须让位，否则一屏两套。包一层而不是给每个顶栏加
/// 参数，是因为这些控件散落在七个模块的 Row 里，逐个穿参既 noisy 又
/// 容易漏掉一处。
class DesktopChromeOnly extends StatelessWidget {
  const DesktopChromeOnly({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopShellScope.isHosted(context)
        ? const SizedBox.shrink()
        : child;
  }
}
