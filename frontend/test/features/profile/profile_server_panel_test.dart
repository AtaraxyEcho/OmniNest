import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/server/server_config_store_base.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_server_panel.dart';

Future<void> _pumpPanel(
  WidgetTester tester, {
  required MemoryServerConfigStore store,
  AppEnvironment? preset,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const ProfileServerPanel()),
      GoRoute(
        path: '/server-setup',
        builder: (_, _) => const Scaffold(key: Key('server-setup-marker')),
      ),
    ],
  );
  addTearDown(router.dispose);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverConfigStoreProvider.overrideWithValue(store),
        presetAppEnvironmentProvider.overrideWithValue(preset),
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    ),
  );
}

void main() {
  testWidgets('自定义配置展示地址与自定义徽标', (tester) async {
    final store = MemoryServerConfigStore();
    await store.write(ServerConfig.tryParse('https://custom.example.com')!);
    await _pumpPanel(tester, store: store, preset: null);
    await tester.pumpAndSettle();

    expect(find.text('https://custom.example.com/api/v1'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('更改服务器'), findsOneWidget);
  });

  testWidgets('仅预置时展示预置徽标', (tester) async {
    await _pumpPanel(
      tester,
      store: MemoryServerConfigStore(),
      preset: const AppEnvironment(
        apiBaseUrl: 'https://preset.example.com/api/v1',
        wsBaseUrl: 'wss://preset.example.com/ws',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('https://preset.example.com/api/v1'), findsOneWidget);
    expect(find.text('预置（未修改）'), findsOneWidget);
  });

  testWidgets('确认更改后清除配置并进入引导页', (tester) async {
    final store = MemoryServerConfigStore();
    await store.write(ServerConfig.tryParse('https://custom.example.com')!);
    await _pumpPanel(tester, store: store, preset: null);
    await tester.pumpAndSettle();

    await tester.tap(find.text('更改服务器'));
    await tester.pumpAndSettle();
    expect(find.text('更改服务器？'), findsOneWidget);

    await tester.tap(find.text('退出并更改'));
    await tester.pumpAndSettle();

    expect(await store.read(), isNull);
    expect(find.byKey(const Key('server-setup-marker')), findsOneWidget);
  });

  testWidgets('取消更改不触碰配置', (tester) async {
    final store = MemoryServerConfigStore();
    final config = ServerConfig.tryParse('https://custom.example.com')!;
    await store.write(config);
    await _pumpPanel(tester, store: store, preset: null);
    await tester.pumpAndSettle();

    await tester.tap(find.text('更改服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect((await store.read())?.apiBaseUrl, config.apiBaseUrl);
    expect(find.byKey(const Key('server-setup-marker')), findsNothing);
  });
}
