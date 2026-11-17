import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_store_base.dart';

ServerConfigStore createServerConfigStore() {
  return SecureServerConfigStore();
}

/// 桌面与移动端的安全存储实现，与刷新令牌同一存储介质。
class SecureServerConfigStore implements ServerConfigStore {
  SecureServerConfigStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _storageKey = 'omninest.serverConfig';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<ServerConfig?> read() async {
    final raw = await _secureStorage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return ServerConfig.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(ServerConfig config) {
    return _secureStorage.write(
      key: _storageKey,
      value: jsonEncode(config.toJson()),
    );
  }

  @override
  Future<void> clear() {
    return _secureStorage.delete(key: _storageKey);
  }
}
