import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/security/offline_column_cipher.dart';
import 'package:omninest/core/storage/local_database.dart';

/// 全应用共享的本地数据库实例。
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

/// 离线敏感列加密器（原生平台用系统安全存储主密钥，Web 用标签页会话主密钥）。
///
/// 与用户数据清理流程共用同一个进程级实例，清理时才能一并失效派生密钥缓存。
final offlineColumnCipherProvider = Provider<OfflineTextCipher?>((ref) {
  return sharedOfflineColumnCipher();
});
