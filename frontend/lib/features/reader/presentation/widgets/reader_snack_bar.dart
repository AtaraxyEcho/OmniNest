import 'package:flutter/material.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

/// 展示阅读模块瞬时反馈，转发全局反馈门面。
///
/// [action] 沿用 SnackBarAction 形态以保持既有调用点兼容；宽度上限、
/// 队列合并与顶部居中定位由门面统一承担。
void showReaderSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  showOmniFeedback(
    context,
    message,
    actionLabel: action?.label,
    onAction: action?.onPressed,
    duration: duration,
  );
}
