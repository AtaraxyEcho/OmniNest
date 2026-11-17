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
  String? _activePath;

  @override
  AppBackdropSceneState build() => const AppBackdropSceneState();

  /// 注册或更新前景模块的背景策略。
  ///
  /// [owner] 是前景模块的稳定标识，[policy] 是模块请求的背景策略。
  /// [pathPrefix] 是注册者所属的路由分支前缀（如 `/video`）：声明后，
  /// 当宿主路由不在该前缀下时此注册不参与生效——StatefulShellRoute 下
  /// 分支页面常驻挂载（IndexedStack 不销毁），其隐藏策略会在返回门户等
  /// 场景持续压制可见分支的注册。省略时始终参与。
  /// 返回值是本次注册的租约，释放时可用于避免删除同名的新注册。
  /// 每次注册都签发新租约：整树重挂后新作用域持新租约，旧作用域的
  /// 释放按旧租约号匹配失败，不会误删新注册。
  int request(String owner, AppBackdropPolicy policy, {String? pathPrefix}) {
    if (!ref.mounted) {
      return 0;
    }
    _sequence++;
    _emptyGraceToken++;
    _policies[owner] = _OwnedBackdropPolicy(
      policy: policy,
      sequence: _sequence,
      pathPrefix: pathPrefix,
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

  /// 更新宿主路由路径并重选生效场景。
  void setActivePath(String path) {
    if (_activePath == path) {
      return;
    }
    _activePath = path;
    _resolve();
  }

  /// Defer empty policy to hidden until after the current microtask batch so
  /// a same-frame route request can register without a hide/show flash.
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
    // 优先取「路径可见」的最高 sequence 注册；宿主路径未知或无可匹配时
    // 回退到最高 sequence 注册（保持既有行为）。
    final active =
        _visibleEntryFor(entries) ??
        entries.firstWhere(
          (entry) => entry.value.pathPrefix == null,
          orElse: () => entries.first,
        );
    _updateState(
      AppBackdropSceneState(owner: active.key, policy: active.value.policy),
    );
  }

  MapEntry<String, _OwnedBackdropPolicy>? _visibleEntryFor(
    List<MapEntry<String, _OwnedBackdropPolicy>> entries,
  ) {
    final activePath = _activePath;
    if (activePath == null) {
      return null;
    }
    for (final entry in entries) {
      final prefix = entry.value.pathPrefix;
      if (prefix == null || activePath.startsWith(prefix)) {
        return entry;
      }
    }
    return null;
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
  const _OwnedBackdropPolicy({
    required this.policy,
    required this.sequence,
    this.pathPrefix,
  });

  final AppBackdropPolicy policy;
  final int sequence;
  final String? pathPrefix;
}
