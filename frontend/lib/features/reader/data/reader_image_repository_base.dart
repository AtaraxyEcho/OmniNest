import 'dart:typed_data';

/// 阅读图片缓存仓库。
abstract interface class ReaderImageRepository {
  /// 保存一张阅读图片。
  Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  });

  /// 读取一张阅读图片。
  Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  });

  /// 删除指定阅读条目的全部图片。
  Future<void> deleteForItem(String itemId);

  /// 清理超过指定天数未访问的图片。
  Future<void> cleanOld({int maxAgeDays = 30});

  /// 清除当前用户的全部图片缓存。
  Future<void> clearAll();
}

/// 未登录状态使用的空阅读图片仓库。
class DisabledReaderImageRepository implements ReaderImageRepository {
  const DisabledReaderImageRepository();

  @override
  Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {}

  @override
  Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  }) async => null;

  @override
  Future<void> deleteForItem(String itemId) async {}

  @override
  Future<void> cleanOld({int maxAgeDays = 30}) async {}

  @override
  Future<void> clearAll() async {}
}
