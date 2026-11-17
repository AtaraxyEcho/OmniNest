import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/server/server_config_store_base.dart';

void main() {
  late MemoryServerConfigStore store;
  late ProviderContainer container;

  setUp(() {
    store = MemoryServerConfigStore();
    container = ProviderContainer(
      overrides: [serverConfigStoreProvider.overrideWithValue(store)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('build 从存储读取自定义配置', () async {
    final config = ServerConfig.tryParse('https://nest.example.com')!;
    await store.write(config);

    final loaded = await container.read(serverConfigProvider.future);
    expect(loaded?.apiBaseUrl, config.apiBaseUrl);
  });

  test('apply 写入存储并更新状态', () async {
    final config = ServerConfig.tryParse('https://nest.example.com')!;
    await container.read(serverConfigProvider.notifier).apply(config);

    expect(container.read(serverConfigProvider).asData?.value, config);
    expect((await store.read())?.apiBaseUrl, config.apiBaseUrl);
  });

  test('clear 清空存储并回落未自定义', () async {
    final config = ServerConfig.tryParse('https://nest.example.com')!;
    await container.read(serverConfigProvider.notifier).apply(config);

    await container.read(serverConfigProvider.notifier).clear();

    expect(container.read(serverConfigProvider).asData?.value, isNull);
    expect(await store.read(), isNull);
  });
}
