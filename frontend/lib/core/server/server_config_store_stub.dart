import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_store_base.dart';

ServerConfigStore createServerConfigStore() {
  return const NoopServerConfigStore();
}

/// 非 io 且非 html 平台的空实现：无持久化能力，按未配置处理。
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
