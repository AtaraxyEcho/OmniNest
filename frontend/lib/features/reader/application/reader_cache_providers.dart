import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/security/encrypted_file_vault.dart';
import 'package:omninest/core/security/offline_key_store.dart';
import 'package:omninest/features/reader/data/local_book_cache.dart';

/// 当前认证会话使用的离线密钥存储。
final offlineKeyStoreProvider = Provider<OfflineKeyStore>((ref) {
  return createOfflineKeyStore();
});

/// 当前认证会话使用的加密文件保险库。
final encryptedFileVaultProvider = Provider<EncryptedFileVault>((ref) {
  return EncryptedFileVault(keyStore: ref.watch(offlineKeyStoreProvider));
});

/// 当前认证用户隔离的本地书籍文件缓存。
final localBookCacheProvider = Provider<LocalBookCache>((ref) {
  final userId = ref.watch(
    authSessionProvider.select((session) => session.value?.user?.id),
  );
  return LocalBookCache(
    userId: userId,
    vault: ref.watch(encryptedFileVaultProvider),
  );
});
