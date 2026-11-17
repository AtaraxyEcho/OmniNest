import 'package:omninest/core/server/server_config.dart';

/// 服务器配置持久化接口。
abstract class ServerConfigStore {
  Future<ServerConfig?> read();

  Future<void> write(ServerConfig config);

  Future<void> clear();
}

/// 内存实现，供测试与本地覆盖使用。
class MemoryServerConfigStore implements ServerConfigStore {
  ServerConfig? _config;

  @override
  Future<ServerConfig?> read() async {
    return _config;
  }

  @override
  Future<void> write(ServerConfig config) async {
    _config = config;
  }

  @override
  Future<void> clear() async {
    _config = null;
  }
}
