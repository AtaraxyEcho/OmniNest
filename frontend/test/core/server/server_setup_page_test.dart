import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/server/server_config.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/server/server_config_store_base.dart';
import 'package:omninest/core/server/server_probe_client.dart';
import 'package:omninest/core/server/server_setup_controller.dart';
import 'package:omninest/core/server/presentation/server_setup_page.dart';

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

Future<void> _pumpPage(
  WidgetTester tester, {
  required MemoryServerConfigStore store,
  _FakeProbeClient? probe,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverConfigStoreProvider.overrideWithValue(store),
        serverProbeClientProvider.overrideWithValue(
          probe ?? _FakeProbeClient(),
        ),
        serverRequireHttpsProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const ServerSetupPage(),
      ),
    ),
  );
}

void main() {
  late MemoryServerConfigStore store;

  setUp(() {
    store = MemoryServerConfigStore();
  });

  testWidgets('渲染标题、输入框与连接按钮', (tester) async {
    await _pumpPage(tester, store: store);
    await tester.pumpAndSettle();

    expect(find.text('连接你的 OmniNest'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
  });

  testWidgets('非法地址点击连接显示解析错误', (tester) async {
    final probe = _FakeProbeClient();
    await _pumpPage(tester, store: store, probe: probe);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '服务器地址'), '###');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(find.text('地址无法解析，请检查后重试'), findsOneWidget);
    expect(probe.callCount, 0);
  });

  testWidgets('http 地址展示明文警告与归一化预览', (tester) async {
    await _pumpPage(tester, store: store);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      '192.168.1.10:8080',
    );
    await tester.pump();

    expect(find.text('将连接：http://192.168.1.10:8080/api/v1'), findsOneWidget);
    expect(find.text('当前为明文 HTTP 连接，公网环境建议使用 HTTPS'), findsOneWidget);
  });

  testWidgets('探活失败显示不可达错误且不写入配置', (tester) async {
    final probe = _FakeProbeClient(
      result: const ServerProbeResult.failure(ServerProbeFailure.unreachable),
    );
    await _pumpPage(tester, store: store, probe: probe);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'https://nest.example.com',
    );
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(find.text('无法连接到服务器，请确认地址与网络'), findsOneWidget);
    expect(await store.read(), isNull);
  });

  testWidgets('探活成功写入配置', (tester) async {
    await _pumpPage(tester, store: store);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'https://nest.example.com',
    );
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect((await store.read())?.apiBaseUrl, 'https://nest.example.com/api/v1');
  });

  testWidgets('探活进行中按钮禁用且重复点击不重复探活', (tester) async {
    final pending = Completer<ServerProbeResult>();
    final probe = _FakeProbeClient(pending: pending);
    await _pumpPage(tester, store: store, probe: probe);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'https://nest.example.com',
    );
    await tester.tap(find.text('连接'));
    await tester.pump();
    await tester.tap(find.text('正在连接…'), warnIfMissed: false);
    await tester.pump();

    expect(probe.callCount, 1);
    expect(find.text('正在连接…'), findsOneWidget);

    pending.complete(const ServerProbeResult.success(requiredSetup: false));
    await tester.pumpAndSettle();
    expect((await store.read())?.apiBaseUrl, 'https://nest.example.com/api/v1');
  });
}
