/// Web 平台无稳定文件系统，不提供背景视频本地缓存。
class AppBackdropLocalVideoCache {
  String? cachedPathFor(String assetId) => null;

  Future<String?> ensureCached({
    required String assetId,
    required String remoteUrl,
  }) async => null;

  Future<void> evict(String assetId) async {}

  void dispose() {}
}
