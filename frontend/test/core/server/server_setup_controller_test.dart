import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/server/server_config_store_base.dart';
import 'package:omninest/core/server/server_probe_client.dart';
import 'package:omninest/core/server/server_setup_controller.dart';

class _FakeProbeClient extends ServerProbeClient {
  _FakeProbeClient({this.result, this.pending});

  final ServerProbeResult? result;
  final Completer<ServerProbeResult>? pending;

  int callCount = 0;

  @override
  Future<ServerProbeResult> probe(
    ServerConfig config, {
    CancelToken? cancelToken,
  }) async {
    callCount++;
    if (pending != null) {
      return pending!.future;
    }
    return result ?? const ServerProbeResult.success(requiredSetup: false);
  }
}

void main() {
  late MemoryServerConfigStore store;
  late ProviderContainer container;

  ProviderContainer build({
    _FakeProbeClient? probe,
    bool requireHttps = false,
  }) {
    return ProviderContainer(
      overrides: [
        serverConfigStoreProvider.overrideWithValue(store),
        serverProbeClientProvider.overrideWithValue(
          probe ?? _FakeProbeClient(),
        ),
        serverRequireHttpsProvider.overrideWithValue(requireHttps),
      ],
    );
  }

  setUp(() {
    store = MemoryServerConfigStore();
    container = build();
  });

  tearDown(() {
    container.dispose();
  });

  test('输入变化刷新归一化预览并清空错误', () async {
    final notifier = container.read(serverSetupControllerProvider.notifier);
    await notifier.connect('not a url at all');
    notifier.updatePreview('192.168.1.10:8080');

    final state = container.read(serverSetupControllerProvider);
    expect(state.error, isNull);
    expect(state.preview?.apiBaseUrl, 'http://192.168.1.10:8080/api/v1');
    expect(state.showsHttpWarning, isTrue);
  });

  test('https 预览不展示明文警告', () {
    container
        .read(serverSetupControllerProvider.notifier)
        .updatePreview('https://nest.example.com');

    final state = container.read(serverSetupControllerProvider);
    expect(state.showsHttpWarning, isFalse);
  });

  test('非法地址直接报错且不发起探活', () async {
    final probe = _FakeProbeClient();
    final probeContainer = build(probe: probe);

    final ok = await probeContainer
        .read(serverSetupControllerProvider.notifier)
        .connect('###');

    expect(ok, isFalse);
    expect(
      probeContainer.read(serverSetupControllerProvider).error,
      ServerSetupError.invalidAddress,
    );
    expect(probe.callCount, 0);
    probeContainer.dispose();
  });

  test('严格构建下显式 http 地址给出专用错误', () async {
    final strictContainer = build(requireHttps: true);

    final ok = await strictContainer
        .read(serverSetupControllerProvider.notifier)
        .connect('http://192.168.1.10:8080');

    expect(ok, isFalse);
    expect(
      strictContainer.read(serverSetupControllerProvider).error,
      ServerSetupError.httpsOnly,
    );
    strictContainer.dispose();
  });

  test('探活成功后写入配置', () async {
    final ok = await container
        .read(serverSetupControllerProvider.notifier)
        .connect('https://nest.example.com');

    expect(ok, isTrue);
    expect((await store.read())?.apiBaseUrl, 'https://nest.example.com/api/v1');
    expect(container.read(serverSetupControllerProvider).error, isNull);
  });

  test('探活失败映射错误且不写入配置', () async {
    final probeContainer = build(
      probe: _FakeProbeClient(
        result: const ServerProbeResult.failure(ServerProbeFailure.unreachable),
      ),
    );

    final ok = await probeContainer
        .read(serverSetupControllerProvider.notifier)
        .connect('https://nest.example.com');

    expect(ok, isFalse);
    expect(
      probeContainer.read(serverSetupControllerProvider).error,
      ServerSetupError.unreachable,
    );
    expect(await store.read(), isNull);
    probeContainer.dispose();
  });

  test('探活期间重复提交被忽略', () async {
    final pending = Completer<ServerProbeResult>();
    final probe = _FakeProbeClient(pending: pending);
    final probeContainer = build(probe: probe);

    final notifier = probeContainer.read(
      serverSetupControllerProvider.notifier,
    );
    final first = notifier.connect('https://nest.example.com');
    final second = await notifier.connect('https://nest.example.com');

    expect(second, isFalse);
    expect(probe.callCount, 1);
    pending.complete(const ServerProbeResult.success(requiredSetup: false));
    expect(await first, isTrue);
    probeContainer.dispose();
  });

  test('探活取消不回写状态', () async {
    final pending = Completer<ServerProbeResult>();
    final probeContainer = build(probe: _FakeProbeClient(pending: pending));

    final notifier = probeContainer.read(
      serverSetupControllerProvider.notifier,
    );
    final connecting = notifier.connect('https://nest.example.com');
    probeContainer.dispose();
    pending.completeError(
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      ),
    );

    expect(await connecting, isFalse);
  });
}
