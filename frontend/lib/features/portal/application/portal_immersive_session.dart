import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 门户音乐沉浸会话状态：仅本机、不持久化、不经 realtime 同步。
///
/// 门户内容区域与顶栏两个沉浸入口共用此唯一事实源。此前内容区域入口
/// 只改组件私有字段，顶栏按钮以远程持久偏好为取反基准，对内容区域
/// 入口完全不可见——既导致"进入后顶部栏退出无效"，也会把偏好翻转经
/// realtime 广播到同账号其他端（Windows 端据此无边框全屏）。
final portalImmersiveSessionProvider =
    NotifierProvider<PortalImmersiveSessionController, bool>(
      PortalImmersiveSessionController.new,
    );

class PortalImmersiveSessionController extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  /// 进入门户音乐沉浸会话。
  void activate() {
    if (ref.mounted) {
      state = true;
    }
  }

  /// 退出门户音乐沉浸会话。
  void deactivate() {
    if (ref.mounted) {
      state = false;
    }
  }
}
