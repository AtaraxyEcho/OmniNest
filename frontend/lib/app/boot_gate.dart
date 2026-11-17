import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动门控总预算：任何门控 provider 悬挂都不允许让 /boot 无限等待。
///
/// go_router 的 redirect 只在 refreshListenable 变化时重算，而 AsyncNotifier
/// 一旦卡在 AsyncLoading 就再也不会 notify。看门狗到期后主动触发一次刷新，
/// 并让 redirect 把三个「检查在途」标志一律视为结束，落到可交互的登录页或
/// 服务器设置页；后台检查完成后仍会照常通知并纠正最终落位。
const Duration bootGateBudget = Duration(seconds: 5);

/// 单独成 Provider 便于测试注入短预算，不必真的等五秒。
final bootGateBudgetProvider = Provider<Duration>((ref) => bootGateBudget);

final bootGateElapsedProvider = NotifierProvider<BootGate, bool>(BootGate.new);

class BootGate extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    _timer = Timer(ref.watch(bootGateBudgetProvider), () {
      state = true;
    });
    ref.onDispose(() => _timer?.cancel());
    return false;
  }
}

/// 创建路由刷新源并接上看门狗：到期自增一次，强制重算 redirect。
ValueNotifier<int> installBootGate(Ref ref) {
  final refreshListenable = ValueNotifier<int>(0);
  ref.listen(bootGateElapsedProvider, (previous, next) {
    if (next) {
      refreshListenable.value++;
    }
  });
  return refreshListenable;
}

/// 到期前的 loading 如实上报；到期后一律按「检查已结束」放行。
bool bootGateAllowsWaiting(Ref ref) => !ref.read(bootGateElapsedProvider);
