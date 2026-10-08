// 托管影视胶囊行与状态筛选面板回归：排序/收藏胶囊按样例 `.chip`（r11、9px、
// 半透明 tint 底、gap 7、行高 38），酸绿选中态，状态筛选落 `.glass-sheet` 实底面板
// 并以行族呈现选项。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_mobile_chips.dart';

Future<void> _pump(
  WidgetTester tester, {
  MovieSortBy sortBy = MovieSortBy.dateAdded,
  MovieLibraryFilter filter = MovieLibraryFilter.all,
  ValueChanged<MovieSortBy>? onSortBy,
  ValueChanged<MovieLibraryFilter>? onFilter,
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
          backgroundColor: MobileEnvColors.stage,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MovieRedesignMobileChips(
                sortBy: sortBy,
                onSortBy: onSortBy ?? (_) {},
                favoritesOnly: false,
                onFavoritesOnly: (_) {},
                filter: filter,
                onFilter: onFilter ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 单个胶囊的按压层：按标签定位，避免用遍历顺序猜是哪一颗。
Finder _chipInkWell(String label) {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  expect(finder.evaluate(), hasLength(1), reason: '$label 只应有一个按压层');
  return finder;
}

Material _chipMaterial(WidgetTester tester, String label) {
  final candidates =
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .evaluate()
          .map((element) => element.widget as Material)
          .where((material) => material.shape is RoundedRectangleBorder)
          .toList();
  expect(candidates, hasLength(1), reason: '$label 只应有一个胶囊容器');
  return candidates.single;
}

void main() {
  testWidgets('选中胶囊用酸绿档，未选中用玻璃底与发丝线', (tester) async {
    await _pump(tester);

    final selected = _chipMaterial(tester, '最新');
    final plain = _chipMaterial(tester, '评分');
    final selectedShape = selected.shape as RoundedRectangleBorder;
    final plainShape = plain.shape as RoundedRectangleBorder;

    expect(selected.color, MobileEnvColors.accent.withValues(alpha: 0.10));
    expect(
      selectedShape.side.color,
      MobileEnvColors.accent.withValues(alpha: 0.38),
    );
    expect(plain.color, MobileEnvPalette.dark.surfaceTint);
    expect(plainShape.side.color, MobileEnvColors.line09);
    // 工位件是 2px 直角；托管胶囊按样例圆角。
    expect(
      selectedShape.borderRadius,
      const BorderRadius.all(Radius.circular(11)),
    );
    expect(
      plainShape.borderRadius,
      const BorderRadius.all(Radius.circular(11)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('胶囊字号与间距按样例，行高取次级档', (tester) async {
    await _pump(tester);

    expect(tester.widget<Text>(find.text('评分')).style?.fontSize, 9);

    final first = tester.getRect(_chipInkWell('最新'));
    final second = tester.getRect(_chipInkWell('评分'));
    expect(second.left - first.right, 7);
    // 样例视觉高 32 低于次级控件 35-45 档，且横向行旁就是 38 的筛选钮，
    // 扩命中必然撑行：胶囊按行高档落地。
    expect(first.height, 38);
    expect(second.height, 38);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点排序胶囊回写排序枚举', (tester) async {
    MovieSortBy? sorted;
    await _pump(tester, onSortBy: (value) => sorted = value);

    await tester.tap(find.text('评分'));
    await tester.pump();

    expect(sorted, MovieSortBy.rating);
  });

  testWidgets('状态筛选面板走玻璃底与行族，选项回写筛选枚举', (tester) async {
    MovieLibraryFilter? picked;
    await _pump(tester, onFilter: (value) => picked = value);

    await tester.tap(find.byTooltip('状态筛选'));
    await tester.pumpAndSettle();

    expect(find.text('状态筛选'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing, reason: '不再是工位 ListTile 列表');
    expect(find.byType(MobilePressable), findsNWidgets(4));
    expect(find.widgetWithText(MobilePressable, '有问题'), findsOneWidget);

    await tester.tap(find.widgetWithText(MobilePressable, '有问题'));
    await tester.pumpAndSettle();

    expect(picked, MovieLibraryFilter.failed);
    expect(tester.takeException(), isNull);
  });
}
