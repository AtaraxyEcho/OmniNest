// 观看历史托管形态与分区深链解析回归：托管态必须落原型 `.feature-list`
// 行族（环境眉标 + 发丝线行 + 38 行内动作），不再落工位重设计卡；
// `/video?section=` 只认枚举名。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_history.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_history_row.dart';

MovieWatchHistory _history({
  required String videoItemId,
  required String title,
  bool completed = false,
}) {
  return MovieWatchHistory(
    id: 'h-$videoItemId',
    videoItemId: videoItemId,
    title: title,
    positionSeconds: completed ? 100 : 42,
    durationSeconds: 100,
    completed: completed,
    playedAt: DateTime(2026, 10, 5, 20, 30),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<MovieWatchHistory> items,
  bool canManageActivity = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: MobileShellScope(
        hosted: true,
        child: Scaffold(
          body: SingleChildScrollView(
            child: HostedHistorySection(
              items: items,
              onDelete: canManageActivity ? (_) {} : null,
              onClearAll: canManageActivity ? () {} : null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('托管观看历史用环境眉标与发丝线行', (tester) async {
    await _pump(
      tester,
      items: [
        _history(videoItemId: 'v1', title: 'Mirage'),
        _history(videoItemId: 'v2', title: 'Spring trip', completed: true),
      ],
    );

    expect(find.byType(MobileEnvSectionHeader), findsOneWidget);
    // 眉标取值来自样例 .section-title > small：9px / 字距 1.5，浅态第 4 层把它
    // 与 .notif-group 归到同一档淡墨（rgba(26,29,27,.58)），暗态是主墨 43%。
    // 标题 21，不是卡片区头档的 24。
    final headerTexts = find.descendant(
      of: find.byType(MobileEnvSectionHeader),
      matching: find.byType(Text),
    );
    final eyebrow = tester.widget<Text>(headerTexts.first);
    expect(eyebrow.style?.color, MobileEnvPalette.dark.groupLabelInk);
    expect(eyebrow.style?.fontSize, 9);
    expect(eyebrow.style?.letterSpacing, 1.5);
    expect(eyebrow.style?.height, 1.45);
    final sectionTitle = tester.widget<Text>(headerTexts.last);
    expect(sectionTitle.style?.fontSize, 21);
    expect(find.byType(MobileFeatureListRow), findsNWidgets(2));
    expect(
      find.byType(MovieRedesignHistoryList),
      findsNothing,
      reason: '托管态不得再落工位重设计历史卡',
    );
    expect(find.text('观看历史'), findsOneWidget);
    expect(find.text('Mirage'), findsOneWidget);
    // 明细含相对时间与进度，完成档显示 100%。
    expect(find.textContaining('100%'), findsOneWidget);
    expect(find.byTooltip('删除'), findsNWidgets(2));
    expect(find.byTooltip('清空历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 activity 权限时历史只读', (tester) async {
    await _pump(
      tester,
      items: [_history(videoItemId: 'v1', title: 'Mirage')],
      canManageActivity: false,
    );

    expect(find.byType(MobileFeatureListRow), findsOneWidget);
    expect(find.byTooltip('删除'), findsNothing);
    expect(find.byTooltip('清空历史'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空历史走环境空态而不是空列表', (tester) async {
    await _pump(tester, items: const []);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('暂无观看历史。'), findsOneWidget);
    expect(find.byType(MobileFeatureListRow), findsNothing);
    expect(find.byTooltip('清空历史'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('分区深链只认枚举名', () {
    expect(movieSectionFromRouteName('history'), MovieSection.history);
    expect(movieSectionFromRouteName('collections'), MovieSection.collections);
    expect(movieSectionFromRouteName('drop TABLE'), isNull);
    expect(movieSectionFromRouteName(''), isNull);
    expect(movieSectionFromRouteName(null), isNull);
  });
}
