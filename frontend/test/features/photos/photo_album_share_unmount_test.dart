import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_detail_page.dart';

/// 相册分享创建的异步边界（缺陷报告 M-10）。
///
/// 创建链接返回后还要读 `webShareBaseUrlResolverProvider` 拼分享地址；
/// 用户在这一步之前退出页面时，必须先确认页面仍在，否则在已卸载的
/// WidgetRef 上取值会抛 "Using ref when a widget ... unmounted"。
class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async => PhotoCenterState.empty();

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadTimeline({bool force = false}) async {}
}

/// 只计次不返回的基址解析器：用来证明守卫之后根本没有再取 Provider。
class _HangingBaseUrlResolver extends WebShareBaseUrlResolver {
  _HangingBaseUrlResolver(super.ref);

  int resolveCalls = 0;
  final Completer<String> _completer = Completer<String>();

  @override
  Future<String> resolve() async {
    resolveCalls++;
    return _completer.future;
  }
}

void main() {
  testWidgets('创建相册链接返回前退出页面则不再读取分享基址', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MockPhotoRepository();
    when(() => repository.getAlbumDetail(any())).thenAnswer(
      (_) async =>
          PhotoAlbumDetail(album: _album(), photos: const <PhotoItem>[]),
    );
    when(
      () => repository.listAlbumShares(any()),
    ).thenAnswer((_) async => const <PhotoShareLink>[]);
    when(
      () => repository.listAlbumPhotos(
        albumId: any(named: 'albumId'),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    final createCompleter = Completer<PhotoShareLink>();
    when(
      () => repository.createAlbumShare(
        any(),
        password: any(named: 'password'),
        expiresAt: any(named: 'expiresAt'),
        maxAccessCount: any(named: 'maxAccessCount'),
      ),
    ).thenAnswer((_) => createCompleter.future);

    _HangingBaseUrlResolver? resolver;
    final container = ProviderContainer(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        photoCenterControllerProvider.overrideWith(
          () => _FakePhotoCenterController(),
        ),
        webShareBaseUrlResolverProvider.overrideWith(
          (ref) => resolver = _HangingBaseUrlResolver(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/photos/albums/album-1',
      routes: [
        GoRoute(
          path: '/photos',
          builder: (context, state) => const Scaffold(body: SizedBox()),
        ),
        GoRoute(
          path: '/photos/albums/:albumId',
          builder:
              (context, state) => PhotoAlbumDetailPage(
                albumId: state.pathParameters['albumId']!,
              ),
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
    await tester.pumpAndSettle();

    // 顶栏的分享动作是带文字的动作钮，不是纯图标钮。
    await tester.tap(find.text('Share Album'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Link'));
    await tester.pump();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    createCompleter.complete(_link());
    await tester.pumpAndSettle();

    // 守卫生效时根本不会去读分享基址 Provider。
    expect(resolver, isNull);
    expect(tester.takeException(), isNull);
  });
}

PhotoAlbum _album() => PhotoAlbum(
  id: 'album-1',
  name: 'Golden hour',
  description: '',
  photoCount: 0,
  createdAt: DateTime(2024, 11, 1),
  updatedAt: DateTime(2024, 11, 12),
);

PhotoShareLink _link() => PhotoShareLink(
  id: 'share-1',
  token: 'tok-1',
  resourceType: 'ALBUM',
  resourceId: 'album-1',
  accessCount: 0,
  createdAt: DateTime(2024, 11, 12),
);
