import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 登录会话世代：换号或登出时递增。
///
/// 会话域 provider 在 `build` 中 watch 本 provider。世代变化属于**依赖变化**
/// 重建（`isReloading`），与 `invalidate` 的**刷新**语义（`isRefreshing`，
/// 会把上一份数据作为可访问的旧值保留给 UI）不同：重建期间旧账号数据不再
/// 作为数据暴露，页面按加载态渲染，因此换号后不会闪现上一账号的内容。
final sessionEpochProvider = NotifierProvider<SessionEpochNotifier, int>(
  SessionEpochNotifier.new,
);

class SessionEpochNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// 递增世代，驱动全部会话域 provider 以依赖变化语义重建。
  void bump() => state = state + 1;
}
