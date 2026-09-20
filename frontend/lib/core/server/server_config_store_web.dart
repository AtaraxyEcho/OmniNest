import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_store_base.dart';

ServerConfigStore createServerConfigStore() {
  return const NoopServerConfigStore();
}

/// Web 端不持久化服务器配置：浏览器同源推导恒可用，无需用户配置。
class NoopServerConfigStore implements ServerConfigStore {
  const NoopServerConfigStore();

  @override
  Future<ServerConfig?> read() async {
    return null;
  }

  @override
  Future<void> write(ServerConfig config) async {}

  @override
  Future<void> clear() async {}
}
