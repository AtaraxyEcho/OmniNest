import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';

/// 伪造的照片中心控制器，返回空状态以避免网络请求
class _FakePhotoCenterController extends PhotoCenterController {
  _FakePhotoCenterController([this.initialState]);

  final PhotoCenterState? initialState;

  @override
  Future<PhotoCenterState> build() async {
    return initialState ?? PhotoCenterState.empty();
  }
}

void main() {
  group('PhotosPage', () {
    testWidgets('renders without crashing', (tester) async {
      // 设置宽屏尺寸以使用桌面布局
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 创建简单的 GoRouter，因为 PhotosPage 的 initState 调用 GoRouter.of(context)
      final router = GoRouter(
        initialLocation: '/photos',
        routes: [
          GoRoute(
            path: '/photos',
            builder: (context, state) => const PhotosPage(),
          ),
          GoRoute(
            path: '/portal',
            builder: (context, state) => const SizedBox(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // 覆盖 session 存储以避免 FlutterSecureStorage 插件依赖
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            presetAppEnvironmentProvider.overrideWithValue(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                wsBaseUrl: 'ws://localhost:8080/ws',
              ),
            ),
            // 覆盖照片控制器以避免网络请求
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
        ),
      );

      // 等待异步 provider 处理
      await tester.pump(const Duration(seconds: 1));

      // 验证页面已渲染
      expect(find.byType(PhotosPage), findsOneWidget);
    });

    testWidgets(
      'desktop layout exposes Frame sidebar, library search and scrollable date grid',
      (tester) async {
        tester.view.physicalSize = const Size(2400, 1200);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final photos = List<PhotoItem>.generate(
          30,
          (index) => PhotoItem(
            id: 'photo-$index',
            fileNodeId: 'file-$index',
            title: 'Photo $index',
            format: 'JPEG',
            fileSize: 1024,
            metadataStatus: 'READY',
            favorite: false,
            createdAt: DateTime(2026, 7, 13),
          ),
        );
        final router = GoRouter(
          initialLocation: '/photos',
          routes: [
            GoRoute(
              path: '/photos',
              builder: (context, state) => const PhotosPage(),
            ),
            GoRoute(
              path: '/portal',
              builder: (context, state) => const SizedBox(),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authSessionStoreProvider.overrideWithValue(
                MemoryAuthSessionStore(),
              ),
              presetAppEnvironmentProvider.overrideWithValue(
                const AppEnvironment(
                  apiBaseUrl: 'http://localhost:8080/api/v1',
                  wsBaseUrl: 'ws://localhost:8080/ws',
                ),
              ),
              photoCenterControllerProvider.overrideWith(
                () => _FakePhotoCenterController(
                  PhotoCenterState.empty().copyWith(photos: photos),
                ),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              theme: OmniNestTheme.from(AppThemePalette.dark),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        expect(find.textContaining('Albums'), findsWidgets);
        expect(find.byType(CustomScrollView), findsOneWidget);
        final scrollable = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        expect(scrollable.physics, isA<AlwaysScrollableScrollPhysics>());
      },
    );

    testWidgets('返回手势按 退出多选→回图库视图→回门户 的顺序处理', (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialState = PhotoCenterState.empty().copyWith(
        isSelectionMode: true,
        frameView: FrameView.timeline,
      );
      final container = ProviderContainer(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          presetAppEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost:8080/api/v1',
              wsBaseUrl: 'ws://localhost:8080/ws',
            ),
          ),
          photoCenterControllerProvider.overrideWith(
            () => _FakePhotoCenterController(initialState),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/photos',
        routes: [
          GoRoute(
            path: '/photos',
            builder: (context, state) => const PhotosPage(),
          ),
          GoRoute(
            path: '/portal',
            builder:
                (context, state) =>
                    const SizedBox(key: Key('portal-destination')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.from(AppThemePalette.dark),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      Future<PhotoCenterState> readState() =>
          container.read(photoCenterControllerProvider.future);

      // 第一次返回：仅退出多选，视图保持时间线。
      await tester.binding.handlePopRoute();
      await tester.pump();
      var state = await readState();
      expect(state.isSelectionMode, isFalse);
      expect(state.frameView, FrameView.timeline);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/photos');

      // 第二次返回：回到图库视图。
      await tester.binding.handlePopRoute();
      await tester.pump();
      state = await readState();
      expect(state.frameView, FrameView.grid);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/photos');

      // 第三次返回：无多选、默认视图且无搜索，回到门户。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/portal');
      expect(find.byKey(const Key('portal-destination')), findsOneWidget);
    });

    testWidgets('batch tag dialog closes via cancel without type error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/photos',
        routes: [
          GoRoute(
            path: '/photos',
            builder: (context, state) => const PhotosPage(),
          ),
          GoRoute(
            path: '/portal',
            builder: (context, state) => const SizedBox(),
          ),
        ],
      );
      addTearDown(router.dispose);
      final selectionState = PhotoCenterState.empty().copyWith(
        isSelectionMode: true,
        selectedPhotoIds: const {'photo-1'},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            presetAppEnvironmentProvider.overrideWithValue(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                wsBaseUrl: 'ws://localhost:8080/ws',
              ),
            ),
            photoCenterControllerProvider.overrideWith(
              () => _FakePhotoCenterController(selectionState),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.from(AppThemePalette.dark),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tag'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('batch bar supports select all and deselect all', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final photos = List<PhotoItem>.generate(
        6,
        (index) => PhotoItem(
          id: 'photo-$index',
          fileNodeId: 'file-$index',
          title: 'Photo $index',
          format: 'JPEG',
          fileSize: 1024,
          metadataStatus: 'READY',
          favorite: false,
          createdAt: DateTime(2026, 7, 13),
        ),
      );
      final router = GoRouter(
        initialLocation: '/photos',
        routes: [
          GoRoute(
            path: '/photos',
            builder: (context, state) => const PhotosPage(),
          ),
          GoRoute(
            path: '/portal',
            builder: (context, state) => const SizedBox(),
          ),
        ],
      );
      addTearDown(router.dispose);
      final selectionState = PhotoCenterState.empty().copyWith(
        photos: photos,
        photoTotalElements: photos.length,
        isSelectionMode: true,
        selectedPhotoIds: const {'photo-0'},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            presetAppEnvironmentProvider.overrideWithValue(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                wsBaseUrl: 'ws://localhost:8080/ws',
              ),
            ),
            photoCenterControllerProvider.overrideWith(
              () => _FakePhotoCenterController(selectionState),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.from(AppThemePalette.dark),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('6 selected'), findsOneWidget);

      await tester.tap(find.text('Deselect all'));
      await tester.pumpAndSettle();
      // 选择集清空后批操作条整体隐藏。
      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Deselect all'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
