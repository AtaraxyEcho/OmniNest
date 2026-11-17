import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/pages/photo_shared_album_page.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

PhotoItem _photo(String id, {String? sourceUrl}) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: id,
    format: 'jpg',
    fileSize: 1024,
    metadataStatus: 'DONE',
    favorite: false,
    createdAt: DateTime.utc(2026, 1, 1),
    sourceUrl: sourceUrl,
  );
}

/// 相册网格内的缩略图入口：顶栏返回钮同样是 InkWell，不限定网格会先命中它。
Finder _thumbnail() =>
    find
        .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
        .first;

void main() {
  Widget wrap(Widget page, PhotoRepository repository) {
    // 分享页挂在应用壳层之外，顶栏返回入口按 go_router 的 canPop/pop 走，
    // 测试宿主必须提供路由，否则与真实运行环境不同形。
    final router = GoRouter(
      initialLocation: '/shared/photos/share-token',
      routes: [
        GoRoute(path: '/portal', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/shared/photos/:token',
          builder: (context, state) => page,
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
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
    );
  }

  /// 访客页只需两张无封面的照片：覆盖层断言只看页码与下载入口，不依赖真实图片解码。
  Future<_MockPhotoRepository> stubAlbum(
    List<PhotoItem> photos, {
    int? total,
  }) async {
    final repository = _MockPhotoRepository();
    when(
      () => repository.authorizeSharedAlbum(
        any(),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => 'share-session');
    when(
      () => repository.accessSharedAlbum(
        any(),
        sessionToken: any(named: 'sessionToken'),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer(
      (_) async => PhotoSharedAlbum(
        albumName: '共享相册',
        photos: photos,
        total: total ?? photos.length,
      ),
    );
    return repository;
  }

  testWidgets('点开缩略图进入覆盖层并显示当前页码', (tester) async {
    final repository = await stubAlbum([_photo('a'), _photo('b')]);
    await tester.pumpWidget(
      wrap(const PhotoSharedAlbumPage(token: 'share-token'), repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(_thumbnail());
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsNothing);
  });

  testWidgets('服务端未签发原图地址时下载入口禁用', (tester) async {
    final repository = await stubAlbum([
      _photo('a'),
      _photo('b', sourceUrl: 'https://files.example.test/b.jpg'),
    ]);
    await tester.pumpWidget(
      wrap(const PhotoSharedAlbumPage(token: 'share-token'), repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(_thumbnail());
    await tester.pumpAndSettle();

    final download = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.download_rounded),
    );
    expect(download.onPressed, isNull);

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();

    final enabled = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.download_rounded),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('覆盖层不追加续页请求', (tester) async {
    final repository = await stubAlbum([_photo('a'), _photo('b')]);
    await tester.pumpWidget(
      wrap(const PhotoSharedAlbumPage(token: 'share-token'), repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(_thumbnail());
    await tester.pumpAndSettle();

    verify(
      () => repository.accessSharedAlbum(
        'share-token',
        sessionToken: 'share-session',
        page: 0,
        size: 50,
      ),
    ).called(1);
  });

  testWidgets('覆盖层显示相册总数并支持键盘左右切换', (tester) async {
    final repository = await stubAlbum([_photo('a'), _photo('b')], total: 5);
    await tester.pumpWidget(
      wrap(const PhotoSharedAlbumPage(token: 'share-token'), repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(_thumbnail());
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
  });
}
