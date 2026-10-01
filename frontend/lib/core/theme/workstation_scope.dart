import 'package:flutter/material.dart';
import 'package:omninest/core/theme/workstation_skin.dart';

/// 将全局主题转换为工位皮肤主题并在子树生效的通用壳。
///
/// 与 Files/Admin 的模块级 Scope 同源，但不叠加任何模块专属
/// ThemeExtension：适用于没有 feature 色板扩展的顶层页面
/// （通知中心、个人中心等），直接使用核心 WorkstationPalette。
class WorkstationScope extends StatelessWidget {
  const WorkstationScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = WorkstationPalette.schemeOf(base.brightness);
    return Theme(
      data: workstationThemeData(base: base, scheme: scheme),
      child: child,
    );
  }
}
