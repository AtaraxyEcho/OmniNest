import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

final appBackdropSceneControllerProvider =
    NotifierProvider<AppBackdropSceneController, AppBackdropSceneState>(
      AppBackdropSceneController.new,
    );

/// 汇总前景模块背景意图并选择最近激活场景。
class AppBackdropSceneController extends Notifier<AppBackdropSceneState> {
  final Map<String, _OwnedBackdropPolicy> _policies =
      <String, _OwnedBackdropPolicy>{};
  int _sequence = 0;
  int _emptyGraceToken = 0;

  @override
  AppBackdropSceneState build() => const AppBackdropSceneState();

  /// 注册或更新前景模块的背景策略。
  ///
  /// [owner] 是前景模块的稳定标识，[policy] 是模块请求的背景策略。
  /// 返回值是本次注册的租约，释放时可用于避免删除同名的新注册。
  /// 每次注册都签发新租约：整树重挂后新作用域持新租约，旧作用域的
  /// 释放按旧租约号匹配失败，不会误删新注册。
  int request(String owner, AppBackdropPolicy policy) {
    if (!ref.mounted) {
      return 0;
    }
    _sequence++;
    _emptyGraceToken++;
    _policies[owner] = _OwnedBackdropPolicy(
      policy: policy,
      sequence: _sequence,
    );
    _resolve();
    return _sequence;
  }

  /// 释放 [owner] 持有的背景策略。
  ///
  /// 指定 [lease] 时仅释放匹配的注册；省略租约时强制释放当前注册。
  void release(String owner, {int? lease}) {
    if (!ref.mounted) {
      return;
    }
    final current = _policies[owner];
    if (current == null || (lease != null && current.sequence != lease)) {
      return;
    }
    _policies.remove(owner);
    if (_policies.isEmpty) {
      _scheduleEmptyGrace();
      return;
    }
    _resolve();
  }

  /// 清空策略时延迟到当前同步/微任务批之后再落到 hidden，给同帧新路由的
  /// request 留出注册窗口，避免导航切换出现「壁纸隐藏再显示」的整段闪烁。
  void _scheduleEmptyGrace() {
    final token = ++_emptyGraceToken;
    scheduleMicrotask(() {
      if (!ref.mounted || token != _emptyGraceToken || _policies.isNotEmpty) {
        return;
      }
      _updateState(const AppBackdropSceneState());
    });
  }

  void _resolve() {
    if (_policies.isEmpty) {
      _updateState(const AppBackdropSceneState());
      return;
    }
    final entries = _policies.entries.toList(growable: false)..sort(
      (left, right) => right.value.sequence.compareTo(left.value.sequence),
    );
    final active = entries.first;
    _updateState(
      AppBackdropSceneState(owner: active.key, policy: active.value.policy),
    );
  }

  /// 仅在所有者或策略实际变化时发布状态，重复注册同策略不触发宿主重建。
  void _updateState(AppBackdropSceneState next) {
    final current = state;
    if (current.owner == next.owner && current.policy == next.policy) {
      return;
    }
    state = next;
  }
}

class _OwnedBackdropPolicy {
  const _OwnedBackdropPolicy({required this.policy, required this.sequence});

  final AppBackdropPolicy policy;
  final int sequence;
}
