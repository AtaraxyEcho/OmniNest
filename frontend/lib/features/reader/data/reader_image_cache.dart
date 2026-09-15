import 'dart:typed_data';

import 'package:omninest/features/reader/data/reader_image_repository_base.dart';

/// 阅读图片缓存的兼容调用门面。
///
/// 实际存储由当前登录用户对应的 [ReaderImageRepository] 负责。
class ReaderImageCache {
  static ReaderImageRepository _repository =
      const DisabledReaderImageRepository();

  /// 切换当前登录用户对应的缓存仓库。
  static void init(ReaderImageRepository repository) {
    _repository = repository;
  }

  /// 保存单张阅读图片。
  static Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) {
    return _repository.saveImage(
      itemId: itemId,
      imagePath: imagePath,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  /// 读取单张阅读图片。
  static Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  }) {
    return _repository.loadImage(itemId: itemId, imagePath: imagePath);
  }

  /// 删除指定阅读条目的全部图片。
  static Future<void> deleteForItem(String itemId) {
    return _repository.deleteForItem(itemId);
  }
}
