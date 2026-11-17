import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 壁纸的作用范围（样例 `Settings.tsx` 的 "Apply to"）。
///
/// 这是**设备级**偏好：样例把它存在浏览器本地，不同设备本来就可以不同
/// （同一页还有 "Choose per device"）。因此不进服务端 `AppBackdropSettings`，
/// 避免把「这台机器想让壁纸铺到哪」同步给别的设备。
enum DesktopBackdropScope {
  /// 全站：所有工作区页面都铺壁纸。
  everywhere,

  /// 首页与音乐：其余页面保持纯环境光，读长文/看片时更干净。
  homeMusic,
}

const _scopeKey = 'desktop.backdrop.scope';

final desktopBackdropScopeProvider =
    NotifierProvider<DesktopBackdropScopeController, DesktopBackdropScope>(
      DesktopBackdropScopeController.new,
    );

class DesktopBackdropScopeController extends Notifier<DesktopBackdropScope> {
  @override
  DesktopBackdropScope build() {
    unawaited(_restore());
    return DesktopBackdropScope.homeMusic;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_scopeKey) == DesktopBackdropScope.everywhere.name) {
        state = DesktopBackdropScope.everywhere;
      }
    } on Object {
      // 偏好后端不可用（比如测试环境还没注册插件）时保持默认值，
      // 壁纸范围不是关键路径，不值得把整个设置页拖崩。
    }
  }

  Future<void> select(DesktopBackdropScope scope) async {
    if (state == scope) {
      return;
    }
    state = scope;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_scopeKey, scope.name);
    } on Object {
      // 同上：写失败只影响下次启动的默认值。
    }
  }
}
