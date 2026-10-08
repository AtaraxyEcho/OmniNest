// 工作区工具总入口回归（原型 FeatureDirectory）：分组与行数、行标题/描述
// 同源复用模块既有标签，且每行都真的落到目标路由——不留死键。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/workspace_tools_page.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';

void main() {
  Future<void> pumpTools(
    WidgetTester tester, {
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
  }) async {
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
        GoRoute(
          path: '/video',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: Text(
                    'video-section:${state.uri.queryParameters['section']}',
                  ),
                ),
              ),
        ),
        GoRoute(
          path: '/photos/groups',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('photo-groups'))),
        ),
        GoRoute(
          path: '/music/scan',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('music-scan'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final rootTheme =
        brightness == Brightness.dark
            ? OmniNestTheme.dark()
            : MobileAppTheme.resolve(OmniNestTheme.light());

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: rootTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// ListView 只构建视口加缓存范围内的行，表尾行要先滚进来。
  Future<void> reveal(WidgetTester tester, String label) async {
    await tester.dragUntilVisible(
      find.text(label),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('目录列出两个分组与全部已落地目标', (tester) async {
    await pumpTools(tester);

    expect(find.text('完整清单'), findsOneWidget);
    expect(find.text('每样东西都有一个家。'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('影视与音乐'), findsOneWidget);

    // Files 八行；表尾两行（影视观看历史、音乐播放历史）需滚入后才构建。
    for (final title in <String>[
      '最近使用',
      '我的收藏',
      '我的分享',
      '离线下载',
      '存储统计',
      '外部存储',
      '导入任务',
      '上传队列',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少工具行 $title');
    }
    await reveal(tester, '合集');
    expect(find.text('合集'), findsOneWidget);
    await reveal(tester, '观看历史');
    expect(find.text('观看历史'), findsOneWidget);
    await reveal(tester, '播放历史');
    expect(find.text('播放历史'), findsOneWidget);
    await reveal(tester, '本地资源');
    expect(find.text('本地资源'), findsOneWidget);
    expect(find.text('相册与阅读'), findsOneWidget);
    await reveal(tester, '年·月');
    expect(find.text('年·月'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地资源行进入扫描页', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '本地资源');
    await tester.tap(find.text('本地资源'));
    await tester.pumpAndSettle();
    expect(find.text('music-scan'), findsOneWidget);
  });

  testWidgets('年·月行进入分组页', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '年·月');
    await tester.tap(find.text('年·月'));
    await tester.pumpAndSettle();
    expect(find.text('photo-groups'), findsOneWidget);
  });

  testWidgets('合集行直达 /video?section=collections', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '合集');
    await tester.tap(find.text('合集'));
    await tester.pumpAndSettle();
    expect(find.text('video-section:collections'), findsOneWidget);
  });

  testWidgets('影片管理行直达 /video?section=management', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '影片管理');
    await tester.tap(find.text('影片管理'));
    await tester.pumpAndSettle();
    expect(find.text('video-section:management'), findsOneWidget);
  });

  testWidgets('Files 行按分区直达 /files?section=', (tester) async {
    await pumpTools(tester);

    await tester.tap(find.text('我的分享'));
    await tester.pumpAndSettle();
    expect(find.text('files-section:myShares'), findsOneWidget);
  });

  testWidgets('表尾的 Files 行同样可达（列表需先滚入视口）', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '上传队列');
    await tester.tap(find.text('上传队列'));
    await tester.pumpAndSettle();
    expect(find.text('files-section:uploadQueue'), findsOneWidget);
  });

  testWidgets('观看历史行直达 /video?section=history', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '观看历史');
    await tester.tap(find.text('观看历史'));
    await tester.pumpAndSettle();
    expect(find.text('video-section:history'), findsOneWidget);
  });

  testWidgets('音乐行进入播放历史页', (tester) async {
    await pumpTools(tester);

    await reveal(tester, '播放历史');
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

  testWidgets('浅色极性下目录文字取浅实例墨色，不残留暗栈白字', (tester) async {
    await pumpTools(tester, brightness: Brightness.light);

    Color inkOf(String label) =>
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .text
            .style!
            .color!;

    expect(inkOf('文件'), MobileEnvPalette.light.inkFaint, reason: '分组眉标');
    expect(inkOf('每样东西都有一个家。'), MobileEnvPalette.light.ink, reason: '衬线标题');
    expect(inkOf('存储统计'), MobileEnvPalette.light.ink, reason: '行标题');
    expect(inkOf('存储统计'), isNot(MobileEnvPalette.dark.ink));
  });
}
