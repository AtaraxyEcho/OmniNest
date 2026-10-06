// 整月下钻回归：托管时间线在月份只下发预览时给出跳转，落点的整月页
// 必须落壳层玻璃皮肤（样例 photo-groups → .album-grid），而不是桌面 SliverAppBar；
// 桌面宽窗保持原有工位形态。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/presentation/pages/photo_period_page.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_hosted_chrome.dart';

const _caps = UserCapabilities(
  canBrowseContent: true,
  canContributeContent: true,
  canManageOwnActivity: true,
  canManagePreferences: true,
  canManageAccount: true,
  canUseBackdropLibrary: true,
  canUploadBackdrop: true,
  canViewOwnTasks: true,
  canAdminTasks: true,
  canManageMediaLibrary: true,
  canManagePhotos: true,
  canAdminUsers: true,
  canReadSystemConfig: true,
  canManageSystemConfig: true,
  canAccessAdminConsole: true,
  canSharedBrowse: true,
  canSharedUpload: true,
  canReadWeather: true,
  canReportLocation: true,
  canManageTwoFactor: true,
  canReadActivity: true,
);

PhotoItem _photo(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'IMAGE',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026, 9, 3),
  );
}

/// 九月只下发 2 张预览（整月 42 张），八月预览即全量。
class _FakePhotoCenter extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: [_photo('p1'), _photo('p2')],
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
      photoTotalElements: 44,
      frameView: FrameView.timeline,
      timeline: PhotoTimeline(
        years: [
          PhotoYearGroup(
            year: 2026,
            months: [
              PhotoMonthGroup(
                month: 9,
                photoCount: 42,
                previewPhotos: [_photo('p1'), _photo('p2')],
              ),
              PhotoMonthGroup(
                month: 8,
                photoCount: 2,
                previewPhotos: [_photo('p3'), _photo('p4')],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadTimeline({bool force = false}) async {}
}

/// 整月状态直接 seeding：页面 initState 的 open 与滚动 loadMore 都短路，
/// 只验外壳与分页呈现。
class _FakePeriodNotifier extends PhotoPeriodNotifier {
  _FakePeriodNotifier(this._seed);

  final PhotoPeriodState _seed;

  @override
  PhotoPeriodState build() => _seed;

  @override
  Future<void> open(int year, int month) async {}

  @override
  Future<void> loadMore() async {}
}

PhotoPeriodState _seedState({required bool hasMore}) {
  return PhotoPeriodState(
    period: (2026, 9),
    photos: [_photo('p1'), _photo('p2'), _photo('p3')],
    totalElements: 42,
    nextPage: 1,
    hasMore: hasMore,
  );
}

/// 常驻骨架/指示器动画不会自然收敛，统一用固定时长推进。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required String initialLocation,
  required Size surface,
  PhotoPeriodState? periodState,
  bool hostedPeriodPage = true,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final overrides = [
    authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
    userCapabilitiesProvider.overrideWithValue(_caps),
    photoCenterControllerProvider.overrideWith(() => _FakePhotoCenter()),
    if (periodState != null)
      photoPeriodProvider.overrideWith(() => _FakePeriodNotifier(periodState)),
  ];

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/library',
        builder:
            (context, state) =>
                const Scaffold(body: Center(child: Text('library-home'))),
      ),
      GoRoute(
        path: '/photos',
        builder:
            (context, state) => const MobileShellScope(
              hosted: true,
              child: Scaffold(
                backgroundColor: Color(0xFF0B1110),
                body: PhotosPage(),
              ),
            ),
      ),
      GoRoute(
        path: '/photos/period/:year/:month',
        builder:
            (context, state) => MobileShellScope(
              // 形态用显式作用域声明，与壳层同一口径，不依赖测试宿主平台。
              hosted: hostedPeriodPage,
              child: PhotoPeriodPage(
                year: int.parse(state.pathParameters['year']!),
                month: int.parse(state.pathParameters['month']!),
              ),
            ),
      ),
      GoRoute(
        path: '/photos/:photoId',
        builder:
            (context, state) =>
                const Scaffold(body: Center(child: Text('photo-viewer'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        // 桌面分支取 context.photosColors，需要注册了模块色板的主题。
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        routerConfig: router,
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('托管时间线只为仍有剩余的月份给整月跳转', (tester) async {
    await _pump(
      tester,
      initialLocation: '/photos',
      surface: const Size(390, 844),
    );

    expect(find.text('时间线'), findsWidgets);
    expect(find.text('查看全部 42 张'), findsOneWidget);
    expect(find.text('查看全部 2 张'), findsNothing, reason: '预览即全量时不给空跳转');
    expect(tester.takeException(), isNull);
  });

  testWidgets('整月页在托管态落壳层玻璃皮肤并保留分页位', (tester) async {
    await _pump(
      tester,
      initialLocation: '/photos',
      surface: const Size(390, 844),
      periodState: _seedState(hasMore: true),
    );

    await tester.tap(find.text('查看全部 42 张'));
    await settle(tester);

    expect(find.text('photo-viewer'), findsNothing);
    expect(find.byType(MobilePageSurface), findsOneWidget);
    expect(find.byType(PhotoHostedPhotoGrid), findsOneWidget);
    expect(find.byType(SliverAppBar), findsNothing, reason: '托管态不得再用桌面吸顶栏');
    expect(find.text('42 张照片'), findsOneWidget);
    expect(find.text('加载更多（已加载 3 / 42）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整月页末页不再出现加载位', (tester) async {
    await _pump(
      tester,
      initialLocation: '/photos/period/2026/9',
      surface: const Size(390, 844),
      periodState: _seedState(hasMore: false),
    );

    expect(find.byType(PhotoHostedPhotoGrid), findsOneWidget);
    expect(find.textContaining('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面宽窗整月页保持工位 SliverAppBar 形态', (tester) async {
    await _pump(
      tester,
      initialLocation: '/photos/period/2026/9',
      surface: const Size(1280, 800),
      periodState: _seedState(hasMore: true),
      hostedPeriodPage: false,
    );

    expect(find.byType(SliverAppBar), findsOneWidget);
    expect(find.byType(MobilePageSurface), findsNothing, reason: '非托管不得套壳层表面');
    expect(find.textContaining('加载更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
