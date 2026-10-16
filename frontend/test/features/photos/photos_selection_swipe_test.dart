// 托管照片页选择模式下的横滑换视图回归。
//
// 页签行在选择模式下会被隐藏，但横滑曾照常生效，于是多选进行中一次误划就
// 悄悄换掉视图（用户看不到页签，无从察觉换到了哪）。现在选择模式关闭分页
// 横滑本身，退出选择模式后跟手换视图照常工作。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_segment_pager.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';

class _FakePhotoCenter extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: [
        PhotoItem(
          id: 'p1',
          fileNodeId: 'p1',
          title: 'West Lake dusk',
          format: 'IMAGE',
          fileSize: 2400000,
          metadataStatus: 'READY',
          favorite: false,
          createdAt: DateTime.now(),
        ),
      ],
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
      photoTotalElements: 1,
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadTimeline({bool force = false}) async {}
}

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

void main() {
  testWidgets('选择模式关掉横滑，退出后换视图照常生效', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 页内存在常驻动画，pumpAndSettle 不收敛：一律固定时长推进。
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    // 挂载形态与 router.dart 一致：照片页需要真实 GoRouter 祖先，
    // 用 MaterialApp(home:) 少挂一层会让页面在取路由时抛 No GoRouter。
    final router = GoRouter(
      initialLocation: '/photos',
      routes: [
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
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          userCapabilitiesProvider.overrideWithValue(_caps),
          photoCenterControllerProvider.overrideWith(() => _FakePhotoCenter()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          routerConfig: router,
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhotosPage)),
    );
    PhotoCenterController notifier() =>
        container.read(photoCenterControllerProvider.notifier);
    FrameView frameView() =>
        container.read(photoCenterControllerProvider).requireValue.frameView;
    MobileSegmentPager<FrameView> pager() =>
        tester.widget<MobileSegmentPager<FrameView>>(
          find.byType(MobileSegmentPager<FrameView>),
        );

    await settle();
    expect(find.byType(PhotosPage), findsOneWidget);
    expect(frameView(), FrameView.grid);
    expect(pager().interactionEnabled, isTrue, reason: '普通浏览态应保留跟手换视图');

    // 浏览态：一次跟手左滑确实换到下一段（否则这条闸门测不到任何行为）。
    await tester.dragFrom(const Offset(300, 500), const Offset(-260, 0));
    await settle();
    expect(frameView(), FrameView.albums);

    notifier().toggleSelectionMode();
    await settle();
    expect(
      container
          .read(photoCenterControllerProvider)
          .requireValue
          .isSelectionMode,
      isTrue,
    );
    expect(
      pager().interactionEnabled,
      isFalse,
      reason: '选择模式下横滑会误换视图，分页手势必须关掉',
    );

    // 行为断言：关掉之后同样的划法不再换段。
    await tester.dragFrom(const Offset(300, 500), const Offset(-260, 0));
    await settle();
    expect(frameView(), FrameView.albums);

    notifier().toggleSelectionMode();
    await settle();
    expect(pager().interactionEnabled, isTrue);

    await tester.dragFrom(const Offset(300, 500), const Offset(-260, 0));
    await settle();
    expect(frameView(), FrameView.favorites, reason: '退出选择模式后横滑要回来');
    expect(tester.takeException(), isNull);
  });
}
