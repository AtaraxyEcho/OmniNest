import 'package:flutter/material.dart';

/// 通用加载指示器：首屏/列表/详情统一使用居中 CircularProgressIndicator。
///
/// 初始加载用居中指示器，已有内容时用下拉刷新保留原内容，避免骨架占位与
/// 真实布局错位造成的闪烁与二次跳动；本组件不区分列表/网格/详情形态。
class AppLoading extends StatelessWidget {
  const AppLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
