import 'package:omninest/core/security/offline_column_cipher.dart';
import 'package:omninest/core/security/offline_memory_cache.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/security/offline_data_lifecycle_base.dart';
import 'package:omninest/core/security/offline_data_lifecycle_stub.dart'
    if (dart.library.io) 'package:omninest/core/security/offline_data_lifecycle_io.dart'
    if (dart.library.js_interop) 'package:omninest/core/security/offline_data_lifecycle_web.dart'
    as platform_lifecycle;

export 'package:omninest/core/security/offline_data_lifecycle_base.dart';

/// 初始化当前平台的离线敏感数据生命周期。
Future<void> initializeOfflineDataLifecycle() {
  return platform_lifecycle.initializeOfflineDataLifecycle();
}

/// 创建当前平台的离线敏感数据生命周期实现。
OfflineDataLifecycle createOfflineDataLifecycle({
  required LocalDatabase database,
  OfflineTextCipher? textCipher,
}) {
  return DatabaseOfflineDataLifecycle(
    delegate: platform_lifecycle.createOfflineDataLifecycle(),
    database: database,
    textCipher: textCipher ?? sharedOfflineColumnCipher(),
  );
}

/// 统一清理平台文件、内存缓存和本地数据库中的用户数据。
class DatabaseOfflineDataLifecycle implements OfflineDataLifecycle {
  /// 创建数据库感知的离线数据生命周期。
  const DatabaseOfflineDataLifecycle({
    required OfflineDataLifecycle delegate,
    required LocalDatabase database,
    OfflineTextCipher? textCipher,
  }) : _delegate = delegate,
       _database = database,
       _textCipher = textCipher;

  final OfflineDataLifecycle _delegate;
  final LocalDatabase _database;

  /// 派生列密钥缓存所属的加密器；平台无安全存储或未注入时为空，无需失效。
  final OfflineTextCipher? _textCipher;

  @override
  Future<void> clearUser(String userId) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> runStep(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await runStep(() => _delegate.clearUser(userId));
    OfflineMemoryCache.clearUser(userId);
    // 主密钥已随平台清理删除，派生列密钥缓存必须同步失效：否则同一进程里
    // 重新登录后会拿旧密钥加密，新会话再也解不开这些密文。
    _textCipher?.evictUser(userId);
    await runStep(() => _database.clearUserData(userId));

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }
}
