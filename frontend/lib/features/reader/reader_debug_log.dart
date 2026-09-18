import 'package:omninest/core/log/dev_log.dart';

/// 阅读模块开发期诊断日志；统一委托 [devLog]，release 构建零输出。
void readerDebugLog(String message, {int? wrapWidth}) {
  devLog(message, wrapWidth: wrapWidth);
}
