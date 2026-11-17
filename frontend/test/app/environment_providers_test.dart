import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/server/server_config_store_base.dart';

void main() {
  late MemoryServerConfigStore store;
  late AppEnvironment preset;
  late ProviderContainer container;

  setUp(() {
    store = MemoryServerConfigStore();
    preset = const AppEnvironment(
      apiBaseUrl: 'https://preset.example.com/api/v1',
      wsBaseUrl: 'wss://preset.example.com/ws',
    );
    container = ProviderContainer(
      overrides: [
        serverConfigStoreProvider.overrideWithValue(store),
        presetAppEnvironmentProvider.overrideWithValue(preset),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('未自定义时生效预置', () {
    expect(container.read(appEnvironmentProvider), same(preset));
  });

  test('自定义配置优先于预置', () async {
    final config = ServerConfig.tryParse('https://custom.example.com')!;
    await container.read(serverConfigProvider.notifier).apply(config);

    expect(
      container.read(appEnvironmentProvider)?.apiBaseUrl,
      'https://custom.example.com/api/v1',
    );
  });

  test('清除自定义后回落预置（预置不落库）', () async {
    final config = ServerConfig.tryParse('https://custom.example.com')!;
    await container.read(serverConfigProvider.notifier).apply(config);

    await container.read(serverConfigProvider.notifier).clear();

    expect(container.read(appEnvironmentProvider), same(preset));
  });

  test('自定义与预置均无时为未配置', () {
    final empty = ProviderContainer(
      overrides: [
        serverConfigStoreProvider.overrideWithValue(MemoryServerConfigStore()),
        presetAppEnvironmentProvider.overrideWithValue(null),
      ],
    );
    addTearDown(empty.dispose);

    expect(empty.read(appEnvironmentProvider), isNull);
  });

  test('存储中已有自定义时启动即优先生效', () async {
    final seeded = MemoryServerConfigStore();
    await seeded.write(ServerConfig.tryParse('https://boot.example.com')!);
    final booted = ProviderContainer(
      overrides: [
        serverConfigStoreProvider.overrideWithValue(seeded),
        presetAppEnvironmentProvider.overrideWithValue(preset),
      ],
    );
    addTearDown(booted.dispose);

    await booted.read(serverConfigProvider.future);
    expect(
      booted.read(appEnvironmentProvider)?.apiBaseUrl,
      'https://boot.example.com/api/v1',
    );
  });
}
