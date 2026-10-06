// 年·月分组页回归（原型 photo-groups 工具页 .year-jump）：年份衬线大字 +
// 全年张数 + 4 列月份砖（月名/张数），点砖进该月整月浏览；
// 时间线未就绪给骨架，确实无照片才给空态。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/presentation/pages/photo_groups_page.dart';

class _FakePhotoCenter extends PhotoCenterController {
  _FakePhotoCenter(this._timeline);

  final PhotoTimeline? _timeline;

  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: const [],
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
      timeline: _timeline,
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadTimeline({bool force = false}) async {}
}

PhotoMonthGroup _month(int month, int photoCount) {
  // 不给预览照片：月份砖走占位底色分支，测试不触达缩略图网络。
  return PhotoMonthGroup(
    month: month,
    photoCount: photoCount,
    previewPhotos: const [],
  );
}

Future<void> _pump(WidgetTester tester, PhotoTimeline? timeline) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/photos/groups',
    routes: [
      GoRoute(
        path: '/photos/groups',
        builder: (context, state) => const Scaffold(body: PhotoGroupsPage()),
      ),
      GoRoute(
        path: '/photos/period/:year/:month',
        builder:
            (context, state) => Scaffold(
              body: Center(
                child: Text(
                  'period:${state.pathParameters['year']}-${state.pathParameters['month']}',
                ),
              ),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _FakePhotoCenter(timeline),
        ),
      ],
      child: MaterialApp.router(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        routerConfig: router,
      ),
    ),
  );
  // 骨架块自带常驻微光动画，pumpAndSettle 永不收敛：按固定时长推进。
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('年份行给出衬线年份与全年张数，月份砖给月名与张数', (tester) async {
    await _pump(
      tester,
      PhotoTimeline(
        years: [
          PhotoYearGroup(year: 2026, months: [_month(9, 42), _month(8, 17)]),
        ],
      ),
    );

    expect(find.byType(MobilePageSurface), findsOneWidget);
    expect(find.text('年·月'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('59 张照片'), findsOneWidget);
    expect(find.text('9月'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点月份砖进入该月整月浏览', (tester) async {
    await _pump(
      tester,
      PhotoTimeline(
        years: [
          PhotoYearGroup(year: 2026, months: [_month(9, 42)]),
        ],
      ),
    );

    await tester.tap(find.text('9月'));
    await tester.pumpAndSettle();
    expect(find.text('period:2026-9'), findsOneWidget);
  });

  testWidgets('确实没有照片时给空态而不是骨架', (tester) async {
    await _pump(tester, const PhotoTimeline(years: []));

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('还没有照片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间线尚未取到时给骨架，不误报空', (tester) async {
    await _pump(tester, null);

    expect(find.byType(EnvEmptyState), findsNothing);
    expect(find.byType(MobileSkeletonBlock), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
