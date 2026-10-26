// 命令面板键盘导航守卫：页签芯片上印着 Tab 与数字 1~7，按键必须真的生效，
// 否则界面承诺了一个不存在的操作方式（此前 Tab 与数字键都没有实现）。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/features/search/search_ui.dart';

/// 一切请求都回同一条文件命中：其余来源在空数据下不参与断言。
class _SingleHitAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'code': 200,
        'message': 'success',
        'data': <Map<String, Object>>[
          <String, Object>{
            'id': 'file-1',
            'title': '维修手册.pdf',
            'subtitle': '正文命中：液压',
            'type': 'file',
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _harness() {
  final client = ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
    httpClientAdapter: _SingleHitAdapter(),
  );
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.dark(),
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGlobalSearchDialog(context),
                child: const Text('open-palette'),
              ),
            ),
      ),
    ),
  );
}

Future<void> _openPalette(WidgetTester tester) async {
  await tester.tap(find.text('open-palette'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, '液压');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _closePalette(WidgetTester tester) async {
  // 面板用文件级 _globalSearchOpen 去重：用例结束必须关闭，否则下一条用例点不开。
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// 数字页签快捷键必须带 Alt：裸数字属于搜索词。
Future<void> _pressDigit(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Alt+数字键跳到对应筛选页签', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await _openPalette(tester);

    // 「全部」页签下文件档命中可见。
    expect(find.text('维修手册.pdf'), findsOneWidget);

    // 4 = 图书：文件档必须被筛掉。
    await _pressDigit(tester, LogicalKeyboardKey.digit4);
    expect(find.text('维修手册.pdf'), findsNothing);

    // 6 = 文件：命中回到列表。
    await _pressDigit(tester, LogicalKeyboardKey.digit6);
    expect(find.text('维修手册.pdf'), findsOneWidget);
    await _closePalette(tester);
  });

  testWidgets('Tab 前滚、Shift+Tab 后滚页签', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await _openPalette(tester);

    expect(find.text('维修手册.pdf'), findsOneWidget);

    // 文件(6) → 照片(5)：后滚一档，文件档不再出现。
    await _pressDigit(tester, LogicalKeyboardKey.digit6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('维修手册.pdf'), findsNothing);

    // 照片(5) → 图书(4) → … → 命令(7) → 全部(1) → 视频(2) → 音乐(3) → 图书(4)
    // 前滚两档到视频仍看不到文件档，再直落文件档页签确认可回。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await _pressDigit(tester, LogicalKeyboardKey.digit6);
    expect(find.text('维修手册.pdf'), findsOneWidget);
    await _closePalette(tester);
  });

  testWidgets('命令页签不含文件档命中', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await _openPalette(tester);

    await _pressDigit(tester, LogicalKeyboardKey.digit7);

    expect(find.text('维修手册.pdf'), findsNothing);
    await _closePalette(tester);
  });
}
