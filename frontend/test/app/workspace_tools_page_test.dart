// 工作区工具总入口回归（原型 FeatureDirectory）：分组与行数、行标题/描述
// 同源复用模块既有标签，且每行都真的落到目标路由——不留死键。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/workspace_tools_page.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';

void main() {
  Future<void> pumpTools(WidgetTester tester, {double textScale = 1.0}) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/tools',
      routes: [
        GoRoute(
          path: '/tools',
          builder:
              (context, state) => const MobileShellScope(
                hosted: true,
                child: Scaffold(body: WorkspaceToolsPage()),
              ),
        ),
        GoRoute(
          path: '/files',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: Text(
                    'files-section:${state.uri.queryParameters['section']}',
                  ),
                ),
              ),
        ),
        GoRoute(
          path: '/music/history',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('music-history'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('目录列出两个分组与全部已落地目标', (tester) async {
    await pumpTools(tester);

    expect(find.text('完整清单'), findsOneWidget);
    expect(find.text('每样东西都有一个家。'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('影视与音乐'), findsOneWidget);

    // Files 八行 + 音乐播放历史一行。
    for (final title in <String>[
      '最近使用',
      '我的收藏',
      '我的分享',
      '离线下载',
      '存储统计',
      '外部存储',
      '导入任务',
      '上传队列',
      '播放历史',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少工具行 $title');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Files 行按分区直达 /files?section=', (tester) async {
    await pumpTools(tester);

    await tester.ensureVisible(find.text('我的分享'));
    await tester.tap(find.text('我的分享'));
    await tester.pumpAndSettle();
    expect(find.text('files-section:myShares'), findsOneWidget);
  });

  testWidgets('表尾的 Files 行同样可达（列表需先滚入视口）', (tester) async {
    await pumpTools(tester);

    await tester.ensureVisible(find.text('上传队列'));
    await tester.tap(find.text('上传队列'));
    await tester.pumpAndSettle();
    expect(find.text('files-section:uploadQueue'), findsOneWidget);
  });

  testWidgets('音乐行进入播放历史页', (tester) async {
    await pumpTools(tester);

    await tester.ensureVisible(find.text('播放历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('播放历史'));
    await tester.pumpAndSettle();
    expect(find.text('music-history'), findsOneWidget);
  });

  testWidgets('1.6x 字号下目录行不溢出且保持单行截断', (tester) async {
    await pumpTools(tester, textScale: 1.6);

    expect(tester.takeException(), isNull);
    expect(find.text('每样东西都有一个家。'), findsOneWidget);
    expect(find.text('存储统计'), findsOneWidget);
  });
}
