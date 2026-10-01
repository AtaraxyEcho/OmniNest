import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

/// Files 工位弹窗兼容层。
///
/// 实现已上移至 core/widgets/workstation_dialog.dart（仅依赖
/// ColorScheme），此处保留既有名称供 Files 模块调用点零改动使用。

typedef FilesFocusTrap = WorkstationFocusTrap;
typedef FilesDialogFrame = WorkstationDialogFrame;
typedef FilesDialogSectionLabel = WorkstationDialogSectionLabel;

/// 建筑极简主义弹窗入口（Files 兼容入口）。
Future<T?> showFilesDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = true,
  Color? barrierColor,
}) {
  return showWorkstationDialog<T>(
    context: context,
    builder: builder,
    dismissible: dismissible,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor,
  );
}

/// 标准确认弹窗（Files 兼容入口）。
Future<bool> showFilesConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) {
  return showWorkstationConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: destructive,
  );
}

/// 高危破坏性二次确认（Files 兼容入口）。
Future<bool> showFilesDestructiveConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmPhrase,
  String? confirmLabel,
}) {
  return showWorkstationDestructiveConfirm(
    context,
    title: title,
    message: message,
    confirmPhrase: confirmPhrase,
    confirmLabel: confirmLabel,
  );
}
