import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_store.dart';

final serverConfigStoreProvider = Provider<ServerConfigStore>((ref) {
  return createServerConfigStore();
});

/// 用户自定义的服务器配置；null 表示未自定义（回落构建期预置或进入引导页）。
final serverConfigProvider =
    AsyncNotifierProvider<ServerConfigController, ServerConfig?>(
      ServerConfigController.new,
    );

/// 服务器配置状态控制器。
///
/// 预置地址不落库（D2 决策）：apply 只写用户自定义值，clear 清除后
/// 自动回落构建期预置，定制包升级换址可随包传播。
class ServerConfigController extends AsyncNotifier<ServerConfig?> {
  @override
  Future<ServerConfig?> build() {
    return ref.watch(serverConfigStoreProvider).read();
  }

  /// 保存新的服务器配置；调用方需先完成探活确认地址可达。
  Future<void> apply(ServerConfig config) async {
    await ref.read(serverConfigStoreProvider).write(config);
    state = AsyncData(config);
  }

  /// 清除自定义配置并回落构建期预置。
  Future<void> clear() async {
    await ref.read(serverConfigStoreProvider).clear();
    state = const AsyncData(null);
  }
}
