import 'package:flutter/foundation.dart';

/// 开发期诊断日志：仅 debug 模式输出，release 构建编译期消除。
///
/// 业务代码不得直接调用 [debugPrint]——release 构建会把内部诊断
/// （播放器状态、错误堆栈等）写进用户日志。架构棘轮测试
/// `no_ungated_debug_print_test.dart` 阻止新增裸调用。
void devLog(String message, {int? wrapWidth}) {
  if (kDebugMode) {
    debugPrint(message, wrapWidth: wrapWidth);
  }
}

/// 开发期诊断堆栈：仅 debug 模式输出。
void devLogStack({String? label, StackTrace? stackTrace, int? maxFrames}) {
  if (kDebugMode) {
    debugPrintStack(label: label, stackTrace: stackTrace, maxFrames: maxFrames);
  }
}
