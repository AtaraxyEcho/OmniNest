import 'dart:convert';
import 'dart:typed_data';

import 'package:omninest/core/security/offline_crypto.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:web/web.dart' as web;

/// 创建 Web 会话级离线主密钥存储。
OfflineKeyStore createOfflineKeyStore() {
  return WebSessionOfflineKeyStore();
}

/// Web 端把离线主密钥放在标签页级 sessionStorage。
///
/// 同一标签页刷新后仍能解开已落库的密文；关闭标签页即随会话丢弃，
/// 公共电脑上残留的 SQLite 数据不再可读。密钥按用户隔离，换号不串用。
class WebSessionOfflineKeyStore implements OfflineKeyStore {
  WebSessionOfflineKeyStore({OfflineCrypto crypto = const OfflineCrypto()})
    : _crypto = crypto;

  static const _keyId = 'session-v1';
  static const _storagePrefix = 'omninest.offline.master.v1.';

  final OfflineCrypto _crypto;

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    final storageKey = _storageKey(userId);
    final encoded = web.window.sessionStorage.getItem(storageKey);
    if (encoded != null && encoded.isNotEmpty) {
      final bytes = _decodeKey(encoded);
      if (bytes != null) {
        return OfflineMasterKey(keyId: _keyId, bytes: bytes);
      }
    }
    final bytes = _crypto.generateKey();
    web.window.sessionStorage.setItem(storageKey, base64Encode(bytes));
    return OfflineMasterKey(keyId: _keyId, bytes: bytes);
  }

  @override
  Future<void> delete(String userId) async {
    web.window.sessionStorage.removeItem(_storageKey(userId));
  }

  Uint8List? _decodeKey(String encoded) {
    try {
      final bytes = base64Decode(encoded);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } on FormatException {
      return null;
    }
  }

  String _storageKey(String userId) {
    final userKey = base64UrlEncode(utf8.encode(userId)).replaceAll('=', '');
    return '$_storagePrefix$userKey';
  }
}

/// 不支持安全存储时的内存密钥存储，保留给纯 Stub 平台复用。
class MemoryOfflineKeyStore implements OfflineKeyStore {
  MemoryOfflineKeyStore({OfflineCrypto crypto = const OfflineCrypto()})
    : _crypto = crypto;

  final OfflineCrypto _crypto;
  final Map<String, OfflineMasterKey> _keys = <String, OfflineMasterKey>{};

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    return _keys.putIfAbsent(
      userId,
      () => OfflineMasterKey(keyId: 'session-v1', bytes: _crypto.generateKey()),
    );
  }

  @override
  Future<void> delete(String userId) async {
    _keys.remove(userId);
  }
}
