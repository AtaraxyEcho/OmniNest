import 'package:flutter/material.dart';

import 'package:omninest/app/browser_theme_color.dart';

/// 把浏览器界面栏配色绑到当前主题的页面底色上。
///
/// 必须挂在 `MaterialApp` 的 `builder` 里：那里才拿得到已按 `themeMode` 与
/// 系统亮度解析完的 `Theme`。挂在根 widget 之上只能自己再推一遍极性，
/// 就会和真正生效的主题不一致。
class BrowserThemeColorBinding extends StatefulWidget {
  const BrowserThemeColorBinding({required this.child, super.key});

  final Widget child;

  @override
  State<BrowserThemeColorBinding> createState() =>
      _BrowserThemeColorBindingState();
}

class _BrowserThemeColorBindingState extends State<BrowserThemeColorBinding> {
  Color? _applied;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final surface = Theme.of(context).scaffoldBackgroundColor;
    if (_applied == surface) {
      return;
    }
    _applied = surface;
    setBrowserThemeColor(surface);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
