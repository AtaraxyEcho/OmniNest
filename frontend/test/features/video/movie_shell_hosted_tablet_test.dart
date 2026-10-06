import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/presentation/widgets/movie_shell.dart';

/// 托管平板宽度（≥1024）的媒体页布局门控测试：
/// 托管态与 Photos/Music/Reader 同规则一律走触屏布局，
/// 不复用桌面侧栏与模块顶栏（宽度只决定触屏内容网格的列数）。
void main() {
  testWidgets('托管态头部返回一次即离开影视模块', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => MobileHostedRoute(
                                  child: MovieShell(
                                    section: MovieSection.movies,
                                    child: const SizedBox(height: 240),
                                  ),
                                ),
                          ),
                        ),
                    child: const Text('媒体库'),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('媒体库'));
    await tester.pumpAndSettle();

    // 非首栏（影片）也只需一次：此前「先回 For you」与调用方的分区历史叠加，
    // 形成 For you ⇄ 影片 乒乓，按多少次都出不了模块。
    await tester.tap(find.byType(MobileGlassIconButton).first);
    await tester.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.dark(),
          // 经 MobileHostedRoute 泵入 = 真实点击链路（根级路由补挂 scope）。
          home: MobileHostedRoute(
            child: MovieShell(
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

  testWidgets('托管分段条为样例四段：For you/Films/Series/Anime', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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
          home: MobileHostedRoute(
            child: MovieShell(
              section: MovieSection.movies,
              child: const SizedBox(height: 240),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 玻璃横幅（样例 module-overlay 头）在场。
    expect(find.text('影视'), findsOneWidget);
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('剧集'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    // 收藏不再占分段位（并入段内 chip）。
    expect(find.text('收藏'), findsNothing);
    expect(tester.takeException(), isNull);
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
