import 'package:flutter/foundation.dart';

/// 背景库临时调试日志。排查完后可整体移除。
void backdropDebug(String message) {
  if (kDebugMode) {
    debugPrint('[Backdrop] $message');
  }
}
