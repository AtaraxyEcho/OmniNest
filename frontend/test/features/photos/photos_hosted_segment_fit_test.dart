// 照片托管六段在 390 逻辑宽的可见性回归。
//
// 样例 `.segmented` 是 `width: max-content` + 按钮 `min-width: 66`
// （Refine Light Mode Design/src/index.css:99-100），六段在 390 宽下最小占位
// 6×66 + 5×4 + 2×4 = 424dp，而可用宽度只有 390 - 2×20 = 350dp：
// 样例自身在手机上放不下六段，靠祖先 `main{overflow-y:auto}` 的隐式
// `overflow-x:auto` 横向滚动；他看到的「六个完整显示」是样例在桌面宽度下
// `.module-overlay > main` 限宽 650 居中的形态。
//
// 本轮裁定（A1）：手机上六段必须全部可见，段宽改用等分档
// (390 - 2×20 - 2×4 - 5×4) / 6 ≈ 53.7dp。这是对样例 min-width:66 的
// 记账式偏离，理由与数值一并写在这里，不要当成漏抄。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';

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

/// 中文六段文案（app_zh.arb）：照片 / 影集 / 收藏 / 时间线 / 地点 / 回收站。
const _labels = <String>['照片', '影集', '收藏', '时间线', '地点', '回收站'];

class _FakePhotoCenter extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    final photos = [
      for (var i = 0; i < 6; i++)
        PhotoItem(
          id: 'p$i',
          fileNodeId: 'p$i',
          title: 'West Lake dusk $i',
          format: 'IMAGE',
          fileSize: 2400000,
          metadataStatus: 'READY',
          favorite: i < 2,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
    ];
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: photos,
      favorites: photos.take(2).toList(growable: false),
      albums: const [],
      tab: PhotoTab.all,
      photoTotalElements: 126,
    );
  }
}

Future<void> _pumpHostedPhotos(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 真实入口：PhotosPage 在 initState 的后帧回调里取 GoRouter.of(context)
  // 挂路由监听，桩不给路由器会在首帧后抛「No GoRouter found in context」。
  final router = GoRouter(
    initialLocation: '/photos',
    routes: [
      GoRoute(
        path: '/photos',
        builder: (context, state) => MobileHostedRoute(child: PhotosPage()),
      ),
      GoRoute(
        path: '/library',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
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
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('六段全部落在 350dp 可视带内且等分', (tester) async {
    await _pumpHostedPhotos(tester);

    final bar = find.byType(MobileSegmentedControl<FrameView>);
    expect(bar, findsOneWidget);
    final segments = find.descendant(of: bar, matching: find.byType(InkWell));
    expect(segments, findsNWidgets(6));

    final barRect = tester.getRect(bar);
    expect(
      barRect.width,
      lessThanOrEqualTo(350),
      reason: '胶囊条整体不得超出 390 - 2×20 的内容带',
    );

    double? firstWidth;
    for (var index = 0; index < 6; index++) {
      final rect = tester.getRect(segments.at(index));
      final label = _labels[index];
      expect(rect.left, greaterThanOrEqualTo(20), reason: '$label 段左缘必须在页边距内');
      expect(
        rect.right,
        lessThanOrEqualTo(370),
        reason: '$label 必须完整可见，不能靠横向滚动才够得着',
      );
      firstWidth ??= rect.width;
      expect(
        rect.width,
        closeTo(firstWidth, 0.1),
        reason: '等分档下六段同宽（$label 宽 ${rect.width}）',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
