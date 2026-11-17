import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/presentation/pages/photo_shared_item_page.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 匿名访客页只允许触碰分享接口：读照片中心控制器会连带发出
/// dashboard / 列表 / 收藏 / 影集四个需要登录态的请求。
void main() {
  testWidgets('访客页不触发登录态集合请求', (tester) async {
    final repository = _MockPhotoRepository();
    when(
      () => repository.authorizeSharedPhoto(
        any(),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => 'share-session');
    when(
      () => repository.accessSharedPhoto(
        any(),
        sessionToken: any(named: 'sessionToken'),
      ),
    ).thenThrow(const AppException(code: 'FORBIDDEN', message: '分享会话已失效'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          photoRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const PhotoSharedItemPage(token: 'share-token'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    verify(
      () => repository.authorizeSharedPhoto('share-token', password: null),
    ).called(1);
    verify(
      () => repository.accessSharedPhoto(
        'share-token',
        sessionToken: 'share-session',
      ),
    ).called(1);
    verifyNever(() => repository.dashboard());
    verifyNever(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    );
    verifyNever(
      () => repository.listFavorites(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    );
    verifyNever(
      () => repository.listAlbumsPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    );

    expect(find.byType(AppErrorView), findsOneWidget);
  });
}
