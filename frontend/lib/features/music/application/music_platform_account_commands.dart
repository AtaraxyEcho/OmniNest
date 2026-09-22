part of 'music_controller.dart';

/// 管理外部音乐平台账号状态和登录命令。
extension MusicPlatformAccountCommands on MusicCenterController {
  Future<Map<String, PlatformUserInfo?>> _safePlatformInfo() async {
    final neteaseInfo = await _safe(() => _api.platformInfo('netease'), null);
    return {'netease': neteaseInfo};
  }

  /// 加载网易云的登录状态。
  Future<void> loadPlatformInfo() async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final platformInfo = await _safePlatformInfo();
    final latest = _currentState;
    if (latest == null) {
      return;
    }
    _replaceState(latest.copyWith(neteaseUserInfo: platformInfo['netease']));
  }

  /// 创建网易云 QR 登录会话。
  Future<QrLoginSession> neteaseQrLogin() => _api.createNeteaseQrLogin();

  /// 轮询网易云 QR 登录状态。
  Future<QrLoginStatus> checkNeteaseQrLogin(String key) =>
      _api.checkNeteaseQrLogin(key);

  /// 断开指定外部平台账号，并清理该平台派生的本地状态。
  ///
  /// 清理是"确定断开"语义，因此曲库与每日推荐走 `invalidate`（允许回落空态），
  /// 而不是 `refresh()`——后者失败时会保留上一次成功数据，退出后仍显示旧歌单。
  /// 队列侧剔除该平台在线曲目并回写，保证重启后不与远端旧队列合并复活。
  ///
  /// 失败时向上抛出，由调用方呈现错误：此前该流程的 Future 无接收方，
  /// 服务端异常会让方法在 `await` 处中断，界面既不清理也不提示。
  ///
  /// @return 从播放队列中剔除的该平台曲目数。
  Future<int> platformLogout(String platform) async {
    await _api.platformLogout(platform);
    if (platform == 'netease') {
      final current = _currentState;
      if (current != null) {
        _replaceState(current.copyWith(clearNeteaseUserInfo: true));
      }
    }
    final removedItems = purgePlatformQueueItems(platform);
    await refreshAfterPlatformChange();
    return removedItems;
  }
}
