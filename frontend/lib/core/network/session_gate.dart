import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 客户端侧的会话结束信号。
///
/// 登出流程在切换到未认证状态之前置位，随后的 provider 级联重建会立即发出
/// 一批不带令牌的请求；[ApiClient] 读到已结束就直接本地拒绝，不再让这批
/// 注定 401 的请求打到服务端。
///
/// 与 ApiClient 实例分开持有：登出会触发 provider 重建，若标记随实例存亡，
/// 新建的客户端又会把请求放出去。
class SessionGate {
  bool _ended = false;

  bool get ended => _ended;

  void markEnded() {
    _ended = true;
  }

  void markActive() {
    _ended = false;
  }
}

final sessionGateProvider = Provider<SessionGate>((ref) => SessionGate());
