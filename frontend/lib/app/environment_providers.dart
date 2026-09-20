import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/server/server_config_controller.dart';

/// 构建期预置环境（--dart-define 或 Web 同源推导）。
/// 独立成 Provider 以便测试注入预置值（D2 回落链测试依赖）。
final presetAppEnvironmentProvider = Provider<AppEnvironment?>((ref) {
  return AppEnvironment.fromDefinesOrNull();
});

/// 生效运行环境：用户自定义服务器配置优先，其次构建期预置。
/// null 表示服务器未配置，由路由层引导进入首启配置页；
/// 未配置期间任何需要环境的 Provider 构造都会 fail-fast。
final appEnvironmentProvider = Provider<AppEnvironment?>((ref) {
  final custom = ref.watch(serverConfigProvider).asData?.value;
  if (custom != null) {
    return custom.toAppEnvironment();
  }
  return ref.watch(presetAppEnvironmentProvider);
});

/// 分享链接基址；仅在服务器已配置（登录后分享流程）时读取。
final webShareBaseUrlProvider = Provider<String>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment == null) {
    throw StateError('服务器地址未配置');
  }
  return environment.effectiveWebBaseUrl;
});
