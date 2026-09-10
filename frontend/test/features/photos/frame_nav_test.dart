import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_bottom_nav.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_sidebar.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 伪造的照片中心控制器，返回空状态以避免网络请求
class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState.empty();
  }
}

Widget _wrapFramePage() {
  final router = GoRouter(
    initialLocation: '/photos',
    routes: [
      GoRoute(path: '/photos', builder: (context, state) => const PhotosPage()),
      GoRoute(path: '/portal', builder: (context, state) => const SizedBox()),
    ],
  );
  final repository = _MockPhotoRepository();
  when(
    () => repository.dashboard(),
  ).thenAnswer((_) async => PhotoDashboard.empty());
  when(
    () => repository.listAlbums(),
  ).thenAnswer((_) async => const <PhotoAlbum>[]);
  when(
    () => repository.listPhotos(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(
    () => repository.listFavorites(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(() => repository.listTrash()).thenAnswer((_) async => PhotoPage.empty());
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
      photoRepositoryProvider.overrideWithValue(repository),
      photoCenterControllerProvider.overrideWith(
        () => _FakePhotoCenterController(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: OmniNestTheme.from(AppThemePalette.dark),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size logicalSize) async {
  tester.view.physicalSize = logicalSize * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrapFramePage());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('Frame 导航壳', () {
    testWidgets('宽屏侧栏展开并可在视图间切换', (tester) async {
      await _pumpAt(tester, const Size(1280, 800));

      expect(find.byType(FrameSidebar), findsOneWidget);
      expect(find.byType(FrameBottomNav), findsNothing);
      expect(
        tester.getSize(find.byType(FrameSidebar)).width,
        moreOrLessEquals(AppControlTokens.sidebarWidth),
      );
      expect(find.text('Trash'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('frame-nav-trash')));
      await tester.pumpAndSettle();
      expect(find.text('Trash is empty'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('frame-nav-locations')));
      await tester.pumpAndSettle();
      expect(find.text('No locations yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('frame-nav-favorites')));
      await tester.pumpAndSettle();
      expect(find.text('No favorite photos yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('frame-nav-albums')));
      await tester.pumpAndSettle();
      expect(find.text('New Album'), findsOneWidget);
    });

    testWidgets('顶栏搜索框压缩至设计稿 34px 高度', (tester) async {
      await _pumpAt(tester, const Size(1280, 800));

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.getSize(field).height, moreOrLessEquals(34));
      // prefixIcon 默认 48x48 最小约束会托高输入框，收窄后文字
      // 与图标仍须保持垂直居中，防止压高度时内容上浮。
      final fieldRect = tester.getRect(field);
      final editRect = tester.getRect(find.byType(EditableText));
      expect(
        editRect.center.dy - fieldRect.center.dy,
        moreOrLessEquals(0, epsilon: 0.5),
      );
      final iconRect = tester.getRect(find.byIcon(Icons.search_rounded));
      expect(
        iconRect.center.dy - fieldRect.center.dy,
        moreOrLessEquals(0, epsilon: 0.5),
      );
    });

    testWidgets('宽 1024 以下侧栏折叠为统一宽度且隐藏文字', (tester) async {
      await _pumpAt(tester, const Size(950, 800));

      expect(find.byType(FrameSidebar), findsOneWidget);
      expect(
        tester.getSize(find.byType(FrameSidebar)).width,
        moreOrLessEquals(AppControlTokens.sidebarCollapsedWidth),
      );
      // 折叠态仅保留图标与顶栏标题，侧栏文字与统计全部隐藏。
      expect(find.text('Trash'), findsNothing);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('0 photos'), findsNothing);
    });

    testWidgets('紧凑布局使用底部导航且不渲染侧栏', (tester) async {
      await _pumpAt(tester, const Size(600, 900));

      expect(find.byType(FrameSidebar), findsNothing);
      expect(find.byType(FrameBottomNav), findsOneWidget);
      // 底部导航与设计稿一致，仅五个入口，不含回收站。
      expect(find.byKey(const ValueKey('frame-tab-trash')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('frame-tab-albums')));
      await tester.pumpAndSettle();
      expect(find.text('New Album'), findsOneWidget);
      expect(find.byKey(const ValueKey('frame-tab-trash')), findsNothing);
    });
  });
}
