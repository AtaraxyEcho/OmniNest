import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';

/// Files 工位控件兼容层。
///
/// 实现已上移至 core/widgets/workstation_controls.dart（仅依赖
/// ColorScheme），此处保留既有名称供 Files 模块调用点零改动使用。

typedef FilesToolbarIconButton = WorkstationIconButton;
typedef FilesToolbarSegmented<T> = WorkstationSegmented<T>;
typedef FilesToolbarSegment<T> = WorkstationSegment<T>;
typedef FilesActionButton = WorkstationActionButton;
typedef FilesActionButtonVariant = WorkstationActionButtonVariant;

/// 工位输入装饰兼容入口。
InputDecoration filesWorkstationInputDecoration(
  BuildContext context, {
  String? hintText,
  IconData prefixIcon = Icons.search_rounded,
  double height = 32,
}) {
  return workstationInputDecoration(
    context,
    hintText: hintText,
    prefixIcon: prefixIcon,
    height: height,
  );
}
