import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 集合加载失败必须呈现错误态，不能塌成"还没有照片"的空状态。
void main() {
  testWidgets('照片列表加载失败时渲染错误视图而非空状态', (tester) async {
    final repository = _MockPhotoRepository();
    when(
      () => repository.dashboard(),
    ).thenAnswer((_) async => PhotoDashboard.empty());
    when(
      () => repository.listAlbumsPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => PhotoAlbumPage.empty());
    when(
      () => repository.listFavorites(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(
      () => repository.listTrash(),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenThrow(const AppException(code: 'UNAUTHORIZED', message: '当前用户不存在'));

    tester.view.physicalSize = const Size(2560, 1600);
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
        GoRoute(path: '/portal', builder: (context, state) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          photoRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorView), findsOneWidget);
    expect(find.text('还没有照片'), findsNothing);
  });

  test('同因局部错误只保留一条，成功刷新后横幅必须清除', () async {
    final repository = _MockPhotoRepository();
    const sessionLost = AppException(
      code: 'UNAUTHORIZED',
      message: '会话已在其他设备登录',
    );
    // 四个并行加载因同一原因失败，横幅不应把同一句话重复四遍。
    when(() => repository.dashboard()).thenThrow(sessionLost);
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenThrow(sessionLost);
    when(
      () => repository.listFavorites(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenThrow(sessionLost);
    when(
      () => repository.listAlbumsPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenThrow(sessionLost);

    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        photoRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final failed = await container.read(photoCenterControllerProvider.future);
    // 控制器按当前 UI 语言解析错误码，UNAUTHORIZED 走本地化文案而非服务端原文；
    // 这里断言的是四条并发失败被折叠成同一句可展示文案。
    expect(failed.errorMessage, '未登录或登录已过期');

    // 重新登录后成功刷新：copyWith 的 errorMessage 传 null 等于「不修改」，
    // 少了 clearError 横幅会永远留在页面上。
    when(
      () => repository.dashboard(),
    ).thenAnswer((_) async => PhotoDashboard.empty());
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
    when(
      () => repository.listAlbumsPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => PhotoAlbumPage.empty());

    await container.read(photoCenterControllerProvider.notifier).refresh();

    expect(
      container.read(photoCenterControllerProvider).requireValue.errorMessage,
      isNull,
    );
  });
}
