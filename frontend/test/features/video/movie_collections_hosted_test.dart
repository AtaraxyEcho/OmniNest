// 合集托管形态回归：工具目录进来的合集分区必须落原型 `.feature-list` 行族，
// 不再用工位重设计卡；新建与明细面板沿用同一套流程（托管态自动分流为
// 玻璃贴底面板），这里只验外壳与行内容。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_collections.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_collection_card.dart';

MovieCollection _collection(String id, String name, int itemCount) {
  return MovieCollection(
    id: id,
    name: name,
    collectionType: 'MANUAL',
    itemCount: itemCount,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<MovieCollection> collections,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: MobileShellScope(
          hosted: true,
          child: Scaffold(
            body: SingleChildScrollView(
              child: HostedCollectionsSection(collections: collections),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('托管合集用发丝线行与项数明细', (tester) async {
    await _pump(tester, [
      _collection('c1', '电影宇宙', 12),
      _collection('c2', '导演作品集', 3),
    ]);

    expect(find.byType(MobileEnvSectionHeader), findsOneWidget);
    expect(find.byType(MobileFeatureListRow), findsNWidgets(2));
    expect(
      find.byType(MovieRedesignCollectionCard),
      findsNothing,
      reason: '托管态不得再落工位重设计合集卡',
    );
    expect(find.text('合集'), findsOneWidget);
    expect(find.text('电影宇宙'), findsOneWidget);
    expect(find.text('12 项'), findsOneWidget);
    expect(find.text('3 项'), findsOneWidget);
    expect(find.byTooltip('新建合集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空合集走环境空态并给新建行动', (tester) async {
    await _pump(tester, const []);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('这里还没有媒体条目。'), findsOneWidget);
    expect(find.byType(MobileFeatureListRow), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
