import 'package:flutter/widgets.dart';

/// 标记当前页面由应用级**桌面统一壳**承载。
///
/// 与 [MobileShellScope] 同一手法、不同形态：桌面壳已经提供了标题栏
/// （品牌 / 搜索 / 通知 / 任务 / 账户 / 窗口控件），模块页必须收起自己
/// 那条重复的顶栏，否则同一屏会出现两套品牌与两个搜索入口——这正是
/// 「每个模块都是一个子系统」的观感来源。
///
/// 模块内部的分区导航（影视的 Films/Series、文件的目录树、管理台的
/// 分区轨）属于页面内容，不在此作用域的收起范围内。
class DesktopShellScope extends InheritedWidget {
  const DesktopShellScope({
    required this.hosted,
    required super.child,
    super.key,
  });

  final bool hosted;

  /// 当前页面是否由桌面统一壳承载。
  static bool isHosted(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<DesktopShellScope>()
            ?.hosted ??
        false;
  }

  @override
  bool updateShouldNotify(DesktopShellScope oldWidget) {
    return hosted != oldWidget.hosted;
  }
}
