import 'package:flutter/material.dart';

/// 内容骨架的结构类型。
///
/// 保留枚举以兼容既有调用点；加载态统一为居中指示器，
/// 不再渲染与最终内容同形的骨架占位。
enum AppLoadingLayout { list, grid, detail }

/// 通用加载指示器：首屏/列表/详情统一使用居中 CircularProgressIndicator。
///
/// 主流方案：初始加载用居中指示器，已有内容时用下拉刷新保留原内容，
/// 避免骨架占位与真实布局错位造成的闪烁与二次跳动。
class AppLoading extends StatelessWidget {
  const AppLoading({super.key})
    : _simple = false,
      layout = AppLoadingLayout.list,
      gridAspectRatio = 1;

  const AppLoading.grid({this.gridAspectRatio = 1, super.key})
    : assert(gridAspectRatio > 0),
      _simple = false,
      layout = AppLoadingLayout.grid;

  const AppLoading.detail({super.key})
    : _simple = false,
      layout = AppLoadingLayout.detail,
      gridAspectRatio = 1;

  const AppLoading.simple({super.key})
    : _simple = true,
      layout = AppLoadingLayout.list,
      gridAspectRatio = 1;

  // ignore: unused_field
  final bool _simple;
  final AppLoadingLayout layout;

  // ignore: unused_field
  final double gridAspectRatio;

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
