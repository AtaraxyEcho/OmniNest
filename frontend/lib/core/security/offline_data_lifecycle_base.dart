/// 离线敏感数据生命周期接口。
abstract interface class OfflineDataLifecycle {
  /// 删除指定用户的自动缓存和密钥材料。
  Future<void> clearUser(String userId);
}
