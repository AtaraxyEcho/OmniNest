import 'dart:async';

import 'package:omninest/core/utils/bounded_async_step.dart';

/// Flutter 测试进程统一入口：关闭启动期平台通道调用的有界等待。
///
/// widget 测试运行在 fake async 下，通道读取既不会真的返回也不会真的超时，
/// 计时器只会留在队列里，在测试结束时被判为 pending timer。生产路径的
/// 3s/6s 预算保持不变；启动门控的预算注入由 boot_gate_test 单独覆盖。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  boundedAsyncStepsEnabled = false;
  await testMain();
}
