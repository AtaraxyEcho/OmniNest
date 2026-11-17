import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/server/server_probe_client.dart';

/// 构建期 HTTPS-only 开关的运行期读取点；独立成 Provider 以便测试注入。
final serverRequireHttpsProvider = Provider<bool>((ref) {
  return ServerConfig.requireHttpsByBuild;
});

enum ServerSetupPhase { idle, probing }

/// 引导页错误；由页面映射为 ARB 文案。
enum ServerSetupError {
  invalidAddress,
  httpsOnly,
  unreachable,
  timeout,
  notOmniNest,
  rejected,
}

class ServerSetupState {
  const ServerSetupState({
    this.phase = ServerSetupPhase.idle,
    this.error,
    this.preview,
  });

  final ServerSetupPhase phase;
  final ServerSetupError? error;
  final ServerConfig? preview;

  bool get isProbing => phase == ServerSetupPhase.probing;

  /// 明文 HTTP 提示：归一化预览为 http 时展示（非阻塞）。
  bool get showsHttpWarning =>
      preview != null && preview!.apiBaseUrl.startsWith('http://');
}

/// 首启服务器引导控制器：解析输入 → 探活 → 应用配置。
/// 页面只发起动作与展示状态，探活的取消随 Provider 生命周期释放。
final serverSetupControllerProvider =
    NotifierProvider<ServerSetupController, ServerSetupState>(
      ServerSetupController.new,
    );

class ServerSetupController extends Notifier<ServerSetupState> {
  CancelToken? _cancelToken;

  @override
  ServerSetupState build() {
    ref.onDispose(() => _cancelToken?.cancel());
    return const ServerSetupState();
  }

  /// 输入变化时刷新归一化预览并清除既有错误。
  void updatePreview(String raw, {String? wsBaseUrl, String? webBaseUrl}) {
    final preview = ServerConfig.tryParse(
      raw,
      wsBaseUrl: wsBaseUrl,
      webBaseUrl: webBaseUrl,
      requireHttps: ref.read(serverRequireHttpsProvider),
    );
    state = ServerSetupState(phase: state.phase, error: null, preview: preview);
  }

  /// 连接：解析 → 探活 → 应用配置。成功返回 true（随后路由门控自动离开引导页）。
  Future<bool> connect(
    String raw, {
    String? wsBaseUrl,
    String? webBaseUrl,
  }) async {
    if (state.isProbing) {
      return false;
    }
    final trimmed = raw.trim();
    final requireHttps = ref.read(serverRequireHttpsProvider);
    final config = ServerConfig.tryParse(
      trimmed,
      wsBaseUrl: wsBaseUrl,
      webBaseUrl: webBaseUrl,
      requireHttps: requireHttps,
    );
    if (config == null) {
      final explicitHttp = trimmed.startsWith('http://');
      state = ServerSetupState(
        error:
            requireHttps && explicitHttp
                ? ServerSetupError.httpsOnly
                : ServerSetupError.invalidAddress,
      );
      return false;
    }
    state = ServerSetupState(phase: ServerSetupPhase.probing, preview: config);
    _cancelToken = CancelToken();
    final ServerProbeResult result;
    try {
      result = await ref
          .read(serverProbeClientProvider)
          .probe(config, cancelToken: _cancelToken);
    } on DioException {
      // 页面退出触发取消：Provider 即将销毁，不回写状态。
      return false;
    }
    if (!ref.mounted) {
      return false;
    }
    if (result.isSuccess) {
      await ref.read(serverConfigProvider.notifier).apply(config);
      if (ref.mounted) {
        state = ServerSetupState(preview: config);
      }
      return true;
    }
    state = ServerSetupState(
      preview: config,
      error: _mapFailure(result.failure),
    );
    return false;
  }

  ServerSetupError _mapFailure(ServerProbeFailure? failure) {
    switch (failure) {
      case ServerProbeFailure.unreachable:
        return ServerSetupError.unreachable;
      case ServerProbeFailure.timeout:
        return ServerSetupError.timeout;
      case ServerProbeFailure.notOmniNest:
        return ServerSetupError.notOmniNest;
      case ServerProbeFailure.rejected:
      case null:
        return ServerSetupError.rejected;
    }
  }
}
