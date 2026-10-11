// 工作区工具总入口回归（原型 FeatureDirectory）：只列模块内没有一级入口的
// 页面，行标题/描述同源复用模块既有标签，每行都真的落到目标路由——不留死键。
//
// 挂载形态与 router.dart 一致：MobileHostedRoute 直接包住页面，不额外套
// Scaffold。多套一层 Scaffold 会把 MaterialApp 的兜底正文样式（monospace /
// 黄色双下划线）挡在外面，双横线缺陷正是在测试里看不见、真机上满屏都是。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/mobile_shell/workspace_tools_page.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 表内全部行，按分组顺序。
const _rows = <String>['我的分享', '合集', '观看历史', '本地资源', '影片管理', '年·月'];

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
              (context, state) =>
                  const MobileHostedRoute(child: WorkspaceToolsPage()),
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
            : OmniNestTheme.light();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileShellLocalBackdropActiveProvider.overrideWithValue(false),
        ],
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

  testWidgets('目录只列模块内无处可去的页面，三个分组六行', (tester) async {
    await pumpTools(tester);

    expect(find.text('完整清单'), findsOneWidget);
    expect(find.text('每样东西都有一个家。'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('影视与音乐'), findsOneWidget);
    expect(find.text('相册与阅读'), findsOneWidget);

    for (final title in _rows) {
      await reveal(tester, title);
      expect(find.text(title), findsOneWidget, reason: '缺少工具行 $title');
    }

    // Files 首页四张分区卡与三枚工具快捷已各自可达，音乐岛也有播放历史入口，
    // 这些页面不再在目录里出现第二份。
    for (final duplicate in const [
      '最近使用',
      '我的收藏',
      '离线下载',
      '存储统计',
      '外部存储',
      '导入任务',
      '上传队列',
      '播放历史',
    ]) {
      expect(find.text(duplicate), findsNothing, reason: '$duplicate 已有模块内入口');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('每行都落到目标路由', (tester) async {
    await pumpTools(tester);

    await tester.tap(find.text('我的分享'));
    await tester.pumpAndSettle();
    expect(find.text('files-section:myShares'), findsOneWidget);

    await pumpTools(tester);
    await reveal(tester, '合集');
    await tester.tap(find.text('合集'));
    await tester.pumpAndSettle();
    expect(find.text('video-section:collections'), findsOneWidget);

    await pumpTools(tester);
    await reveal(tester, '观看历史');
    await tester.tap(find.text('观看历史'));
    await tester.pumpAndSettle();
    expect(find.text('video-section:history'), findsOneWidget);

    await pumpTools(tester);
    await reveal(tester, '本地资源');
    await tester.tap(find.text('本地资源'));
    await tester.pumpAndSettle();
    expect(find.text('music-scan'), findsOneWidget);

    await pumpTools(tester);
    await reveal(tester, '影片管理');
    await tester.tap(find.text('影片管理'));
    await tester.pumpAndSettle();
    expect(find.text('video-section:management'), findsOneWidget);

    await pumpTools(tester);
    await reveal(tester, '年·月');
    await tester.tap(find.text('年·月'));
    await tester.pumpAndSettle();
    expect(find.text('photo-groups'), findsOneWidget);
  });

  testWidgets('页面不带 Scaffold，也不得继承兜底正文样式', (tester) async {
    await pumpTools(tester);
    await reveal(tester, '年·月');

    // MaterialApp 的兜底 DefaultTextStyle 是 monospace + 48px + 黄色双下划线：
    // 字重字号会被各自行样式盖掉，只有下划线留下来，看起来就是字底下多两道线。
    for (final label in <String>[
      '完整清单',
      '每样东西都有一个家。',
      '文件',
      '我的分享',
      '年·月',
      ..._rows,
    ]) {
      final style =
          tester.renderObject<RenderParagraph>(find.text(label)).text.style!;
      expect(
        style.decoration,
        isNot(TextDecoration.underline),
        reason: '$label 拿到了兜底下划线',
      );
    }
  });

  testWidgets('1.6x 字号下目录行不溢出且保持单行截断', (tester) async {
    await pumpTools(tester, textScale: 1.6);

    expect(tester.takeException(), isNull);
    expect(find.text('每样东西都有一个家。'), findsOneWidget);
    await reveal(tester, '影片管理');
    expect(find.text('影片管理'), findsOneWidget);
  });

  testWidgets('浅色极性下目录文字取浅实例墨色，不残留暗栈白字', (tester) async {
    await pumpTools(tester, brightness: Brightness.light);
    await reveal(tester, '本地资源');

    Color inkOf(String label) =>
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .text
            .style!
            .color!;

    expect(inkOf('文件'), MobileEnvPalette.light.groupLabelInk, reason: '分组眉标');
    expect(inkOf('每样东西都有一个家。'), MobileEnvPalette.light.ink, reason: '衬线标题');
    expect(inkOf('本地资源'), MobileEnvPalette.light.ink, reason: '行标题');
    expect(inkOf('本地资源'), isNot(MobileEnvPalette.dark.ink));
  });
}
