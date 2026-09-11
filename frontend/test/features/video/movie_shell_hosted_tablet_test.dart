import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/presentation/widgets/movie_shell.dart';

/// 托管平板宽度（≥1024）的媒体页布局门控测试：
/// 托管态与 Photos/Music/Reader 同规则一律走触屏布局，
/// 不复用桌面侧栏与模块顶栏（宽度只决定触屏内容网格的列数）。
void main() {
  testWidgets('托管平板宽度使用触屏布局：无桌面顶栏与侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        ],
        child: MobileShellScope(
          hosted: true,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            theme: OmniNestTheme.dark(),
            home: MovieShell(
              section: MovieSection.movies,
              child: const SizedBox(
                key: Key('movie-hosted-content'),
                height: 240,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MovieTopBar), findsNothing, reason: '托管态由壳层顶栏提供标题');
    expect(find.byType(MovieSidebar), findsNothing, reason: '托管态不复用桌面侧栏');
    expect(find.byKey(const Key('movie-hosted-content')), findsOneWidget);
  });

  testWidgets('非托管桌面宽度仍使用桌面顶栏与侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.dark(),
          home: MovieShell(
            section: MovieSection.movies,
              child: const SizedBox(
                key: Key('movie-desktop-content'),
                height: 240,
              ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MovieTopBar), findsOneWidget);
    expect(find.byType(MovieSidebar), findsOneWidget);
    expect(find.byKey(const Key('movie-desktop-content')), findsOneWidget);
  });
}
