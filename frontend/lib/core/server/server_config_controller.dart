import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_store.dart';
import 'package:omninest/core/utils/bounded_async_step.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// 安全存储读取预算：平台通道悬挂时按「未自定义配置」回落构建期预置，
/// 不能让服务器门控永远停在 AsyncLoading。读取抛错同样按未配置处理，
/// 一次存储故障不应让整个应用卡在启动页。
const Duration _configReadBudget = Duration(seconds: 3);

/// 非敏感服务器地址镜像键：供冷启动从 SharedPreferences 瞬读，避开
/// Windows Credential Manager / Keychain 首次异步读取延迟；写/清路径与主存储保持一致。
const String _serverConfigMirrorPrefsKey = 'omninest.server_config.mirror.v1';

class ServerConfigController extends AsyncNotifier<ServerConfig?> {
  @override
  Future<ServerConfig?> build() async {
    final store = ref.watch(serverConfigStoreProvider);
    final mirrored = await _readMirror();
    if (mirrored != null) {
      return mirrored;
    }
    try {
      final stored = await boundedAsyncStep(
        ref,
        store.read(),
        _configReadBudget,
      );
      if (stored != null) {
        unawaited(_writeMirror(stored));
      }
      return stored;
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('服务器配置读取失败，回落预置: ${error.runtimeType}');
      }
      return null;
    }
  }

  /// 保存新的服务器配置；调用方需先完成探活确认地址可达。
  Future<void> apply(ServerConfig config) async {
    await _clearSessionBeforeSwitchingServer();
    await ref.read(serverConfigStoreProvider).write(config);
    unawaited(_writeMirror(config));
    state = AsyncData(config);
  }

  /// 清除自定义配置并回落构建期预置。
  Future<void> clear() async {
    await _clearSessionBeforeSwitchingServer();
    await ref.read(serverConfigStoreProvider).clear();
    unawaited(_clearMirror());
    state = const AsyncData(null);
  }

  /// 换服前必须先把当前会话注销到旧服务器：直接改写 baseUrl 会把旧服务器的
  /// JWT 与 Refresh Token 发给新服务器，既登不进去也会泄露凭据。
  Future<void> _clearSessionBeforeSwitchingServer() async {
    await ref.read(authSessionProvider.notifier).clearSession();
  }

  Future<ServerConfig?> _readMirror() async {
    // 镜像只为桌面端（Windows Credential Manager/Keychain 冷读）提速；
    // 移动/Web 与测试环境直接走主存储，避免测试内 SharedPreferences 平台通道挂起。
    if (!isDesktopPlatform) {
      return null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_serverConfigMirrorPrefsKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return ServerConfig.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> _writeMirror(ServerConfig config) async {
    if (!isDesktopPlatform) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _serverConfigMirrorPrefsKey,
        jsonEncode(config.toJson()),
      );
    } on Object {
      // 镜像写入失败不影响主存储与当前运行态。
    }
  }

  Future<void> _clearMirror() async {
    if (!isDesktopPlatform) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_serverConfigMirrorPrefsKey);
    } on Object {
      // 镜像清理失败不影响主存储与当前运行态。
    }
  }
}
