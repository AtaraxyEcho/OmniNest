import 'dart:typed_data';

import 'package:omninest/core/security/offline_memory_cache.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';

/// 创建 Web 会话内阅读图片缓存仓库。
ReaderImageRepository createReaderImageRepository({
  required LocalDatabase database,
  required String userId,
}) {
  return WebReaderImageRepository(userId: userId);
}

/// Web 端仅在当前登录会话内保存阅读图片。
class WebReaderImageRepository implements ReaderImageRepository {
  const WebReaderImageRepository({required String userId}) : _userId = userId;

  static const _cacheType = 'reader-image';

  final String _userId;

  @override
  Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {
    OfflineMemoryCache.write(
      userId: _userId,
      cacheType: _cacheType,
      businessId: _businessId(itemId, imagePath),
      bytes: Uint8List.fromList(bytes),
    );
  }

  @override
  Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  }) async {
    final bytes = OfflineMemoryCache.read(
      userId: _userId,
      cacheType: _cacheType,
      businessId: _businessId(itemId, imagePath),
    );
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteForItem(String itemId) async {
    OfflineMemoryCache.removeByBusinessPrefix(
      userId: _userId,
      cacheType: _cacheType,
      businessPrefix: '$itemId\u0000',
    );
  }

  @override
  Future<void> cleanOld({int maxAgeDays = 30}) async {}

  @override
  Future<void> clearAll() async {
    OfflineMemoryCache.clearType(userId: _userId, cacheType: _cacheType);
  }

  String _businessId(String itemId, String imagePath) {
    return '$itemId\u0000$imagePath';
  }
}
