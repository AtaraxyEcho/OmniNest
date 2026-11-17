import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:omninest/core/security/offline_data_lifecycle_base.dart';
import 'package:omninest/core/security/offline_key_store.dart';

/// 初始化原生平台离线数据目录并删除旧版明文阅读缓存。
Future<void> initializeOfflineDataLifecycle({
  Future<Directory> Function()? documentsDirectoryResolver,
  Future<Directory> Function()? temporaryDirectoryResolver,
}) async {
  final documents =
      await (documentsDirectoryResolver ?? getApplicationDocumentsDirectory)();
  final temporary =
      await (temporaryDirectoryResolver ?? getTemporaryDirectory)();
  final legacyDirectories = <Directory>[
    Directory(p.join(documents.path, 'reader_cache')),
    Directory(p.join(temporary.path, 'reader_cache')),
  ];
  for (final directory in legacyDirectories) {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

/// 创建原生平台离线敏感数据生命周期实现。
OfflineDataLifecycle createOfflineDataLifecycle() {
  return IoOfflineDataLifecycle(keyStore: createOfflineKeyStore());
}

/// 清理原生平台离线缓存与主密钥。
class IoOfflineDataLifecycle implements OfflineDataLifecycle {
  IoOfflineDataLifecycle({required OfflineKeyStore keyStore})
    : _keyStore = keyStore;

  final OfflineKeyStore _keyStore;

  @override
  Future<void> clearUser(String userId) async {
    try {
      final temporary = await getTemporaryDirectory();
      final documents = await getApplicationDocumentsDirectory();
      final encodedUserId = base64UrlEncode(
        utf8.encode(userId),
      ).replaceAll('=', '');
      final directoryPaths = <String>[
        p.join(temporary.path, 'reader_cache_v2', encodedUserId),
        p.join(temporary.path, 'reader_image_cache_v2', encodedUserId),
        p.join(temporary.path, 'reader_cache'),
        p.join(documents.path, 'reader_cache'),
      ];
      // 目录递归删除移出 UI isolate，避免大量文件删除阻塞界面。
      await Isolate.run(() {
        for (final path in directoryPaths) {
          final directory = Directory(path);
          if (directory.existsSync()) {
            directory.deleteSync(recursive: true);
          }
        }
      });
    } finally {
      await _keyStore.delete(userId);
    }
  }
}
